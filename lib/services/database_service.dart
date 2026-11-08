import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class DatabaseService {
  static const String _favoritesKey = 'melody_favorites';
  static const String _playlistsKey = 'melody_playlists';
  static const String _historyKey = 'melody_history';
  static const String _themeModeKey = 'melody_theme_mode';
  static const String _pureBlackKey = 'melody_pure_black';
  static const String _accentColorKey = 'melody_accent_color';
  static const String _audioQualityKey = 'melody_audio_quality';
  static const String _skipSilenceKey = 'melody_skip_silence';
  static const String _normalizeVolumeKey = 'melody_normalize_volume';
  static const String _updateSourceKey = 'melody_update_source';
  static const String _autoCheckUpdatesKey = 'melody_auto_check_updates';
  static const String _lastUpdateCheckKey = 'melody_last_update_check';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Liked Songs ---
  static List<Song> getLikedSongs() {
    final raw = _prefs?.getStringList(_favoritesKey) ?? [];
    return raw.map((str) => Song.fromJson(jsonDecode(str))).toList();
  }

  static Future<void> toggleLike(Song song) async {
    final list = getLikedSongs();
    final index = list.indexWhere((s) => s.id == song.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, song);
    }
    final raw = list.map((s) => jsonEncode(s.toJson())).toList();
    await _prefs?.setStringList(_favoritesKey, raw);
  }

  static bool isLiked(String songId) {
    final list = getLikedSongs();
    return list.any((s) => s.id == songId);
  }

  // --- Playlists ---
  static List<Playlist> getPlaylists() {
    final raw = _prefs?.getStringList(_playlistsKey) ?? [];
    return raw.map((str) => Playlist.fromJson(jsonDecode(str))).toList();
  }

  static Future<void> savePlaylists(List<Playlist> playlists) async {
    final raw = playlists.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs?.setStringList(_playlistsKey, raw);
  }

  static Future<void> createPlaylist(String title, {String? description}) async {
    final list = getPlaylists();
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      author: 'You',
      description: description,
      thumbnailUrl: 'https://picsum.photos/300/300',
      songCount: 0,
      songs: [],
    );
    list.add(newPlaylist);
    await savePlaylists(list);
  }

  static Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final list = getPlaylists();
    final index = list.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final p = list[index];
      if (!p.songs.any((s) => s.id == song.id)) {
        final updatedSongs = List<Song>.from(p.songs)..add(song);
        list[index] = Playlist(
          id: p.id,
          title: p.title,
          author: p.author,
          description: p.description,
          thumbnailUrl: updatedSongs.isNotEmpty ? updatedSongs.first.thumbnailUrl : p.thumbnailUrl,
          songCount: updatedSongs.length,
          songs: updatedSongs,
        );
        await savePlaylists(list);
      }
    }
  }

  static Future<void> deletePlaylist(String playlistId) async {
    final list = getPlaylists();
    list.removeWhere((p) => p.id == playlistId);
    await savePlaylists(list);
  }

  // --- History ---
  static List<Song> getHistory() {
    final raw = _prefs?.getStringList(_historyKey) ?? [];
    return raw.map((str) => Song.fromJson(jsonDecode(str))).toList();
  }

  static Future<void> addToHistory(Song song) async {
    final list = getHistory();
    list.removeWhere((s) => s.id == song.id);
    list.insert(0, song);
    if (list.length > 50) list.removeLast();
    final raw = list.map((s) => jsonEncode(s.toJson())).toList();
    await _prefs?.setStringList(_historyKey, raw);
  }

  static Future<void> clearHistory() async {
    await _prefs?.remove(_historyKey);
  }

  // --- Settings ---
  static String getThemeMode() =>
      _prefs?.getString(_themeModeKey) ?? 'system';
  static Future<void> setThemeMode(String mode) async =>
      await _prefs?.setString(_themeModeKey, mode);

  static bool getPureBlack() =>
      _prefs?.getBool(_pureBlackKey) ?? true;
  static Future<void> setPureBlack(bool val) async =>
      await _prefs?.setBool(_pureBlackKey, val);

  static int getAccentColor() =>
      _prefs?.getInt(_accentColorKey) ?? 0xFFE53935; // Melody Red
  static Future<void> setAccentColor(int color) async =>
      await _prefs?.setInt(_accentColorKey, color);

  static String getAudioQuality() =>
      _prefs?.getString(_audioQualityKey) ?? 'high';
  static Future<void> setAudioQuality(String quality) async =>
      await _prefs?.setString(_audioQualityKey, quality);

  static bool getSkipSilence() =>
      _prefs?.getBool(_skipSilenceKey) ?? false;
  static Future<void> setSkipSilence(bool val) async =>
      await _prefs?.setBool(_skipSilenceKey, val);

  static bool getNormalizeVolume() =>
      _prefs?.getBool(_normalizeVolumeKey) ?? true;
  static Future<void> setNormalizeVolume(bool val) async =>
      await _prefs?.setBool(_normalizeVolumeKey, val);

  // --- Updates ---
  static String getUpdateSource() {
    final saved = _prefs?.getString(_updateSourceKey);
    if (saved == null ||
        saved.isEmpty ||
        saved.contains('Srijan/melody') ||
        saved.contains('YOUR_USERNAME')) {
      const correct =
          'https://api.github.com/repos/justabean0/melody/releases/latest';
      _prefs?.setString(_updateSourceKey, correct);
      return correct;
    }
    return saved;
  }
  static Future<void> setUpdateSource(String source) async =>
      await _prefs?.setString(_updateSourceKey, source);

  static bool getAutoCheckUpdates() =>
      _prefs?.getBool(_autoCheckUpdatesKey) ?? true;
  static Future<void> setAutoCheckUpdates(bool val) async =>
      await _prefs?.setBool(_autoCheckUpdatesKey, val);

  static int getLastUpdateCheck() =>
      _prefs?.getInt(_lastUpdateCheckKey) ?? 0;
  static Future<void> setLastUpdateCheck(int timestamp) async =>
      await _prefs?.setInt(_lastUpdateCheckKey, timestamp);
}
