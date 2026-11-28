import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'anti_bot_service.dart';
import 'audio_cache_service.dart';
import 'database_service.dart';
import 'download_service.dart';
import 'log_service.dart';
import 'recommendation_service.dart';
import 'stream_resolver_service.dart';

enum MelodyLoopMode { off, all, one }

class MelodyAudioService {
  static MelodyAudioService? _instance;
  factory MelodyAudioService() => _instance ??= MelodyAudioService._internal();
  MelodyAudioService._internal() : _player = AudioPlayer();

  static void flushActiveListeningStats() {
    _instance?.flushListeningStats();
  }

  @visibleForTesting
  MelodyAudioService.forTesting({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  AudioPlayer get player => _player;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  final List<Song> _queue = [];
  List<Song> get queue => List.unmodifiable(_queue);

  final Set<String> _userQueuedIds = {};
  final Set<String> _autoplayQueuedIds = {};
  final Set<String> _sessionPlayedIds = {};
  final Set<String> _sessionPlayedNormalizedKeys = {};
  bool _autoplayClearedByUser = false;
  bool _isDisposed = false;
  Future<List<Song>>? _inflightAutoplayFuture;
  String? _inflightAutoplaySeedId;

  /// Optional test override for autoplay recommendation resolution.
  @visibleForTesting
  Future<List<Song>> Function(
    Song seedSong, {
    Set<String> excludeIds,
    Set<String> excludeNormalizedKeys,
  })? autoplayFetcherOverride;

  /// Returns true if [songId] was explicitly queued by the user.
  bool isUserQueued(String songId) => _userQueuedIds.contains(songId);

  /// Returns true if [songId] was added by smart autoplay.
  bool isAutoplayQueued(String songId) => _autoplayQueuedIds.contains(songId);

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  MelodyLoopMode _loopMode = MelodyLoopMode.off;
  MelodyLoopMode get loopMode => _loopMode;

  bool _isShuffle = false;
  bool get isShuffle => _isShuffle;

  bool _skipSilence = false;
  bool get skipSilence => _skipSilence;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  bool _isPausedByUser = false;
  bool get isPausedByUser => _isPausedByUser;

  bool _needsStreamRecovery = false;
  bool get needsStreamRecovery => _needsStreamRecovery;

  bool _hasHandledCompletion = false;

  int _recoveryAttempts = 0;
  Duration _lastRecoveryPosition = Duration.zero;
  int _playOperationToken = 0;
  int get playOperationToken => _playOperationToken;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  Duration _lastTrackedPosition = Duration.zero;
  int _pendingListeningMs = 0;
  Song? _activeSessionSong;
  String? _activeSessionKey;

  final _songChangeController = StreamController<Song?>.broadcast();
  Stream<Song?> get onSongChange => _songChangeController.stream;

  final _stateChangeController = StreamController<void>.broadcast();
  Stream<void> get onStateChange => _stateChangeController.stream;

  final _positionChangeController = StreamController<Duration>.broadcast();
  Stream<Duration> get onPositionChange => _positionChangeController.stream;

  void init() {
    unawaited(_initAudioSession());
    unawaited(setSkipSilence(DatabaseService.getSkipSilence()));

    // Persistent playback notification channel actions
    const MethodChannel('com.melody.music/playback').setMethodCallHandler((call) async {
      debugPrint('AudioService: onMethodCall: ${call.method}, args: ${call.arguments}');
      if (call.method == 'onNotificationAction') {
        final action = call.arguments as String?;
        if (action == null) return;
        if (action == 'idleTeardown') {
          await _handleIdleTeardown();
          return;
        }
        if (action.startsWith('seek:')) {
          final ms = int.tryParse(action.substring(5)) ?? 0;
          await seek(Duration(milliseconds: ms));
          return;
        }
        switch (action) {
          case 'play':
            await resume();
            break;
          case 'pause':
            await pause();
            break;
          case 'stop':
            await stop();
            break;
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

    _player.playerStateStream.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state.playing && state.processingState != ProcessingState.completed;

      if (state.processingState == ProcessingState.ready && !_isLoading) {
        _hasHandledCompletion = false;
      }

      if (state.processingState == ProcessingState.completed && !_isLoading) {
        _captureListeningProgress(_player.position, maxDeltaMs: 5000);
        _flushListeningTime();
        if (!_hasHandledCompletion) {
          _hasHandledCompletion = true;
          _handleTrackEnded();
        }
      }

      if (wasPlaying != _isPlaying) {
        if (!_isPlaying) {
          _captureListeningProgress(_player.position, maxDeltaMs: 5000);
          _flushListeningTime();
        }
        _position = _player.position;
        _updateNotification();
        _stateChangeController.add(null);
      }
    });

    _player.positionStream.listen((pos) {
      if (!_isLoading) {
        if (_isPlaying) {
          _captureListeningProgress(pos, maxDeltaMs: 2500);
          if (_pendingListeningMs >= 10000) {
            _flushListeningTime();
          }
        }
        _lastTrackedPosition = pos;
        _position = pos;
        _positionChangeController.add(pos);
      }
    });

    _player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _duration = dur;
        _position = _player.position;
        if (_currentSong != null && _currentSong!.duration <= 0) {
          final updatedSong = _currentSong!.copyWith(duration: dur.inSeconds);
          _currentSong = updatedSong;
          if (_currentIndex >= 0 && _currentIndex < _queue.length) {
            _queue[_currentIndex] = updatedSong;
          }
          _songChangeController.add(updatedSong);
        }
        _updateNotification();
        _stateChangeController.add(null);
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    } catch (e) {
      debugPrint('AudioSession init warning: $e');
    }
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

  AudioSource _createAudioSource(String url) {
    if (url.startsWith('content://') || url.startsWith('file://')) {
      return AudioSource.uri(Uri.parse(url));
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return AudioSource.file(url);
    }
    return AudioSource.uri(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );
  }

  String? _resolvePlayableLocalUri(Song song) {
    final direct = song.localUri?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final downloaded = DownloadService().localUriFor(song);
    if (downloaded != null && downloaded.trim().isNotEmpty) {
      return downloaded.trim();
    }
    return null;
  }

  void _logPlayerException(dynamic error, String url) {
    String host = '';
    String path = '';
    String itag = '';
    try {
      final uri = Uri.parse(url);
      host = uri.host;
      path = uri.path;
      itag = uri.queryParameters['itag'] ?? '';
    } catch (_) {}

    if (error is PlayerException) {
      LogService.error(
        'PlayerException: code=${error.code}, message="${error.message}", host=$host, path=$path, itag=$itag',
        tag: 'AudioPlayer',
      );
    } else {
      LogService.warning(
        'Playback error: $error, host=$host, path=$path, itag=$itag',
        tag: 'AudioPlayer',
      );
    }
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue, int? startIndex}) async {
    AntiBotService.recordPlay(videoId: song.id);
    _isPausedByUser = false;
    _needsStreamRecovery = false;
    _recoveryAttempts = 0;
    _userQueuedIds.clear();
    _autoplayQueuedIds.clear();
    _autoplayClearedByUser = false;

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

  Future<void> playQueue(List<Song> queue, {int startIndex = 0}) async {
    if (queue.isEmpty) return;
    _isPausedByUser = false;
    _needsStreamRecovery = false;
    _recoveryAttempts = 0;
    _userQueuedIds.clear();
    _autoplayQueuedIds.clear();
    _autoplayClearedByUser = false;

    _queue.clear();
    _queue.addAll(queue);
    _currentIndex = (startIndex >= 0 && startIndex < _queue.length) ? startIndex : 0;

    await _playCurrent();
  }

  void _captureListeningProgress(Duration pos, {int maxDeltaMs = 2500}) {
    final deltaMs = (pos - _lastTrackedPosition).inMilliseconds;
    if (deltaMs > 0 && deltaMs <= maxDeltaMs) {
      _pendingListeningMs += deltaMs;
    }
    _lastTrackedPosition = pos;
  }

  /// Flushes accumulated listening seconds immediately to persistent daily/monthly stats.
  void flushListeningStats() {
    if (_isPlaying) {
      _captureListeningProgress(_player.position, maxDeltaMs: 5000);
    }
    _flushListeningTime();
  }

  void _flushListeningTime({bool resetRemainder = false}) {
    final secs = _pendingListeningMs ~/ 1000;
    if (secs > 0) {
      _pendingListeningMs = resetRemainder ? 0 : (_pendingListeningMs % 1000);
      unawaited(
        DatabaseService.recordListeningSeconds(
          secs,
          song: _activeSessionSong ?? _currentSong,
          sessionKey: _activeSessionKey,
        ),
      );
    } else if (resetRemainder) {
      _pendingListeningMs = 0;
    }
  }

  Future<void> _playCurrent({int? token}) async {
    _captureListeningProgress(_player.position, maxDeltaMs: 5000);
    _flushListeningTime(resetRemainder: true);
    _lastTrackedPosition = Duration.zero;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final opToken = token ?? ++_playOperationToken;
    _isPausedByUser = false;
    _needsStreamRecovery = false;
    _recoveryAttempts = 0;
    _isLoading = true;

    // 1. Immediately cut off old audio while keeping completion guard active during teardown
    try {
      await _player.stop();
    } catch (_) {}
    if (opToken != _playOperationToken || _isPausedByUser) return;

    _currentSong = _queue[_currentIndex];
    _activeSessionSong = _currentSong;
    _activeSessionKey =
        'plog_${DateTime.now().microsecondsSinceEpoch}_${_currentSong!.id}';
    _recordSessionPlayed(_currentSong!);
    _userQueuedIds.remove(_currentSong!.id);
    _autoplayQueuedIds.remove(_currentSong!.id);

    // 2. Immediately reset position and initialize duration to current song metadata
    _position = Duration.zero;
    _duration = Duration(seconds: _currentSong!.duration);

    // Update notification immediately with new song info and duration
    _updateNotification();

    // 3. Immediately broadcast to UI so all sliders and timestamps reset instantly
    _positionChangeController.add(Duration.zero);
    _songChangeController.add(_currentSong);
    _stateChangeController.add(null);

    // Save to local history
    unawaited(DatabaseService.addToHistory(_currentSong!).catchError((e) {
      LogService.error('History write failed: $e', tag: 'Database');
    }));
    unawaited(_saveCurrentSession());
    LogService.recordBreadcrumb(
      'Playback started: "${_currentSong!.title}" (${_currentSong!.id})',
      category: 'playback',
    );

    try {
      final localUri = _resolvePlayableLocalUri(_currentSong!);
      if (localUri != null) {
        final localSource = _createAudioSource(localUri);
        await _player.setAudioSource(localSource).timeout(const Duration(seconds: 8));
        _hasHandledCompletion = false;
        if ((_playbackSpeed - 1.0).abs() > 0.01) {
          try {
            await _player.setSpeed(_playbackSpeed);
          } catch (_) {}
        }

        if (opToken != _playOperationToken || _isPausedByUser) {
          try {
            await _player.pause();
          } catch (_) {}
          return;
        }

        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}

        unawaited(_player.play().catchError((e) {
          LogService.error('AudioPlayer local play execution error: $e', tag: 'AudioPlayer');
        }));

        _triggerNextTrackPrefetch();
        _scheduleAutoplayPrefetchIfNeeded(_currentSong!, opToken);
        _updateNotification();
      } else {
        // 1. Resolve audio stream with instant cache check & hybrid fast path
        String streamUrl = await StreamResolverService.resolveAudioStreamUrl(
          _currentSong!.id,
          songTitle: _currentSong!.title,
          artist: _currentSong!.artist,
          optimistic: true,
        );

        if (opToken != _playOperationToken || _isPausedByUser) return;

        // 2. Local Disk Cache & 5s Head Proxy mapping
        String playableUrl = AudioCacheService.getPlayableUrl(_currentSong!.id, streamUrl);

        try {
          final source = _createAudioSource(playableUrl);
          await _player.setAudioSource(source).timeout(const Duration(seconds: 8));
          _hasHandledCompletion = false;
          if ((_playbackSpeed - 1.0).abs() > 0.01) {
            try {
              await _player.setSpeed(_playbackSpeed);
            } catch (_) {}
          }

          if (opToken != _playOperationToken || _isPausedByUser) {
            try {
              await _player.pause();
            } catch (_) {}
            return;
          }

          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}

          unawaited(_player.play().catchError((e) {
            LogService.error('AudioPlayer play execution error: $e', tag: 'AudioPlayer');
          }));
        } catch (playError) {
          // Immediately cancel native ExoPlayer on timeout or error
          try {
            await _player.stop();
          } catch (_) {}

          _logPlayerException(playError, streamUrl);

          if (opToken != _playOperationToken || _isPausedByUser) return;
          LogService.warning(
            'Optimistic source preparation failed ($playError). Retrying with safe direct stream (skipping proxy)...',
            tag: 'AudioPlayer',
          );
          debugPrint('Optimistic play error ($playError). Retrying with safe direct stream (skipping proxy)...');
          if (playError is! TimeoutException) {
            StreamResolverService.invalidateCache(_currentSong!.id);
          }
          AudioCacheService.evict(_currentSong!.id);

          // Safe fallback retry with direct resolved stream (bypassing local proxy and companion proxy)
          streamUrl = await StreamResolverService.resolveAudioStreamUrl(
            _currentSong!.id,
            songTitle: _currentSong!.title,
            artist: _currentSong!.artist,
            optimistic: false,
            skipCompanionProxy: true,
          );
          if (opToken != _playOperationToken || _isPausedByUser) return;

          final directFallbackSource = _createAudioSource(streamUrl);

          try {
            await _player.setAudioSource(directFallbackSource).timeout(const Duration(seconds: 10));
            _hasHandledCompletion = false;
            if ((_playbackSpeed - 1.0).abs() > 0.01) {
              try {
                await _player.setSpeed(_playbackSpeed);
              } catch (_) {}
            }
            if (opToken != _playOperationToken || _isPausedByUser) {
              try {
                await _player.pause();
              } catch (_) {}
              return;
            }

            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}

            unawaited(_player.play().catchError((e) {
              LogService.error('AudioPlayer fallback play execution error: $e', tag: 'AudioPlayer');
            }));
          } catch (fallbackError) {
            // Immediately cancel native ExoPlayer on fallback timeout or error
            try {
              await _player.stop();
            } catch (_) {}

            _logPlayerException(fallbackError, streamUrl);
            StreamResolverService.invalidateCache(_currentSong!.id);

            if (opToken != _playOperationToken || _isPausedByUser) return;
            rethrow;
          }
        }

        if (opToken != _playOperationToken || _isPausedByUser) {
          try {
            await _player.pause();
          } catch (_) {}
          return;
        }

        // 3. Keep 5-second head of this listened song in local cache for instant future replays
        AudioCacheService.ensureHeadCached(_currentSong!.id, streamUrl);

        // 4. NEXT-TRACK PRE-FETCHING & BACKGROUND AUTOPLAY:
        // Pre-resolve next track stream & pre-fetch upcoming similar autoplay tracks before track ends
        _triggerNextTrackPrefetch();
        _scheduleAutoplayPrefetchIfNeeded(_currentSong!, opToken);
        _updateNotification();
      }
    } catch (e) {
      LogService.recordBreadcrumb('Playback error for ${_currentSong?.id}: $e', category: 'playback');
      debugPrint('Playback error resolving audio: $e');
      _isPlaying = false;
      _updateNotification();
    } finally {
      if (opToken == _playOperationToken) {
        _isLoading = false;
        _stateChangeController.add(null);
      }
    }
  }

  void _recordSessionPlayed(Song song) {
    _sessionPlayedIds.add(song.id);
    final normTitle = RecommendationService.normalizeTrackKey(song.title);
    if (normTitle.isNotEmpty) {
      final artistKey = RecommendationService.primaryArtistKey(song.artist);
      _sessionPlayedNormalizedKeys.add(
        artistKey.isNotEmpty ? '$normTitle|$artistKey' : normTitle,
      );
    }
    if (_sessionPlayedIds.length > 100) {
      _sessionPlayedIds.remove(_sessionPlayedIds.first);
    }
    if (_sessionPlayedNormalizedKeys.length > 100) {
      _sessionPlayedNormalizedKeys.remove(_sessionPlayedNormalizedKeys.first);
    }
  }

  void _scheduleAutoplayPrefetchIfNeeded(Song seed, int opToken) {
    if (_isDisposed || _isPausedByUser || seed.isPodcast || _autoplayClearedByUser) {
      return;
    }
    if (_loopMode == MelodyLoopMode.one) return;
    // Prefetch when on the last or second-to-last item in queue
    if (_currentIndex < _queue.length - 2) return;
    unawaited(_prefetchAutoplayRecommendations(seed, opToken));
  }

  Future<List<Song>> _prefetchAutoplayRecommendations(
    Song seed,
    int opToken, {
    bool forceWhenEmpty = false,
  }) async {
    if (_isDisposed || seed.isPodcast) return const [];
    if (!forceWhenEmpty && _autoplayClearedByUser) return const [];

    final excludeIds = <String>{
      ..._sessionPlayedIds,
      ..._queue.map((s) => s.id),
    };
    final excludeNormalized = Set<String>.from(_sessionPlayedNormalizedKeys);

    Future<List<Song>> future;
    if (_inflightAutoplayFuture != null && _inflightAutoplaySeedId == seed.id) {
      future = _inflightAutoplayFuture!;
    } else {
      _inflightAutoplaySeedId = seed.id;
      final fetcher = autoplayFetcherOverride;
      future = fetcher != null
          ? fetcher(
              seed,
              excludeIds: excludeIds,
              excludeNormalizedKeys: excludeNormalized,
            )
          : RecommendationService.getAutoplayRecommendations(
              seed,
              excludeIds: excludeIds,
              excludeNormalizedKeys: excludeNormalized,
            );
      _inflightAutoplayFuture = future;
    }

    try {
      final recs = await future;
      if (_inflightAutoplaySeedId == seed.id) {
        _inflightAutoplayFuture = null;
        _inflightAutoplaySeedId = null;
      }
      if (_isDisposed ||
          _isPausedByUser ||
          opToken != _playOperationToken ||
          _currentSong?.id != seed.id) {
        return const [];
      }
      if (!forceWhenEmpty && _autoplayClearedByUser) return const [];

      final existingIds = _queue.map((s) => s.id).toSet();
      final appended = <Song>[];
      for (final r in recs) {
        if (existingIds.add(r.id) && !_sessionPlayedIds.contains(r.id)) {
          _queue.add(r);
          _autoplayQueuedIds.add(r.id);
          appended.add(r);
        }
      }
      if (appended.isNotEmpty) {
        _triggerNextTrackPrefetch();
        unawaited(_saveCurrentSession());
        if (!_isDisposed && !_stateChangeController.isClosed) {
          _stateChangeController.add(null);
        }
      }
      return appended;
    } catch (e) {
      if (_inflightAutoplaySeedId == seed.id) {
        _inflightAutoplayFuture = null;
        _inflightAutoplaySeedId = null;
      }
      debugPrint('AudioService: Autoplay prefetch error: $e');
      return const [];
    }
  }

  Future<void> _continueWithAutoplayOnTrackEnd() async {
    final seed = _currentSong;
    final opToken = _playOperationToken;
    if (seed == null || seed.isPodcast || _isPausedByUser || _isDisposed) {
      _isPlaying = false;
      _updateNotification();
      if (!_isDisposed && !_stateChangeController.isClosed) {
        _stateChangeController.add(null);
      }
      return;
    }

    await _prefetchAutoplayRecommendations(seed, opToken, forceWhenEmpty: true);
    if (_isDisposed || _isPausedByUser || opToken != _playOperationToken) {
      return;
    }

    if (hasNext) {
      await playNext();
    } else {
      _isPlaying = false;
      _updateNotification();
      if (!_isDisposed && !_stateChangeController.isClosed) {
        _stateChangeController.add(null);
      }
    }
  }

  /// Exposes track-end handling for deterministic unit tests.
  @visibleForTesting
  Future<void> handleTrackEndedForTesting() async {
    if (_loopMode == MelodyLoopMode.one) {
      await seek(Duration.zero);
      return;
    }
    if (hasNext) {
      await playNext();
      return;
    }
    if (_loopMode == MelodyLoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
      return;
    }
    await _continueWithAutoplayOnTrackEnd();
  }

  /// Seeds a song/queue state synchronously for unit tests without invoking ExoPlayer.
  @visibleForTesting
  void seedQueueForTesting(List<Song> songs, {int currentIndex = 0}) {
    _queue
      ..clear()
      ..addAll(songs);
    _userQueuedIds.clear();
    _autoplayQueuedIds.clear();
    _autoplayClearedByUser = false;
    _isPausedByUser = false;
    if (_queue.isEmpty) {
      _currentIndex = -1;
      _currentSong = null;
    } else {
      _currentIndex = currentIndex.clamp(0, _queue.length - 1);
      _currentSong = _queue[_currentIndex];
      _recordSessionPlayed(_currentSong!);
    }
  }

  void _triggerNextTrackPrefetch() {
    if (_currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[_currentIndex + 1];
      unawaited(_prefetchTrack(nextTrack));
    }
  }

  Future<void> _prefetchTrack(Song song) async {
    if (_resolvePlayableLocalUri(song) != null) {
      return;
    }
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
    // If the track was paused by the user when a stale completion event fires, do NOT auto-restart
    if (_isPausedByUser) {
      debugPrint('AudioService: Track completion received while paused by user. Marking recovery pending.');
      _needsStreamRecovery = true;
      return;
    }

    final isLocalTrack = _currentSong != null && _resolvePlayableLocalUri(_currentSong!) != null;

    // Detect premature track completion during active playback (remote streams only)
    if (!isLocalTrack &&
        _currentSong != null &&
        _duration > const Duration(seconds: 30) &&
        _position < _duration - const Duration(seconds: 15)) {
      if ((_position.inSeconds - _lastRecoveryPosition.inSeconds).abs() <= 2) {
        _recoveryAttempts++;
      } else {
        _lastRecoveryPosition = _position;
        _recoveryAttempts = 1;
      }

      if (_recoveryAttempts <= 2) {
        debugPrint(
            'AudioService: Premature track end at $_position of $_duration (attempt $_recoveryAttempts/2). Resuming stream seamlessly...');
        unawaited(_recoverStreamAtPosition(_position));
        return;
      } else {
        debugPrint('AudioService: Max recovery attempts reached at $_position. Continuing to next track.');
      }
    }

    _recoveryAttempts = 0;
    _lastRecoveryPosition = Duration.zero;

    if (_loopMode == MelodyLoopMode.one) {
      seek(Duration.zero);
      unawaited(_player.play().catchError((e) {
        LogService.error('Loop one play error: $e', tag: 'AudioPlayer');
      }));
    } else if (hasNext) {
      playNext();
    } else if (_loopMode == MelodyLoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      _playCurrent();
    } else {
      unawaited(_continueWithAutoplayOnTrackEnd());
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

  Future<void> resume() async {
    if (_currentSong == null) return;
    _isPausedByUser = false;
    final opToken = ++_playOperationToken;

    try {
      if (!_needsStreamRecovery && _player.processingState != ProcessingState.idle) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
        unawaited(_player.play().catchError((e) {
          LogService.error('Error in resume play: $e', tag: 'AudioPlayer');
        }));
      } else if (_position > Duration.zero) {
        _needsStreamRecovery = false;
        await _recoverStreamAtPosition(_position, token: opToken);
        return;
      } else {
        _needsStreamRecovery = false;
        await _playCurrent(token: opToken);
        return;
      }
      if (opToken != _playOperationToken || _isPausedByUser) return;
      _isPlaying = true;
      LogService.recordBreadcrumb('Playback resumed at $_position', category: 'playback');
      _updateNotification();
      _stateChangeController.add(null);
    } catch (e) {
      debugPrint('Resume error: $e. Retrying playback at position...');
      LogService.warning('Resume error: $e. Retrying playback at position...', tag: 'AudioPlayer');
      if (_position > Duration.zero) {
        await _recoverStreamAtPosition(_position, token: opToken);
      } else {
        await _playCurrent(token: opToken);
      }
    }
  }

  Future<void> pause() async {
    _captureListeningProgress(_player.position, maxDeltaMs: 5000);
    _flushListeningTime();
    _isPausedByUser = true;
    _playOperationToken++;
    _isLoading = false;
    _position = _player.position;
    try {
      await _player.pause();
    } catch (_) {}
    _isPlaying = false;
    _position = _player.position;
    LogService.recordBreadcrumb('Playback paused at $_position', category: 'playback');
    _updateNotification();
    _stateChangeController.add(null);
    unawaited(_saveCurrentSession());
  }

  Future<void> stop() async {
    _captureListeningProgress(_player.position, maxDeltaMs: 5000);
    _flushListeningTime(resetRemainder: true);
    _activeSessionSong = null;
    _activeSessionKey = null;
    _isPausedByUser = true;
    _playOperationToken++;
    _needsStreamRecovery = false;
    _recoveryAttempts = 0;
    _hasHandledCompletion = false;
    _isLoading = false;
    unawaited(_saveCurrentSession());
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _position = Duration.zero;
    LogService.recordBreadcrumb('Playback stopped', category: 'playback');
    _updateNotification();
    _stateChangeController.add(null);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying || (_isLoading && !_isPausedByUser)) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    _captureListeningProgress(_player.position, maxDeltaMs: 5000);
    _flushListeningTime();
    _lastTrackedPosition = position;
    _position = position;
    if (_duration <= Duration.zero || position < _duration - const Duration(seconds: 2)) {
      _hasHandledCompletion = false;
    }
    LogService.recordBreadcrumb('Playback seek to $position', category: 'playback');
    _updateNotification();
    _positionChangeController.add(position);
    _stateChangeController.add(null);

    try {
      await _player.seek(position);
    } catch (e) {
      if (_currentSong != null && _resolvePlayableLocalUri(_currentSong!) != null) {
        LogService.warning('AudioService: Local track seek error ($e)', tag: 'AudioPlayer');
        return;
      }
      debugPrint('AudioService: Seek error ($e). Re-resolving stream and resuming at $position...');
      LogService.warning('Seek error ($e). Attempting stream recovery at $position', tag: 'AudioPlayer');
      if (_currentSong != null) {
        StreamResolverService.invalidateCache(_currentSong!.id);
        AudioCacheService.evict(_currentSong!.id);
      }
      await _recoverStreamAtPosition(position);
    }
  }

  Future<void> _recoverStreamAtPosition(Duration position, {int? token}) async {
    if (_currentSong == null) return;
    _lastTrackedPosition = position;
    final opToken = token ?? ++_playOperationToken;
    _hasHandledCompletion = false;
    try {
      _isLoading = true;
      _stateChangeController.add(null);

      final localUri = _resolvePlayableLocalUri(_currentSong!);
      final String directUrl;
      if (localUri != null) {
        directUrl = localUri;
      } else {
        StreamResolverService.invalidateCache(_currentSong!.id);
        directUrl = await StreamResolverService.resolveAudioStreamUrl(
          _currentSong!.id,
          songTitle: _currentSong!.title,
          artist: _currentSong!.artist,
          optimistic: false,
          skipCompanionProxy: true,
        );
      }

      if (opToken != _playOperationToken || _isPausedByUser) return;

      final directSource = _createAudioSource(directUrl);

      try {
        await _player.setAudioSource(directSource, initialPosition: position).timeout(const Duration(seconds: 10));
        if ((_playbackSpeed - 1.0).abs() > 0.01) {
          try {
            await _player.setSpeed(_playbackSpeed);
          } catch (_) {}
        }
        if (opToken != _playOperationToken || _isPausedByUser) {
          try {
            await _player.pause();
          } catch (_) {}
          return;
        }

        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}

        unawaited(_player.play().catchError((e) {
          LogService.error('AudioPlayer recovery play error: $e', tag: 'AudioPlayer');
        }));
      } catch (pe) {
        // Immediately cancel native ExoPlayer on timeout or error
        try {
          await _player.stop();
        } catch (_) {}

        _logPlayerException(pe, directUrl);
        if (localUri == null) {
          StreamResolverService.invalidateCache(_currentSong!.id);
        }
        rethrow;
      }

      if (opToken != _playOperationToken || _isPausedByUser) {
        try {
          await _player.pause();
        } catch (_) {}
        return;
      }

      _isPlaying = true;
      _updateNotification();
    } catch (err) {
      debugPrint('AudioService: Recovery at position failed: $err');
      LogService.error('Recovery at position failed: $err', tag: 'AudioPlayer');
    } finally {
      if (opToken == _playOperationToken) {
        _isLoading = false;
        _stateChangeController.add(null);
      }
    }
  }

  Future<void> _handleIdleTeardown() async {
    LogService.recordBreadcrumb('AudioService: 15-minute idleTeardown triggered from native', category: 'lifecycle');
    await _saveCurrentSession();
    await stop();
  }

  Future<void> _saveCurrentSession() async {
    if (_currentSong == null) return;
    try {
      await DatabaseService.savePlaybackSession(
        song: _currentSong!,
        position: _position,
        duration: _duration,
        queue: _queue.take(100).toList(),
        queueIndex: _currentIndex,
      );
    } catch (e) {
      debugPrint('AudioService: Error saving playback session: $e');
    }
  }

  Future<bool> restoreLastSession() async {
    try {
      final session = await DatabaseService.getLastPlaybackSession();
      if (session == null) return false;

      // Check if session was updated within the last 7 days
      final age = DateTime.now().difference(session.updatedAt);
      if (age > const Duration(days: 7)) {
        await DatabaseService.clearPlaybackSession();
        return false;
      }

      _currentSong = session.song;
      _queue.clear();
      _queue.addAll(session.queue.isNotEmpty ? session.queue : [session.song]);
      _currentIndex = (session.queueIndex >= 0 && session.queueIndex < _queue.length)
          ? session.queueIndex
          : _queue.indexWhere((s) => s.id == session.song.id);
      if (_currentIndex == -1) _currentIndex = 0;

      _position = session.position;
      _lastTrackedPosition = _position;
      _pendingListeningMs = 0;
      _duration = session.duration > Duration.zero
          ? session.duration
          : Duration(seconds: session.song.duration);

      _isPlaying = false;
      _isPausedByUser = true;
      _needsStreamRecovery = true;
      _hasHandledCompletion = false;

      _positionChangeController.add(_position);
      _songChangeController.add(_currentSong);
      _stateChangeController.add(null);

      _updateNotification();
      LogService.recordBreadcrumb(
        'Restored previous playback session: "${session.song.title}" at $_position',
        category: 'playback',
      );
      return true;
    } catch (e) {
      debugPrint('AudioService: Error restoring playback session: $e');
      return false;
    }
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
    final clamped = speed.clamp(0.5, 2.5).toDouble();
    _playbackSpeed = clamped;
    try {
      await _player.setSpeed(clamped);
    } catch (e) {
      debugPrint('AudioService: setSpeed($clamped) skipped: $e');
    }
    _stateChangeController.add(null);
  }

  /// Applies [enabled] skip-silence mode safely on the underlying audio player.
  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    try {
      await _player.setSkipSilenceEnabled(enabled);
    } catch (e) {
      debugPrint('AudioService: setSkipSilenceEnabled($enabled) skipped: $e');
    }
    _stateChangeController.add(null);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removed = _queue.removeAt(index);
    _userQueuedIds.remove(removed.id);
    _autoplayQueuedIds.remove(removed.id);
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
    } else if (index == _currentIndex + 1) {
      _triggerNextTrackPrefetch();
    }
    unawaited(_saveCurrentSession());
    _stateChangeController.add(null);
  }

  /// Inserts [song] at the top of the upcoming queue (`currentIndex + 1`) so it
  /// plays immediately after the current track finishes, ahead of any autoplay items.
  void addToQueue(Song song) {
    _insertAtTopOfUpcomingQueue(song);
  }

  /// Places [song] at `currentIndex + 1` to play next right after the current track.
  void playNextInQueue(Song song) {
    _insertAtTopOfUpcomingQueue(song);
  }

  void _insertAtTopOfUpcomingQueue(Song song) {
    if (_currentSong == null ||
        _currentIndex < 0 ||
        _currentIndex >= _queue.length) {
      _queue.clear();
      _queue.add(song);
      _currentIndex = 0;
      _userQueuedIds.remove(song.id);
      _autoplayQueuedIds.remove(song.id);
      _autoplayClearedByUser = false;
      _playCurrent();
      return;
    }

    if (song.id == _currentSong!.id) return;

    final existingIdx = _queue.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1 && existingIdx != _currentIndex) {
      _queue.removeAt(existingIdx);
      if (existingIdx < _currentIndex) _currentIndex--;
    }

    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, song);
    _autoplayQueuedIds.remove(song.id);
    _userQueuedIds.add(song.id);
    _autoplayClearedByUser = false;

    _triggerNextTrackPrefetch();
    unawaited(_saveCurrentSession());
    _stateChangeController.add(null);
  }

  /// Reorders an upcoming queue item from [oldIndex] to [newIndex] (both > currentIndex).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex <= _currentIndex || oldIndex >= _queue.length) return;
    if (newIndex <= _currentIndex || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);

    _triggerNextTrackPrefetch();
    unawaited(_saveCurrentSession());
    _stateChangeController.add(null);
  }

  void clearQueue() {
    _userQueuedIds.clear();
    _autoplayQueuedIds.clear();
    _autoplayClearedByUser = true;
    if (_currentSong != null) {
      _queue.clear();
      _queue.add(_currentSong!);
      _currentIndex = 0;
    } else {
      _queue.clear();
      _currentIndex = -1;
    }
    unawaited(_saveCurrentSession());
    _stateChangeController.add(null);
  }

  void dispose() {
    _isDisposed = true;
    _flushListeningTime(resetRemainder: true);
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
