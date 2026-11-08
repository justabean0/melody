import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/song.dart';
import 'anti_bot_service.dart';
import 'audio_cache_service.dart';
import 'database_service.dart';
import 'innertube_service.dart';
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
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = (state == PlayerState.playing);
      _stateChangeController.add(null);
    });

    _player.onPositionChanged.listen((pos) {
      _position = pos;
      _positionChangeController.add(pos);
    });

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _stateChangeController.add(null);
    });

    _player.onPlayerComplete.listen((_) {
      _handleTrackEnded();
    });
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
      if (!_queue.any((s) => s.id == song.id)) {
        _queue.add(song);
      }
      _currentIndex = _queue.indexWhere((s) => s.id == song.id);
    }

    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    _currentSong = _queue[_currentIndex];
    _songChangeController.add(_currentSong);
    _isLoading = true;
    _position = Duration.zero;
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

      await _player.stop();

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

      // Auto-mix recommendations when nearing queue completion
      if (_queue.length - _currentIndex <= 2) {
        _fetchAutoMixTracks(_currentSong!.id);
      }
    } catch (e) {
      debugPrint('Playback error resolving audio: $e');
      _isPlaying = false;
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

  void _fetchAutoMixTracks(String videoId) async {
    try {
      final related = await InnerTubeService.getRelatedSongs(videoId);
      for (final s in related) {
        if (!_queue.any((item) => item.id == s.id)) {
          _queue.add(s);
        }
      }
      _stateChangeController.add(null);
    } catch (_) {}
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
      }
    }
    _stateChangeController.add(null);
  }

  void clearQueue() {
    _player.stop();
    _queue.clear();
    _currentSong = null;
    _currentIndex = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _songChangeController.add(null);
    _stateChangeController.add(null);
  }

  void dispose() {
    _player.dispose();
    StreamResolverService.dispose();
    _songChangeController.close();
    _stateChangeController.close();
    _positionChangeController.close();
  }
}
