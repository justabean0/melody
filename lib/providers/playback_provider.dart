import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/lyrics_service.dart';

class PlaybackProvider extends ChangeNotifier {
  final MelodyAudioService _audioService = MelodyAudioService();

  Song? get currentSong => _audioService.currentSong;
  List<Song> get queue => _audioService.queue;
  int get currentIndex => _audioService.currentIndex;
  bool get isPlaying => _audioService.isPlaying;
  bool get isLoading => _audioService.isLoading;
  Duration get position => _audioService.position;
  Duration get duration => _audioService.duration;
  MelodyLoopMode get loopMode => _audioService.loopMode;
  bool get isShuffle => _audioService.isShuffle;

  LyricsData? _lyrics;
  LyricsData? get lyrics => _lyrics;

  bool _isLoadingLyrics = false;
  bool get isLoadingLyrics => _isLoadingLyrics;

  StreamSubscription? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _songSub;

  PlaybackProvider() {
    _audioService.init();

    _posSub = _audioService.onPositionChange.listen((_) {
      notifyListeners();
    });

    _stateSub = _audioService.onStateChange.listen((_) {
      notifyListeners();
    });

    _songSub = _audioService.onSongChange.listen((song) {
      _onSongChanged(song);
    });
  }

  void _onSongChanged(Song? song) {
    if (song == null) {
      _lyrics = null;
      notifyListeners();
      return;
    }

    _loadLyrics(song);
    notifyListeners();
  }

  Future<void> _loadLyrics(Song song) async {
    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    try {
      _lyrics = await LyricsService.fetchLyrics(
        title: song.title,
        artist: song.artist,
        durationSeconds: song.duration,
      );
    } catch (_) {
      _lyrics = null;
    } finally {
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  /// Get index of the current active lyric line for synced scrolling
  int get activeLyricIndex {
    if (_lyrics == null || !_lyrics!.isSynced) return -1;
    final currentMs = position.inMilliseconds;
    final lines = _lyrics!.syncedLyrics;

    for (int i = lines.length - 1; i >= 0; i--) {
      if (currentMs >= lines[i].timeMs) {
        return i;
      }
    }
    return 0;
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue, int? startIndex}) async {
    await _audioService.playSong(song, contextQueue: contextQueue, startIndex: startIndex);
  }

  Future<void> togglePlayPause() async {
    await _audioService.togglePlayPause();
  }

  Future<void> playNext() async {
    await _audioService.playNext();
  }

  Future<void> playPrevious() async {
    await _audioService.playPrevious();
  }

  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
  }

  void toggleShuffle() {
    _audioService.toggleShuffle();
  }

  void cycleLoopMode() {
    _audioService.cycleLoopMode();
  }

  void setPlaybackSpeed(double speed) {
    _audioService.setPlaybackSpeed(speed);
  }

  void removeFromQueue(int index) {
    _audioService.removeFromQueue(index);
  }

  void clearQueue() {
    _audioService.clearQueue();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _songSub?.cancel();
    _audioService.dispose();
    super.dispose();
  }
}
