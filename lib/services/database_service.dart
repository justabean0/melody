import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/song.dart';
import 'battery_service.dart';

class PlaybackSession {
  final Song song;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final int queueIndex;
  final DateTime updatedAt;

  const PlaybackSession({
    required this.song,
    required this.position,
    required this.duration,
    required this.queue,
    required this.queueIndex,
    required this.updatedAt,
  });
}

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
  static const String _musicLanguagesKey = 'melody_music_languages';
  static const String _hasSelectedLanguagesKey = 'melody_has_selected_languages';
  static const String _languagePromptCompletedKey = 'melody_language_onboarding_v2_completed';
  static const String _searchHistoryKey = 'melody_search_history';
  static const String _batteryOptPromptShownKey = 'melody_battery_opt_prompt_shown';
  static const String _backgroundPlaybackKey = 'melody_background_playback_enabled';
  static const String _feedCacheVersion = 'v4';

  static String _feedCacheKey(String cacheKey) => 'melody_feed_cache_${_feedCacheVersion}_$cacheKey';
  static String _feedCacheTimestampKey(String cacheKey) => 'melody_feed_cache_ts_${_feedCacheVersion}_$cacheKey';

  /// Reactive notifier for real-time synchronization when user changes music languages
  static final ValueNotifier<List<String>> musicLanguagesNotifier = ValueNotifier<List<String>>([]);

  static SharedPreferences? _prefs;
  static Database? _db;

  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    _db = db;
  }

  @visibleForTesting
  static void setPrefsForTesting(SharedPreferences? prefs) {
    _prefs = prefs;
    musicLanguagesNotifier.value = getMusicLanguages();
  }

  static Future<void> init({String? dbName}) async {
    _prefs = await SharedPreferences.getInstance();
    musicLanguagesNotifier.value = getMusicLanguages();

    if (_db == null) {
      try {
        final databasesPath = await getDatabasesPath();
        final path = p.join(databasesPath, dbName ?? 'melody.db');

        _db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, version) async {
            await _createTables(db);
          },
          onOpen: (db) async {
            await _createTables(db);
          },
        );
      } catch (e) {
        debugPrint('DatabaseService init database error: $e');
      }
    } else {
      try {
        await _createTables(_db!);
      } catch (e) {
        debugPrint('DatabaseService _createTables error: $e');
      }
    }

    try {
      final bgEnabled = await getBackgroundPlaybackEnabled();
      await BatteryService.syncBackgroundPlayback(bgEnabled);
    } catch (_) {}

    await pruneOldFeedCaches();
  }

  /// Prunes all feed cache keys from previous versions (e.g. pre-v4 all-Hindi cache pollution)
  static Future<void> pruneOldFeedCaches() async {
    try {
      final keys = _prefs?.getKeys() ?? <String>{};
      for (final key in keys) {
        if (key.startsWith('melody_feed_cache_') &&
            !key.startsWith('melody_feed_cache_${_feedCacheVersion}_') &&
            !key.startsWith('melody_feed_cache_ts_${_feedCacheVersion}_')) {
          await _prefs?.remove(key);
        }
      }
    } catch (_) {}
  }

  static Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS last_playback_session (
        id INTEGER PRIMARY KEY,
        song_id TEXT,
        title TEXT,
        artist TEXT,
        album TEXT,
        thumbnail_url TEXT,
        duration_ms INTEGER,
        position_ms INTEGER,
        queue_json TEXT,
        queue_index INTEGER,
        updated_at INTEGER
      )
    ''');
  }

  // --- Background Playback Setting ---
  static Future<bool> getBackgroundPlaybackEnabled() async {
    if (_db != null) {
      try {
        final rows = await _db!.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: ['background_playback_enabled'],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final val = rows.first['value'];
          return val == '1' || val == 'true';
        }
      } catch (e) {
        debugPrint('Error reading background playback setting from SQLite: $e');
      }
    }
    return _prefs?.getBool(_backgroundPlaybackKey) ?? false;
  }

  static Future<void> setBackgroundPlaybackEnabled(bool enabled) async {
    await _prefs?.setBool(_backgroundPlaybackKey, enabled);
    if (_db != null) {
      try {
        await _db!.insert(
          'app_settings',
          {'key': 'background_playback_enabled', 'value': enabled ? '1' : '0'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint('Error saving background playback setting to SQLite: $e');
      }
    }
    await BatteryService.syncBackgroundPlayback(enabled);
  }

  // --- Last Playback Session ---
  static Future<void> savePlaybackSession({
    required Song song,
    required Duration position,
    required Duration duration,
    required List<Song> queue,
    required int queueIndex,
  }) async {
    if (_db == null) return;
    try {
      final queueJson = jsonEncode(queue.take(100).map((s) => s.toJson()).toList());
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      await _db!.insert(
        'last_playback_session',
        {
          'id': 1,
          'song_id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'thumbnail_url': song.thumbnailUrl,
          'duration_ms': duration.inMilliseconds,
          'position_ms': position.inMilliseconds,
          'queue_json': queueJson,
          'queue_index': queueIndex,
          'updated_at': nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error saving last playback session: $e');
    }
  }

  static Future<PlaybackSession?> getLastPlaybackSession() async {
    if (_db == null) return null;
    try {
      final rows = await _db!.query(
        'last_playback_session',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final songId = row['song_id'] as String?;
      final title = row['title'] as String?;
      if (songId == null || title == null) return null;

      final artist = row['artist'] as String? ?? 'Unknown Artist';
      final album = row['album'] as String? ?? '';
      final thumbnailUrl = row['thumbnail_url'] as String? ?? '';
      final durationMs = row['duration_ms'] as int? ?? 0;
      final positionMs = row['position_ms'] as int? ?? 0;
      final queueJson = row['queue_json'] as String? ?? '[]';
      final queueIndex = row['queue_index'] as int? ?? 0;
      final updatedAtMs = row['updated_at'] as int? ?? 0;

      final song = Song(
        id: songId,
        title: title,
        artist: artist,
        album: album,
        thumbnailUrl: thumbnailUrl,
        duration: durationMs ~/ 1000,
      );

      List<Song> queue = [];
      try {
        final decoded = jsonDecode(queueJson) as List<dynamic>;
        queue = decoded.map((item) => Song.fromJson(item as Map<String, dynamic>)).toList();
      } catch (_) {
        queue = [song];
      }

      return PlaybackSession(
        song: song,
        position: Duration(milliseconds: positionMs),
        duration: Duration(milliseconds: durationMs),
        queue: queue,
        queueIndex: queueIndex,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      );
    } catch (e) {
      debugPrint('Error getting last playback session: $e');
      return null;
    }
  }

  static Future<void> clearPlaybackSession() async {
    if (_db == null) return;
    try {
      await _db!.delete(
        'last_playback_session',
        where: 'id = ?',
        whereArgs: [1],
      );
    } catch (e) {
      debugPrint('Error clearing playback session: $e');
    }
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
  static final StreamController<void> _historyChangedController = StreamController<void>.broadcast();
  static Stream<void> get onHistoryChanged => _historyChangedController.stream;

  static List<Song> getHistory() {
    final raw = _prefs?.getStringList(_historyKey) ?? [];
    final List<Song> list = [];
    for (final str in raw) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is Map) {
          list.add(Song.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (e) {
        debugPrint('DatabaseService: Skipping corrupted history entry: $e');
      }
    }
    return list;
  }

  static Future<void> addToHistory(Song song) async {
    final list = getHistory();
    list.removeWhere((s) => s.id == song.id);
    list.insert(0, song);
    if (list.length > 50) list.removeLast();
    final raw = list.map((s) => jsonEncode(s.toJson())).toList();
    await _prefs?.setStringList(_historyKey, raw);
    _historyChangedController.add(null);
  }

  static Future<void> clearHistory() async {
    await _prefs?.remove(_historyKey);
    _historyChangedController.add(null);
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

  // --- Battery Optimization Prompt ---
  static bool hasShownBatteryOptPrompt() =>
      _prefs?.getBool(_batteryOptPromptShownKey) ?? false;
  static Future<void> markBatteryOptPromptShown() async =>
      await _prefs?.setBool(_batteryOptPromptShownKey, true);

  // --- Music Languages Preferences ---
  static List<String> getMusicLanguages() {
    final list = _prefs?.getStringList(_musicLanguagesKey);
    if (list != null && list.isNotEmpty) return list;
    return ['English'];
  }

  static List<String> getSavedMusicLanguages() {
    return _prefs?.getStringList(_musicLanguagesKey) ?? [];
  }

  static bool hasSelectedMusicLanguages() {
    final list = _prefs?.getStringList(_musicLanguagesKey);
    return list != null && list.isNotEmpty;
  }

  static Future<void> setMusicLanguages(List<String> languages) async {
    await _prefs?.setStringList(_musicLanguagesKey, languages);
    await _prefs?.setBool(_hasSelectedLanguagesKey, true);
    await _prefs?.setBool(_languagePromptCompletedKey, true);
    musicLanguagesNotifier.value = List.unmodifiable(languages);
  }

  static bool hasSelectedLanguages() {
    return _prefs?.getBool(_hasSelectedLanguagesKey) ?? false;
  }

  static bool hasCompletedLanguageOnboarding() {
    return _prefs?.getBool(_languagePromptCompletedKey) ?? false;
  }

  static Future<void> markLanguageOnboardingCompleted() async {
    await _prefs?.setBool(_languagePromptCompletedKey, true);
  }

  // --- Cached Feed (Instant Stale-While-Revalidate Home Display) ---
  static List<Song> getCachedFeed(String cacheKey) {
    final raw = _prefs?.getString(_feedCacheKey(cacheKey));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) => Song.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static DateTime? getCachedFeedTimestamp(String cacheKey) {
    final ms = _prefs?.getInt(_feedCacheTimestampKey(cacheKey));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> saveCachedFeed(String cacheKey, List<Song> songs) async {
    try {
      final jsonStr = jsonEncode(songs.map((s) => s.toJson()).toList());
      await _prefs?.setString(_feedCacheKey(cacheKey), jsonStr);
      await _prefs?.setInt(
        _feedCacheTimestampKey(cacheKey),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> clearCachedFeed(String cacheKey) async {
    try {
      await _prefs?.remove(_feedCacheKey(cacheKey));
      await _prefs?.remove(_feedCacheTimestampKey(cacheKey));
    } catch (_) {}
  }

  // --- Search History ---
  static List<String> getSearchHistory() {
    return _prefs?.getStringList(_searchHistoryKey) ?? [];
  }

  static Future<void> addSearchHistory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final list = getSearchHistory();
    list.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
    list.insert(0, clean);
    if (list.length > 25) {
      list.removeRange(25, list.length);
    }
    await _prefs?.setStringList(_searchHistoryKey, list);
  }

  static Future<void> removeSearchHistory(String query) async {
    final list = getSearchHistory();
    list.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());
    await _prefs?.setStringList(_searchHistoryKey, list);
  }

  static Future<void> clearSearchHistory() async {
    await _prefs?.remove(_searchHistoryKey);
  }
}
