import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';

class AudioPermissionStatus {
  final bool granted;
  final bool permanentlyDenied;

  const AudioPermissionStatus({
    required this.granted,
    required this.permanentlyDenied,
  });
}

class LocalAudioTrack {
  final String id;
  final String contentUri;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final int dateAdded;
  final String relativePath;
  final String displayName;
  final bool isMelodyDownload;
  final String? albumArtUri;

  const LocalAudioTrack({
    required this.id,
    required this.contentUri,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs = 0,
    this.dateAdded = 0,
    this.relativePath = '',
    this.displayName = '',
    this.isMelodyDownload = false,
    this.albumArtUri,
  });

  factory LocalAudioTrack.fromMap(Map<dynamic, dynamic> map) {
    final durationRaw = map['durationMs'];
    final dateRaw = map['dateAdded'];
    return LocalAudioTrack(
      id: map['id']?.toString() ?? '',
      contentUri: map['contentUri']?.toString() ?? '',
      title: (map['title']?.toString() ?? '').trim().isNotEmpty
          ? map['title'].toString().trim()
          : 'Unknown Track',
      artist: (map['artist']?.toString() ?? '').trim().isNotEmpty
          ? map['artist'].toString().trim()
          : 'Unknown Artist',
      album: map['album']?.toString(),
      durationMs: durationRaw is int
          ? durationRaw
          : int.tryParse(durationRaw?.toString() ?? '') ?? 0,
      dateAdded: dateRaw is int
          ? dateRaw
          : int.tryParse(dateRaw?.toString() ?? '') ?? 0,
      relativePath: map['relativePath']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      isMelodyDownload: map['isMelodyDownload'] == true,
      albumArtUri: map['albumArtUri']?.toString(),
    );
  }

  Song toSong() {
    return Song(
      id: 'local_$id',
      title: title,
      artist: artist,
      album: album,
      duration: durationMs > 0 ? (durationMs / 1000).round() : 0,
      thumbnailUrl: albumArtUri ?? '',
      localUri: contentUri,
      isLocal: true,
    );
  }
}

class MediaStoreSaveResult {
  final String contentUri;
  final String displayName;
  final String relativePath;

  const MediaStoreSaveResult({
    required this.contentUri,
    required this.displayName,
    required this.relativePath,
  });
}

class LocalAudioService extends ChangeNotifier {
  static final LocalAudioService _instance = LocalAudioService._internal();
  factory LocalAudioService() => _instance;
  LocalAudioService._internal() : _channel = const MethodChannel(channelName);

  @visibleForTesting
  LocalAudioService.forTesting({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.melody.music/local_audio';

  final MethodChannel _channel;

  List<LocalAudioTrack> _tracks = const [];
  List<LocalAudioTrack> get tracks => List.unmodifiable(_tracks);

  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;

  bool _isPermanentlyDenied = false;
  bool get isPermanentlyDenied => _isPermanentlyDenied;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Future<bool> hasAudioPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('hasAudioPermission');
      _hasPermission = res ?? false;
      return _hasPermission;
    } on MissingPluginException {
      return _hasPermission;
    } catch (_) {
      return false;
    }
  }

  Future<AudioPermissionStatus> getPermissionStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAudioPermissionStatus',
      );
      final granted = raw?['granted'] == true;
      final permanentlyDenied = raw?['permanentlyDenied'] == true;
      _hasPermission = granted;
      _isPermanentlyDenied = permanentlyDenied;
      notifyListeners();
      return AudioPermissionStatus(
        granted: granted,
        permanentlyDenied: permanentlyDenied,
      );
    } on MissingPluginException {
      return AudioPermissionStatus(
        granted: _hasPermission,
        permanentlyDenied: _isPermanentlyDenied,
      );
    } catch (_) {
      return AudioPermissionStatus(
        granted: _hasPermission,
        permanentlyDenied: _isPermanentlyDenied,
      );
    }
  }

  Future<AudioPermissionStatus> requestAudioPermission() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'requestAudioPermission',
      );
      final granted = raw?['granted'] == true;
      final permanentlyDenied = raw?['permanentlyDenied'] == true;
      _hasPermission = granted;
      _isPermanentlyDenied = permanentlyDenied;
      notifyListeners();
      if (granted) {
        await scanLocalAudio();
      }
      return AudioPermissionStatus(
        granted: granted,
        permanentlyDenied: permanentlyDenied,
      );
    } on MissingPluginException {
      return const AudioPermissionStatus(
        granted: false,
        permanentlyDenied: false,
      );
    } catch (_) {
      return AudioPermissionStatus(
        granted: _hasPermission,
        permanentlyDenied: _isPermanentlyDenied,
      );
    }
  }

  Future<bool> openAppSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openAppSettings');
      return res ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<LocalAudioTrack>> scanLocalAudio({bool melodyOnly = false}) async {
    _isScanning = !melodyOnly;
    if (!melodyOnly) notifyListeners();
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>(
        'scanLocalAudio',
        {'melodyOnly': melodyOnly},
      );
      final parsed = (rawList ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(LocalAudioTrack.fromMap)
          .where((t) => t.contentUri.isNotEmpty)
          .toList();
      if (!melodyOnly) {
        _tracks = parsed;
      }
      return parsed;
    } on MissingPluginException {
      return melodyOnly ? const [] : _tracks;
    } catch (_) {
      return melodyOnly ? const [] : _tracks;
    } finally {
      if (!melodyOnly) {
        _isScanning = false;
        notifyListeners();
      }
    }
  }

  Future<MediaStoreSaveResult> saveTrackToMediaStore({
    required String tempFilePath,
    required String title,
    required String artist,
    required String extension,
    required String mimeType,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'saveTrackToMediaStore',
      {
        'tempFilePath': tempFilePath,
        'title': title,
        'artist': artist,
        'extension': extension,
        'mimeType': mimeType,
      },
    );
    if (raw == null || (raw['contentUri']?.toString().isEmpty ?? true)) {
      throw StateError('MediaStore did not return a saved content URI');
    }
    final result = MediaStoreSaveResult(
      contentUri: raw['contentUri'].toString(),
      displayName: raw['displayName']?.toString() ?? '$title - $artist.$extension',
      relativePath: raw['relativePath']?.toString() ?? 'Music/Melody/',
    );
    // Refresh scanned tracks if permission is already granted so the Local tab updates immediately
    if (_hasPermission) {
      await scanLocalAudio();
    } else {
      notifyListeners();
    }
    return result;
  }

  @visibleForTesting
  void setTracksForTesting(
    List<LocalAudioTrack> tracks, {
    bool hasPermission = true,
    bool isPermanentlyDenied = false,
  }) {
    _tracks = List.unmodifiable(tracks);
    _hasPermission = hasPermission;
    _isPermanentlyDenied = isPermanentlyDenied;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _tracks = const [];
    _hasPermission = false;
    _isPermanentlyDenied = false;
    _isScanning = false;
    notifyListeners();
  }
}
