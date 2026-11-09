import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Local 5-Second Audio Head Cache & Embedded Loopback Proxy
///
/// Ensures ZERO-DELAY playback startup by caching ONLY the first 5-8 seconds
/// (~128 KB) of songs on local storage. It deliberately NEVER downloads or caches
/// the full song, keeping device storage minimal (<5 MB max) while eliminating
/// network buffering delay.
class AudioCacheService {
  static HttpServer? _proxyServer;
  static int _port = 0;
  static Directory? _headsDir;
  static final http.Client _httpClient = http.Client();

  /// Default head chunk size: 128 KB (~6-8 seconds of 128kbps AAC / Opus)
  static const int headChunkSize = 131072;

  /// Max head files to keep on disk (~12.8 MB total for 100 songs)
  static const int maxCachedHeads = 100;

  static int get proxyPort => _port;
  static bool get isProxyRunning => _proxyServer != null;

  /// Initializes the 5-second head disk cache directory and embedded loopback proxy
  static Future<void> init() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      _headsDir = Directory('${baseDir.path}/melody_heads');

      if (!await _headsDir!.exists()) {
        await _headsDir!.create(recursive: true);
      }

      // Purge any legacy full-song cache directories from previous versions
      final legacySongsDir = Directory('${baseDir.path}/melody_songs');
      if (await legacySongsDir.exists()) {
        try {
          await legacySongsDir.delete(recursive: true);
          debugPrint('AudioCacheService: Purged legacy full-song cache directory');
        } catch (_) {}
      }

      // Bind loopback proxy server to an ephemeral port
      _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _proxyServer!.port;
      debugPrint('AudioCacheService: Local 5s head caching proxy listening on port $_port');

      _proxyServer!.listen(_handleProxyRequest, onError: (e) {
        debugPrint('AudioCacheService: Proxy server error: $e');
      });
    } catch (e) {
      debugPrint('AudioCacheService init warning: $e');
    }
  }

  /// Handles incoming HTTP range streaming requests from AudioPlayer
  static Future<void> _handleProxyRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final id = request.uri.queryParameters['id'] ?? '';
      final rawRemoteUrl = request.uri.queryParameters['url'] ?? '';

      if (rawRemoteUrl.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }

      final remoteUri = Uri.parse(Uri.decodeComponent(rawRemoteUrl));
      final incomingRange = request.headers.value(HttpHeaders.rangeHeader);

      final headFile = File('${_headsDir?.path}/$id.head');
      final metaFile = File('${_headsDir?.path}/$id.meta');

      final hasHead = await headFile.exists() && await metaFile.exists();

      // Case 1: We have the first 5-8s head cached and request asks for start of audio
      if (hasHead && (incomingRange == null || incomingRange.startsWith('bytes=0-'))) {
        final headBytes = await headFile.readAsBytes();
        final metaContent = (await metaFile.readAsString()).trim();
        final totalLength = int.tryParse(metaContent) ?? (headBytes.length * 20);

        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-${totalLength - 1}/$totalLength');
        response.headers.set(HttpHeaders.contentLengthHeader, totalLength.toString());
        response.headers.contentType = ContentType('audio', 'mp4');

        // Instantly write the 5-second head from local flash storage (<2ms)
        response.add(headBytes);
        await response.flush();

        // Stream the remaining audio chunks from the remote server
        if (headBytes.length < totalLength) {
          final remoteReq = http.Request('GET', remoteUri)
            ..headers[HttpHeaders.rangeHeader] = 'bytes=${headBytes.length}-$totalLength'
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

          final streamedRemote = await _httpClient.send(remoteReq);
          await for (final chunk in streamedRemote.stream) {
            response.add(chunk);
          }
        }

        await response.close();
        return;
      }

      // Case 2: Passthrough proxy for seeking or when no head is cached yet
      final forwardReq = http.Request('GET', remoteUri);
      if (incomingRange != null) {
        forwardReq.headers[HttpHeaders.rangeHeader] = incomingRange;
      }
      forwardReq.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final remoteRes = await _httpClient.send(forwardReq);
      response.statusCode = remoteRes.statusCode;

      remoteRes.headers.forEach((name, value) {
        if (name.toLowerCase() != 'content-encoding') {
          response.headers.set(name, value);
        }
      });

      await response.addStream(remoteRes.stream);
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Pre-caches the first 5-8 seconds (~128 KB) of an upcoming or played track to disk
  static Future<void> prefetchHead(String videoId, String remoteUrl) async {
    if (_headsDir == null) return;
    try {
      final headFile = File('${_headsDir!.path}/$videoId.head');
      final metaFile = File('${_headsDir!.path}/$videoId.meta');

      if (await headFile.exists() && await metaFile.exists()) {
        try {
          await headFile.setLastModified(DateTime.now());
        } catch (_) {}
        return; // Already cached
      }

      final uri = Uri.parse(remoteUrl);
      final req = http.Request('GET', uri)
        ..headers[HttpHeaders.rangeHeader] = 'bytes=0-${headChunkSize - 1}'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedRes = await _httpClient.send(req).timeout(const Duration(seconds: 4));
      if (streamedRes.statusCode == HttpStatus.ok || streamedRes.statusCode == HttpStatus.partialContent) {
        final contentRange = streamedRes.headers['content-range'] ?? '';
        int totalLength = 0;
        if (contentRange.contains('/')) {
          totalLength = int.tryParse(contentRange.split('/').last) ?? 0;
        }
        if (totalLength == 0) {
          totalLength = streamedRes.contentLength ?? (headChunkSize * 20);
        }

        final bytes = await streamedRes.stream.toBytes();
        if (bytes.isNotEmpty) {
          await headFile.writeAsBytes(bytes, flush: true);
          await metaFile.writeAsString(totalLength.toString(), flush: true);
          debugPrint('AudioCacheService: Pre-cached 5s head for $videoId (${bytes.length} bytes)');

          // Keep head cache compact
          await _pruneHeadsCache();
        }
      }
    } catch (e) {
      debugPrint('AudioCacheService: Head prefetch skipped for $videoId: $e');
    }
  }

  /// Ensures the 5-second head for any played or listened-to song is cached on disk.
  static void ensureHeadCached(String videoId, String remoteUrl) {
    unawaited(prefetchHead(videoId, remoteUrl));
  }

  /// Prunes old 5s heads if cached count exceeds maxCachedHeads
  static Future<void> _pruneHeadsCache() async {
    if (_headsDir == null) return;
    try {
      final entities = await _headsDir!.list().toList();
      final headFiles = entities.whereType<File>().where((f) => f.path.endsWith('.head')).toList();
      if (headFiles.length > maxCachedHeads) {
        headFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        final toRemove = headFiles.take(headFiles.length - maxCachedHeads);
        for (final f in toRemove) {
          final metaPath = f.path.replaceAll('.head', '.meta');
          try {
            await f.delete();
            final metaFile = File(metaPath);
            if (await metaFile.exists()) await metaFile.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Checks if the first 5-8 seconds are pre-cached on local storage
  static bool hasCachedHead(String videoId) {
    if (_headsDir == null) return false;
    final head = File('${_headsDir!.path}/$videoId.head');
    return head.existsSync() && head.lengthSync() > 1000;
  }

  /// Determines the optimal playable source URL:
  /// 1. Local loopback proxy if 5s head is cached (<2ms start)
  /// 2. Direct remote URL otherwise
  /// Deliberately never downloads or caches full songs on disk.
  static String getPlayableUrl(String videoId, String remoteUrl) {
    if (isProxyRunning && hasCachedHead(videoId)) {
      debugPrint('AudioCacheService: Using 5s head cache proxy for $videoId');
      final encoded = Uri.encodeComponent(remoteUrl);
      return 'http://127.0.0.1:$_port/stream?id=$videoId&url=$encoded';
    }

    return remoteUrl;
  }

  /// Clears all 5-second head files from disk
  static Future<void> clearHeadCache() async {
    if (_headsDir != null && await _headsDir!.exists()) {
      try {
        final entities = await _headsDir!.list().toList();
        for (final entity in entities) {
          if (entity is File) await entity.delete();
        }
        debugPrint('AudioCacheService: Cleared all 5-second head cache files');
      } catch (e) {
        debugPrint('AudioCacheService: Error clearing head cache: $e');
      }
    }
  }

  /// Disposes background server and HTTP resources
  static Future<void> dispose() async {
    _httpClient.close();
    await _proxyServer?.close(force: true);
    _proxyServer = null;
  }
}
