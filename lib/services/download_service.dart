import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'database_service.dart';
import 'local_audio_service.dart';
import 'log_service.dart';
import 'stream_resolver_service.dart';

/// Lifecycle states for a track's offline download.
enum DownloadStatus {
  notDownloaded,
  downloading,
  downloaded,
  failed,
}

/// Snapshot of a track's download status, progress, and local URI/path.
class TrackDownloadState {
  final DownloadStatus status;
  final double progress;
  final String? filePath;
  final String? errorMessage;

  const TrackDownloadState({
    this.status = DownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.filePath,
    this.errorMessage,
  });

  TrackDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? filePath,
    String? errorMessage,
  }) {
    return TrackDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

typedef TrackDownloader = Future<String?> Function(
  Song song,
  void Function(double progress) onProgress,
);

typedef DownloadStreamResolver = Future<DownloadStreamSelection> Function(Song song);

/// Persistent offline track downloader backed by Android MediaStore (`Music/Melody/`).
class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal()
      : _httpClientOverride = null,
        _localAudioOverride = null,
        _streamResolverOverride = null,
        _tempDirOverride = null {
    downloader = _defaultDownloadPipeline;
  }

  @visibleForTesting
  DownloadService.forTesting({
    this.downloader,
    http.Client? httpClient,
    LocalAudioService? localAudioService,
    DownloadStreamResolver? streamResolver,
    Directory? tempDirectory,
    bool useDefaultPipeline = false,
  })  : _httpClientOverride = httpClient,
        _localAudioOverride = localAudioService,
        _streamResolverOverride = streamResolver,
        _tempDirOverride = tempDirectory {
    if (useDefaultPipeline && downloader == null) {
      downloader = _defaultDownloadPipeline;
    }
  }

  /// Optional downloader implementation hook; initialized to the MediaStore pipeline on the singleton.
  TrackDownloader? downloader;

  final http.Client? _httpClientOverride;
  final LocalAudioService? _localAudioOverride;
  final DownloadStreamResolver? _streamResolverOverride;
  final Directory? _tempDirOverride;

  final Map<String, TrackDownloadState> _states = {};
  final Map<String, String> _songToContentUri = {};
  final Map<String, String> _songToDisplayName = {};

  LocalAudioService get _localAudio => _localAudioOverride ?? LocalAudioService();

  static String _normalizeKey(String title, String artist) {
    final t = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final a = artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '$t::$a';
  }

  static String _sanitizeNamePart(String raw, String fallback) {
    final cleaned = raw
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
  }

  static String expectedBaseNameForSong(Song song) {
    final t = _sanitizeNamePart(song.title, 'Melody Track');
    final a = _sanitizeNamePart(song.artist, 'Unknown Artist');
    return '$t - $a'.toLowerCase();
  }

  /// Hydrates cached download states from [DatabaseService] synchronously at startup.
  void restorePersistedDownloads() {
    final saved = DatabaseService.getDownloadedTracks();
    for (final entry in saved.entries) {
      final contentUri = entry.value['contentUri']?.toString();
      if (contentUri == null || contentUri.isEmpty) continue;
      _songToContentUri[entry.key] = contentUri;
      final displayName = entry.value['displayName']?.toString();
      if (displayName != null && displayName.isNotEmpty) {
        _songToDisplayName[entry.key] = displayName;
      }
      _states[entry.key] = TrackDownloadState(
        status: DownloadStatus.downloaded,
        progress: 1.0,
        filePath: contentUri,
      );
    }
    notifyListeners();
  }

  /// Reconciles tracked downloads with `Music/Melody/` in MediaStore.
  Future<void> reconcileWithMediaStore() async {
    final persisted = DatabaseService.getDownloadedTracks();
    final tracks = await _localAudio.scanLocalAudio(melodyOnly: true);

    if (tracks.isEmpty && persisted.isEmpty) {
      return;
    }

    // If MediaStore returned no Melody tracks while entries were previously persisted,
    // verify whether platform scanning returned anything before pruning in unit tests.
    final byUri = <String, LocalAudioTrack>{};
    final byName = <String, LocalAudioTrack>{};
    final byMeta = <String, LocalAudioTrack>{};
    for (final t in tracks) {
      byUri[t.contentUri] = t;
      if (t.displayName.isNotEmpty) {
        byName[t.displayName.toLowerCase()] = t;
      }
      byMeta[_normalizeKey(t.title, t.artist)] = t;
    }

    final reconciled = <String, Map<String, dynamic>>{};
    bool changed = false;

    for (final entry in persisted.entries) {
      final songId = entry.key;
      final record = entry.value;
      final uri = record['contentUri']?.toString() ?? '';
      final displayName = record['displayName']?.toString().toLowerCase() ?? '';
      final title = record['title']?.toString() ?? '';
      final artist = record['artist']?.toString() ?? '';

      final matched = byUri[uri] ??
          (displayName.isNotEmpty ? byName[displayName] : null) ??
          byMeta[_normalizeKey(title, artist)];

      if (matched != null) {
        reconciled[songId] = {
          ...record,
          'contentUri': matched.contentUri,
          'displayName': matched.displayName,
        };
        _songToContentUri[songId] = matched.contentUri;
        if (matched.displayName.isNotEmpty) {
          _songToDisplayName[songId] = matched.displayName;
        }
        _states[songId] = TrackDownloadState(
          status: DownloadStatus.downloaded,
          progress: 1.0,
          filePath: matched.contentUri,
        );
        if (matched.contentUri != uri) changed = true;
      } else {
        // Track was deleted externally from Music/Melody/
        _songToContentUri.remove(songId);
        _songToDisplayName.remove(songId);
        if (_states[songId]?.status == DownloadStatus.downloaded) {
          _states.remove(songId);
        }
        changed = true;
      }
    }

    if (changed) {
      await DatabaseService.replaceDownloadedTrackRecords(reconciled);
      notifyListeners();
    }
  }

  /// Matches an arbitrary [song] against already scanned or persisted `Music/Melody/` tracks.
  String? localUriFor(Song song) {
    if (song.localUri != null && song.localUri!.trim().isNotEmpty) {
      return song.localUri;
    }
    final state = _states[song.id];
    if (state != null &&
        state.status == DownloadStatus.downloaded &&
        state.filePath != null &&
        state.filePath!.isNotEmpty) {
      return state.filePath;
    }
    final mapped = _songToContentUri[song.id];
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }

    final persisted = DatabaseService.getDownloadedTracks();
    final record = persisted[song.id];
    final uri = record?['contentUri']?.toString();
    if (uri != null && uri.isNotEmpty) {
      return uri;
    }

    // Reinstall fallback: check scanned Melody downloads by filename or title/artist
    final expectedBase = expectedBaseNameForSong(song);
    final metaKey = _normalizeKey(song.title, song.artist);
    for (final track in _localAudio.tracks) {
      if (!track.isMelodyDownload) continue;
      final base = track.displayName.contains('.')
          ? track.displayName
              .substring(0, track.displayName.lastIndexOf('.'))
              .toLowerCase()
          : track.displayName.toLowerCase();
      if (base == expectedBase || _normalizeKey(track.title, track.artist) == metaKey) {
        return track.contentUri;
      }
    }
    return null;
  }

  TrackDownloadState stateFor(String songId) {
    final existing = _states[songId];
    if (existing != null) return existing;

    final persisted = DatabaseService.getDownloadedTracks()[songId];
    final uri = persisted?['contentUri']?.toString();
    if (uri != null && uri.isNotEmpty) {
      return TrackDownloadState(
        status: DownloadStatus.downloaded,
        progress: 1.0,
        filePath: uri,
      );
    }
    return const TrackDownloadState();
  }

  DownloadStatus statusFor(String songId) => stateFor(songId).status;

  double progressFor(String songId) => stateFor(songId).progress;

  bool isDownloaded(String songId) =>
      statusFor(songId) == DownloadStatus.downloaded;

  bool isSongDownloaded(Song song) =>
      song.isLocal || song.hasLocalSource || isDownloaded(song.id) || localUriFor(song) != null;

  Future<Directory> _resolveTempDir() async {
    if (_tempDirOverride != null) return _tempDirOverride;
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  static const int _downloadChunkBytes = 524288; // 512 KB
  static const String _downloadUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0';

  static int _parseContentRangeTotal(String? headerValue) {
    if (headerValue == null || !headerValue.contains('/')) return 0;
    final totalPart = headerValue.split('/').last.trim();
    return int.tryParse(totalPart) ?? 0;
  }

  Future<int> _writeStreamWithTimeout(
    Stream<List<int>> stream,
    IOSink sink,
    void Function(int bytes) onChunkBytes,
  ) async {
    int written = 0;
    await for (final chunk
        in stream.timeout(const Duration(seconds: 15))) {
      if (chunk.isEmpty) continue;
      sink.add(chunk);
      written += chunk.length;
      onChunkBytes(chunk.length);
    }
    return written;
  }

  Future<DownloadStreamSelection> _resolveDownloadSelection(Song song) {
    final resolver = _streamResolverOverride;
    if (resolver != null) return resolver(song);
    return StreamResolverService.resolveDownloadStream(
      song.id,
      songTitle: song.title,
      artist: song.artist,
      client: _httpClientOverride,
    );
  }

  Future<String?> _defaultDownloadPipeline(
    Song song,
    void Function(double progress) onProgress,
  ) async {
    LogService.info(
      'Starting offline download for "${song.title}" (${song.id})',
      tag: 'DownloadService',
    );
    var selection = await _resolveDownloadSelection(song).timeout(
      const Duration(seconds: 25),
    );
    LogService.info(
      'Resolved download stream (${selection.extension}, ${selection.mimeType}) for ${song.id}',
      tag: 'DownloadService',
    );

    final tempDir = await _resolveTempDir();
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final safeId = song.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final tempFile = File(
      p.join(
        tempDir.path,
        'melody_dl_${safeId}_${DateTime.now().millisecondsSinceEpoch}.${selection.extension}',
      ),
    );

    final ownClient = _httpClientOverride == null;
    final client = _httpClientOverride ?? http.Client();
    IOSink? sink;

    try {
      sink = tempFile.openWrite();
      int receivedBytes = 0;
      int totalBytes =
          int.tryParse(Uri.tryParse(selection.url)?.queryParameters['clen'] ?? '') ??
              0;

      void reportProgress() {
        if (totalBytes > 0) {
          final frac = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress((frac * 0.9).clamp(0.01, 0.9));
        } else {
          final pseudo = (receivedBytes / (receivedBytes + 1048576)) * 0.85;
          onProgress(pseudo.clamp(0.01, 0.85));
        }
      }

      final firstReq = http.Request('GET', Uri.parse(selection.url))
        ..headers[HttpHeaders.rangeHeader] = 'bytes=0-${_downloadChunkBytes - 1}'
        ..headers['User-Agent'] = _downloadUserAgent;
      final firstRes =
          await client.send(firstReq).timeout(const Duration(seconds: 12));

      if (firstRes.statusCode == HttpStatus.ok) {
        final headerLen = firstRes.contentLength ?? 0;
        if (headerLen > 0) totalBytes = headerLen;
        await _writeStreamWithTimeout(firstRes.stream, sink, (delta) {
          receivedBytes += delta;
          reportProgress();
        });
      } else if (firstRes.statusCode == HttpStatus.partialContent) {
        final crTotal = _parseContentRangeTotal(
          firstRes.headers[HttpHeaders.contentRangeHeader],
        );
        if (crTotal > 0) totalBytes = crTotal;

        var lastChunkBytes = await _writeStreamWithTimeout(
          firstRes.stream,
          sink,
          (delta) {
            receivedBytes += delta;
            reportProgress();
          },
        );

        bool refreshedStream = false;
        while ((totalBytes > 0 && receivedBytes < totalBytes) ||
            (totalBytes <= 0 && lastChunkBytes >= _downloadChunkBytes)) {
          final rangeStart = receivedBytes;
          final rangeEnd = totalBytes > 0
              ? math.min(
                  receivedBytes + _downloadChunkBytes - 1,
                  totalBytes - 1,
                )
              : receivedBytes + _downloadChunkBytes - 1;

          int chunkBytes = 0;
          bool chunkDone = false;

          for (int attempt = 0; attempt < 3 && !chunkDone; attempt++) {
            try {
              final req = http.Request('GET', Uri.parse(selection.url))
                ..headers[HttpHeaders.rangeHeader] =
                    'bytes=$rangeStart-$rangeEnd'
                ..headers['User-Agent'] = _downloadUserAgent;
              final res =
                  await client.send(req).timeout(const Duration(seconds: 12));

              if (res.statusCode == HttpStatus.partialContent ||
                  res.statusCode == HttpStatus.ok) {
                final nextTotal = _parseContentRangeTotal(
                  res.headers[HttpHeaders.contentRangeHeader],
                );
                if (nextTotal > 0) totalBytes = nextTotal;

                chunkBytes = await _writeStreamWithTimeout(res.stream, sink, (delta) {
                  receivedBytes += delta;
                  reportProgress();
                });
                chunkDone = true;
              } else if (res.statusCode ==
                      HttpStatus.requestedRangeNotSatisfiable &&
                  totalBytes <= 0 &&
                  receivedBytes > 0) {
                await res.stream.drain<void>();
                chunkBytes = 0;
                chunkDone = true;
              } else if ((res.statusCode == HttpStatus.forbidden ||
                      res.statusCode == HttpStatus.gone) &&
                  !refreshedStream) {
                await res.stream.drain<void>();
                refreshedStream = true;
                selection = await _resolveDownloadSelection(song).timeout(
                  const Duration(seconds: 25),
                );
              } else {
                await res.stream.drain<void>();
                if (attempt == 2) {
                  throw HttpException(
                    'Download chunk failed with HTTP ${res.statusCode}',
                    uri: Uri.parse(selection.url),
                  );
                }
              }
            } catch (e) {
              if (attempt == 2) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 350));
            }
          }

          lastChunkBytes = chunkBytes;
          if (chunkBytes <= 0) break;
        }
      } else {
        await firstRes.stream.drain<void>();
        throw HttpException(
          'Download failed with HTTP ${firstRes.statusCode}',
          uri: Uri.parse(selection.url),
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (receivedBytes <= 0 || !await tempFile.exists()) {
        throw StateError('Downloaded stream was empty');
      }

      onProgress(0.95);

      final saved = await _localAudio.saveTrackToMediaStore(
        tempFilePath: tempFile.path,
        title: song.title,
        artist: song.artist,
        extension: selection.extension,
        mimeType: selection.mimeType,
      );

      LogService.info(
        'Saved download to MediaStore: ${saved.displayName} (${saved.contentUri})',
        tag: 'DownloadService',
      );

      await DatabaseService.saveDownloadedTrackRecord(
        songId: song.id,
        contentUri: saved.contentUri,
        displayName: saved.displayName,
        title: song.title,
        artist: song.artist,
      );
      _songToContentUri[song.id] = saved.contentUri;
      _songToDisplayName[song.id] = saved.displayName;

      return saved.contentUri;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      if (ownClient) {
        client.close();
      }
    }
  }

  /// Initiates an offline download for [song] and notifies listeners on state transitions.
  Future<TrackDownloadState> downloadSong(Song song) async {
    final current = stateFor(song.id);
    if (current.status == DownloadStatus.downloading ||
        current.status == DownloadStatus.downloaded) {
      return current;
    }

    final activeDownloader = downloader;
    if (activeDownloader == null) {
      // Preserves safe idle behavior when no downloader is attached in unit harnesses.
      return current;
    }

    _states[song.id] = const TrackDownloadState(
      status: DownloadStatus.downloading,
      progress: 0.0,
    );
    notifyListeners();

    try {
      final savedPath = await activeDownloader(song, (progress) {
        final clamped = progress.clamp(0.0, 1.0);
        _states[song.id] = TrackDownloadState(
          status: DownloadStatus.downloading,
          progress: clamped,
        );
        notifyListeners();
      });

      if (savedPath != null && savedPath.isNotEmpty) {
        final done = TrackDownloadState(
          status: DownloadStatus.downloaded,
          progress: 1.0,
          filePath: savedPath,
        );
        _states[song.id] = done;
        _songToContentUri[song.id] = savedPath;
        notifyListeners();
        return done;
      }

      const failed = TrackDownloadState(
        status: DownloadStatus.failed,
        progress: 0.0,
        errorMessage: 'Download did not produce an output file.',
      );
      _states[song.id] = failed;
      notifyListeners();
      return failed;
    } catch (e) {
      final failed = TrackDownloadState(
        status: DownloadStatus.failed,
        progress: 0.0,
        errorMessage: e.toString(),
      );
      _states[song.id] = failed;
      notifyListeners();
      return failed;
    }
  }

  Future<void> removeDownload(String songId) async {
    final removedState = _states.remove(songId);
    final removedUri = _songToContentUri.remove(songId);
    _songToDisplayName.remove(songId);
    await DatabaseService.removeDownloadedTrackRecord(songId);
    if (removedState != null || removedUri != null) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void setStateForTesting(String songId, TrackDownloadState state) {
    _states[songId] = state;
    if (state.status == DownloadStatus.downloaded && state.filePath != null) {
      _songToContentUri[songId] = state.filePath!;
    }
    notifyListeners();
  }

  @visibleForTesting
  void reset({bool restoreDefaultPipeline = false}) {
    _states.clear();
    _songToContentUri.clear();
    _songToDisplayName.clear();
    downloader = restoreDefaultPipeline ? _defaultDownloadPipeline : null;
    notifyListeners();
  }
}
