import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/database_service.dart';

class LibraryProvider extends ChangeNotifier {
  List<Song> _likedSongs = [];
  List<Playlist> _playlists = [];
  List<Song> _history = [];

  List<Song> get likedSongs => List.unmodifiable(_likedSongs);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Song> get history => List.unmodifiable(_history);

  LibraryProvider() {
    loadAll();
  }

  void loadAll() {
    _likedSongs = DatabaseService.getLikedSongs();
    _playlists = DatabaseService.getPlaylists();
    _history = DatabaseService.getHistory();
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
