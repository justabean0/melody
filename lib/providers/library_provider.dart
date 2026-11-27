import 'dart:async';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/database_service.dart';

class LibraryProvider extends ChangeNotifier {
  List<Song> _likedSongs = [];
  List<Playlist> _playlists = [];
  List<Song> _history = [];
  int _todayListeningSeconds = 0;
  int _monthlyListeningSeconds = 0;
  List<int> _dailyListeningSeries = const [];
  List<PlaytimeBucket> _dailyPlaytimeBuckets = const [];
  List<PlaytimeBucket> _monthlyPlaytimeBuckets = const [];
  List<PlayLogEntry> _recentPlayLogs = const [];
  StreamSubscription<void>? _historySubscription;
  StreamSubscription<void>? _listeningStatsSubscription;

  List<Song> get likedSongs => List.unmodifiable(_likedSongs);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Song> get history => List.unmodifiable(_history);
  int get todayListeningSeconds => _todayListeningSeconds;
  int get monthlyListeningSeconds => _monthlyListeningSeconds;
  String get monthlyListeningLabel =>
      DatabaseService.formatListeningDuration(_monthlyListeningSeconds);
  List<int> get dailyListeningSeries => List.unmodifiable(_dailyListeningSeries);
  List<PlaytimeBucket> get dailyPlaytimeBuckets =>
      List.unmodifiable(_dailyPlaytimeBuckets);
  List<PlaytimeBucket> get monthlyPlaytimeBuckets =>
      List.unmodifiable(_monthlyPlaytimeBuckets);
  List<PlayLogEntry> get recentPlayLogs => List.unmodifiable(_recentPlayLogs);

  LibraryProvider() {
    loadAll();
    _historySubscription = DatabaseService.onHistoryChanged.listen((_) {
      refreshHistory();
    });
    _listeningStatsSubscription =
        DatabaseService.onListeningStatsChanged.listen((_) {
      refreshListeningStats();
    });
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    _listeningStatsSubscription?.cancel();
    super.dispose();
  }

  void loadAll() {
    _likedSongs = DatabaseService.getLikedSongs();
    _playlists = DatabaseService.getPlaylists();
    _history = DatabaseService.getHistory();
    _syncListeningSnapshot();
    notifyListeners();
  }

  void _syncListeningSnapshot() {
    _todayListeningSeconds = DatabaseService.getTodayListeningSeconds();
    _monthlyListeningSeconds = DatabaseService.getMonthlyListeningSeconds();
    _dailyListeningSeries = DatabaseService.getDailyListeningSeries(days: 14);
    _dailyPlaytimeBuckets = DatabaseService.getDailyPlaytimeBuckets(days: 7);
    _monthlyPlaytimeBuckets =
        DatabaseService.getMonthlyPlaytimeBuckets(months: 6);
    _recentPlayLogs = DatabaseService.getRecentPlayLogs(limit: 25);
  }

  void refreshListeningStats() {
    _syncListeningSnapshot();
    notifyListeners();
  }

  bool isLiked(String songId) => _likedSongs.any((s) => s.id == songId);

  Future<void> toggleLike(Song song) async {
    await DatabaseService.toggleLike(song);
    _likedSongs = DatabaseService.getLikedSongs();
    notifyListeners();
  }

  Future<void> createPlaylist(String title, {String? description}) async {
    await DatabaseService.createPlaylist(title, description: description);
    _playlists = DatabaseService.getPlaylists();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    await DatabaseService.addSongToPlaylist(playlistId, song);
    _playlists = DatabaseService.getPlaylists();
    notifyListeners();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await DatabaseService.removeSongFromPlaylist(playlistId, songId);
    _playlists = DatabaseService.getPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await DatabaseService.deletePlaylist(playlistId);
    _playlists = DatabaseService.getPlaylists();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await DatabaseService.clearHistory();
    _history = [];
    notifyListeners();
  }

  void refreshHistory() {
    _history = DatabaseService.getHistory();
    notifyListeners();
  }
}
