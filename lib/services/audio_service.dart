import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/song.dart';
import 'anti_bot_service.dart';
import 'audio_cache_service.dart';
import 'database_service.dart';
import 'stream_resolver_service.dart';

enum MelodyLoopMode { off, all, one }

class MelodyAudioService {
  static final MelodyAudioService _instance = MelodyAudioService._internal();
  factory MelodyAudioService() => _instance;
  MelodyAudioService._internal();

  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  final List<Song> _queue = [];
  List<Song> get queue => List.unmodifiable(_queue);

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  MelodyLoopMode _loopMode = MelodyLoopMode.off;
  MelodyLoopMode get loopMode => _loopMode;

  bool _isShuffle = false;
  bool get isShuffle => _isShuffle;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  final _songChangeController = StreamController<Song?>.broadcast();
  Stream<Song?> get onSongChange => _songChangeController.stream;

  final _stateChangeController = StreamController<void>.broadcast();
  Stream<void> get onStateChange => _stateChangeController.stream;

  final _positionChangeController = StreamController<Duration>.broadcast();
  Stream<Duration> get onPositionChange => _positionChangeController.stream;

  void init() {
    // Configure audio context to keep playing cleanly in background
    _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
        ),
      ),
    );

    // Persistent playback notification channel actions
    const MethodChannel('com.melody.music/playback').setMethodCallHandler((call) async {
      if (call.method == 'onNotificationAction') {
        final action = call.arguments as String?;
        if (action == null) return;
        if (action.startsWith('seek:')) {
          final ms = int.tryParse(action.substring(5)) ?? 0;
          await seek(Duration(milliseconds: ms));
          return;
        }
        switch (action) {
          case 'playPause':
            await togglePlayPause();
            break;
          case 'next':
            await playNext();
            break;
          case 'prev':
            await playPrevious();
            break;
        }
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = (state == PlayerState.playing);
      _updateNotification();
      _stateChangeController.add(null);
    });

    _player.onPositionChanged.listen((pos) {
      if (!_isLoading) {
        _position = pos;
        _positionChangeController.add(pos);
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (dur > Duration.zero) {
        _duration = dur;
        _updateNotification();
        _stateChangeController.add(null);
      }
    });

    _player.onPlayerComplete.listen((_) {
      _handleTrackEnded();
    });
  }

  void _updateNotification() {
    if (_currentSong == null) {
      try {
        const MethodChannel('com.melody.music/playback').invokeMethod('hideNotification');
      } catch (_) {}
      return;
    }
    try {
      final durMs = _duration.inMilliseconds > 0
          ? _duration.inMilliseconds
          : (_currentSong!.duration * 1000);
      const MethodChannel('com.melody.music/playback').invokeMethod('showNotification', {
        'title': _currentSong!.title,
        'artist': _currentSong!.artist,
        'isPlaying': _isPlaying,
        'thumbnailUrl': _currentSong!.thumbnailUrl,
        'durationMs': durMs,
        'positionMs': _position.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue, int? startIndex}) async {
    AntiBotService.recordPlay(videoId: song.id);
    if (contextQueue != null && contextQueue.isNotEmpty) {
      _queue.clear();
      _queue.addAll(contextQueue);
      _currentIndex = startIndex ?? _queue.indexWhere((s) => s.id == song.id);
      if (_currentIndex == -1) {
        _queue.insert(0, song);
        _currentIndex = 0;
      }
    } else {
      // Single song played by user: start fresh with this song as the active track
      _queue.clear();
      _queue.add(song);
      _currentIndex = 0;
    }

    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    // 1. Immediately cut off old audio so it stops playing right away
    await _player.stop();

    _currentSong = _queue[_currentIndex];

    // 2. Immediately reset position and initialize duration to current song metadata
    _position = Duration.zero;
    _duration = Duration(seconds: _currentSong!.duration);
    _isLoading = true;

    // Update notification immediately with new song info and duration
    _updateNotification();

    // 3. Immediately broadcast to UI so all sliders and timestamps reset instantly
    _positionChangeController.add(Duration.zero);
    _songChangeController.add(_currentSong);
    _stateChangeController.add(null);

    // Save to local history
    DatabaseService.addToHistory(_currentSong!);

    try {
      // 1. Resolve audio stream with instant cache check & hybrid fast path
      String streamUrl = await StreamResolverService.resolveAudioStreamUrl(
        _currentSong!.id,
        songTitle: _currentSong!.title,
        artist: _currentSong!.artist,
        optimistic: true,
      );

      // 2. Local Disk Cache & 5s Head Proxy mapping
      String playableUrl = AudioCacheService.getPlayableUrl(_currentSong!.id, streamUrl);

      try {
        if (!playableUrl.startsWith('http://') && !playableUrl.startsWith('https://')) {
          await _player.play(DeviceFileSource(playableUrl));
        } else {
          await _player.play(UrlSource(playableUrl));
        }
      } catch (playError) {
        debugPrint('Optimistic play error ($playError). Retrying with safe probed stream...');
        StreamResolverService.invalidateCache(_currentSong!.id);

        // Safe fallback retry with active probe & alternative track lookup
        streamUrl = await StreamResolverService.resolveAudioStreamUrl(
          _currentSong!.id,
          songTitle: _currentSong!.title,
          artist: _currentSong!.artist,
          optimistic: false,
        );
        playableUrl = AudioCacheService.getPlayableUrl(_currentSong!.id, streamUrl);

        if (!playableUrl.startsWith('http://') && !playableUrl.startsWith('https://')) {
          await _player.play(DeviceFileSource(playableUrl));
        } else {
          await _player.play(UrlSource(playableUrl));
        }
      }

      // 3. NEXT-TRACK PRE-FETCHING:
      // In the background, pre-resolve next track stream & pre-cache its 5-second head
      _triggerNextTrackPrefetch();
      _updateNotification();
    } catch (e) {
      debugPrint('Playback error resolving audio: $e');
      _isPlaying = false;
      _updateNotification();
    } finally {
      _isLoading = false;
      _stateChangeController.add(null);
    }
  }

  void _triggerNextTrackPrefetch() {
    if (_currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[_currentIndex + 1];
      unawaited(_prefetchTrack(nextTrack));
    }
  }

  Future<void> _prefetchTrack(Song song) async {
    try {
      debugPrint('AudioService: Pre-fetching next track in queue: "${song.title}" (${song.id})');
      final url = await StreamResolverService.resolveAudioStreamUrl(
        song.id,
        songTitle: song.title,
        artist: song.artist,
        optimistic: true,
      );
      // Pre-cache first 5-8 seconds (~128KB) to disk
      await AudioCacheService.prefetchHead(song.id, url);
    } catch (e) {
      debugPrint('Next-track prefetch error for ${song.id}: $e');
    }
  }

  void _handleTrackEnded() {
    if (_loopMode == MelodyLoopMode.one) {
      _player.seek(Duration.zero);
      _player.resume();
    } else if (hasNext) {
      playNext();
    } else if (_loopMode == MelodyLoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      _playCurrent();
    } else {
      _isPlaying = false;
      _updateNotification();
      _stateChangeController.add(null);
    }
  }

  bool get hasNext => _currentIndex + 1 < _queue.length;
  bool get hasPrev => _currentIndex > 0;

  Future<void> playNext() async {
    if (hasNext) {
      _currentIndex++;
      await _playCurrent();
    }
  }

  Future<void> playPrevious() async {
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
    } else if (hasPrev) {
      _currentIndex--;
      await _playCurrent();
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    _stateChangeController.add(null);
  }

  Future<void> seek(Duration position) async {
    _position = position;
    await _player.seek(position);
    _updateNotification();
    _stateChangeController.add(null);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.isNotEmpty && _currentSong != null) {
      final current = _currentSong!;
      final rest = _queue.where((s) => s.id != current.id).toList()..shuffle();
      _queue.clear();
      _queue.add(current);
      _queue.addAll(rest);
      _currentIndex = 0;
    }
    _stateChangeController.add(null);
  }

  void cycleLoopMode() {
    switch (_loopMode) {
      case MelodyLoopMode.off:
        _loopMode = MelodyLoopMode.all;
        break;
      case MelodyLoopMode.all:
        _loopMode = MelodyLoopMode.one;
        break;
      case MelodyLoopMode.one:
        _loopMode = MelodyLoopMode.off;
        break;
    }
    _stateChangeController.add(null);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _player.setPlaybackRate(speed);
    _stateChangeController.add(null);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex < _queue.length) {
        _playCurrent();
      } else if (_queue.isNotEmpty) {
        _currentIndex = 0;
        _playCurrent();
      } else {
        _player.stop();
        _currentSong = null;
        _currentIndex = -1;
        _updateNotification();
      }
    }
    _stateChangeController.add(null);
  }

  void addToQueue(Song song) {
    if (!_queue.any((s) => s.id == song.id)) {
      _queue.add(song);
      if (_currentSong == null) {
        _currentIndex = 0;
        _playCurrent();
      } else {
        _stateChangeController.add(null);
      }
    }
  }

  void playNextInQueue(Song song) {
    final existingIdx = _queue.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1 && existingIdx != _currentIndex) {
      _queue.removeAt(existingIdx);
      if (existingIdx < _currentIndex) _currentIndex--;
    }

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, song);
    } else {
      _queue.add(song);
      _currentIndex = 0;
      _playCurrent();
      return;
    }
    _stateChangeController.add(null);
  }

  void clearQueue() {
    if (_currentSong != null) {
      _queue.clear();
      _queue.add(_currentSong!);
      _currentIndex = 0;
    } else {
      _queue.clear();
      _currentIndex = -1;
    }
    _stateChangeController.add(null);
  }

  void dispose() {
    try {
      const MethodChannel('com.melody.music/playback').invokeMethod('hideNotification');
    } catch (_) {}
    _player.dispose();
    StreamResolverService.dispose();
    _songChangeController.close();
    _stateChangeController.close();
    _positionChangeController.close();
  }
}
