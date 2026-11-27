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

class PlaytimeBucket {
  final String key;
  final String label;
  final int seconds;
  final DateTime periodStart;

  const PlaytimeBucket({
    required this.key,
    required this.label,
    required this.seconds,
    required this.periodStart,
  });
}

class PlayLogEntry {
  final String sessionKey;
  final String songId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int durationSeconds;
  final DateTime playedAt;

  const PlayLogEntry({
    required this.sessionKey,
    required this.songId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionKey': sessionKey,
        'songId': songId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'playedAtMs': playedAt.millisecondsSinceEpoch,
      };

  factory PlayLogEntry.fromJson(Map<String, dynamic> json) => PlayLogEntry(
        sessionKey: (json['sessionKey'] ?? '').toString(),
        songId: (json['songId'] ?? '').toString(),
        title: (json['title'] ?? 'Unknown Track').toString(),
        artist: (json['artist'] ?? 'Unknown Artist').toString(),
        thumbnailUrl: (json['thumbnailUrl'] ?? '').toString(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        playedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['playedAtMs'] as num?)?.toInt() ?? 0,
        ),
      );
}

class FormattedSplitPlaytime {
  final String primaryValue;
  final String primaryUnit;
  final String secondaryValue;
  final String secondaryUnit;

  const FormattedSplitPlaytime({
    required this.primaryValue,
    required this.primaryUnit,
    required this.secondaryValue,
    required this.secondaryUnit,
  });

  String get summary => '$primaryValue $primaryUnit / $secondaryValue $secondaryUnit';
}

class DatabaseService {
  static const String _favoritesKey = 'melody_favorites';
  static const String _playlistsKey = 'melody_playlists';
  static const String _historyKey = 'melody_history';
  static const String _themeModeKey = 'melody_theme_mode';
  static const String _pureBlackKey = 'melody_pure_black';
  static const String _surfaceStyleKey = 'melody_surface_style';
  static const String _accentColorKey = 'melody_accent_color';
  static const String _adaptivePlayerTintKey = 'melody_adaptive_player_tint';
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
  static const String _dailyListeningSecondsKey = 'melody_daily_listening_seconds';
  static const String _playLogsFallbackKey = 'melody_play_logs_v1';
  static const String _downloadedTracksKey = 'melody_downloaded_tracks_v1';
  static const String _feedCacheVersion = 'v4';

  static String _feedCacheKey(String cacheKey) => 'melody_feed_cache_${_feedCacheVersion}_$cacheKey';
  static String _feedCacheTimestampKey(String cacheKey) => 'melody_feed_cache_ts_${_feedCacheVersion}_$cacheKey';

  /// Reactive notifier for real-time synchronization when user changes music languages
  static final ValueNotifier<List<String>> musicLanguagesNotifier = ValueNotifier<List<String>>([]);

  static SharedPreferences? _prefs;
  static Database? _db;
  static List<PlayLogEntry> _recentPlayLogsCache = const [];

  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    _db = db;
    if (db == null) {
      _recentPlayLogsCache = const [];
    }
  }

  @visibleForTesting
  static void setPrefsForTesting(SharedPreferences? prefs) {
    _prefs = prefs;
    if (prefs == null) {
      _recentPlayLogsCache = const [];
    }
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
          version: 2,
          onCreate: (db, version) async {
            await _createTables(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
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

    await _refreshPlayLogsCache();

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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS listening_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_key TEXT UNIQUE,
        song_id TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        thumbnail_url TEXT,
        duration_seconds INTEGER NOT NULL,
        played_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_logs_played_at
      ON listening_logs (played_at_ms DESC)
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

  static Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final list = getPlaylists();
    final index = list.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final p = list[index];
    final updatedSongs = p.songs.where((s) => s.id != songId).toList();
    if (updatedSongs.length == p.songs.length) return;
    list[index] = Playlist(
      id: p.id,
      title: p.title,
      author: p.author,
      description: p.description,
      thumbnailUrl: updatedSongs.isNotEmpty
          ? updatedSongs.first.thumbnailUrl
          : 'https://picsum.photos/300/300',
      songCount: updatedSongs.length,
      songs: updatedSongs,
    );
    await savePlaylists(list);
  }

  static Future<void> deletePlaylist(String playlistId) async {
    final list = getPlaylists();
    list.removeWhere((p) => p.id == playlistId);
    await savePlaylists(list);
  }

  // --- History ---
  static final StreamController<void> _historyChangedController = StreamController<void>.broadcast();
  static Stream<void> get onHistoryChanged => _historyChangedController.stream;

  // --- Local Listening Stats ---
  static final StreamController<void> _listeningStatsChangedController =
      StreamController<void>.broadcast();
  static Stream<void> get onListeningStatsChanged =>
      _listeningStatsChangedController.stream;

  static String _dayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static final RegExp _dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static bool _isValidDateKey(String key) {
    if (!_dateKeyPattern.hasMatch(key)) return false;
    final parts = key.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return false;
    final dt = DateTime(year, month, day);
    return dt.year == year && dt.month == month && dt.day == day;
  }

  static Map<String, int> _readDailyListeningMap() {
    final raw = _prefs?.getString(_dailyListeningSecondsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, int>{};
        for (final entry in decoded.entries) {
          final k = entry.key.toString();
          if (!_isValidDateKey(k)) continue;
          final v = entry.value;
          if (v is int && v > 0) {
            result[k] = v;
          } else if (v is num && v.isFinite && v > 0) {
            final truncated = v.toInt();
            if (truncated > 0) result[k] = truncated;
          }
        }
        return result;
      }
    } catch (_) {}
    return {};
  }

  static const List<String> _shortWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Records locally played [seconds] into today's bucket (or [date] for testing)
  /// and optionally updates the detailed play log for [song] / [sessionKey].
  static Future<void> recordListeningSeconds(
    int seconds, {
    DateTime? date,
    Song? song,
    String? sessionKey,
  }) async {
    if (seconds <= 0) return;
    final now = date ?? DateTime.now();
    final key = _dayKey(now);
    final map = _readDailyListeningMap();
    map[key] = (map[key] ?? 0) + seconds;

    // Retain at least 12 months (366 days) of second-accurate daily buckets for 6-month charts
    final cutoff = now.subtract(const Duration(days: 366));
    final cutoffKey = _dayKey(cutoff);
    map.removeWhere((k, _) => k.compareTo(cutoffKey) < 0);

    await _prefs?.setString(_dailyListeningSecondsKey, jsonEncode(map));

    if (song != null) {
      await _recordPlayLog(
        seconds: seconds,
        playedAt: now,
        song: song,
        sessionKey: sessionKey,
      );
    }

    _listeningStatsChangedController.add(null);
  }

  static Future<void> _recordPlayLog({
    required int seconds,
    required DateTime playedAt,
    required Song song,
    String? sessionKey,
  }) async {
    final resolvedKey = (sessionKey != null && sessionKey.trim().isNotEmpty)
        ? sessionKey.trim()
        : 'plog_${playedAt.microsecondsSinceEpoch}_${song.id}';
    final playedAtMs = playedAt.millisecondsSinceEpoch;

    if (_db != null) {
      try {
        final existing = await _db!.query(
          'listening_logs',
          columns: ['id', 'duration_seconds'],
          where: 'session_key = ?',
          whereArgs: [resolvedKey],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final prevDuration =
              (existing.first['duration_seconds'] as num?)?.toInt() ?? 0;
          await _db!.update(
            'listening_logs',
            {
              'title': song.title,
              'artist': song.artist,
              'thumbnail_url': song.thumbnailUrl,
              'duration_seconds': prevDuration + seconds,
              'played_at_ms': playedAtMs,
            },
            where: 'session_key = ?',
            whereArgs: [resolvedKey],
          );
        } else {
          await _db!.insert(
            'listening_logs',
            {
              'session_key': resolvedKey,
              'song_id': song.id,
              'title': song.title,
              'artist': song.artist,
              'thumbnail_url': song.thumbnailUrl,
              'duration_seconds': seconds,
              'played_at_ms': playedAtMs,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _db!.rawDelete(
            '''
            DELETE FROM listening_logs
            WHERE id NOT IN (
              SELECT id FROM listening_logs ORDER BY played_at_ms DESC, id DESC LIMIT 200
            )
            ''',
          );
        }
        await _refreshPlayLogsCache();
        return;
      } catch (e) {
        debugPrint('DatabaseService: Error writing listening_logs: $e');
      }
    }

    // Fallback JSON list in SharedPreferences when SQLite is not initialized
    final list = List<PlayLogEntry>.from(_readFallbackPlayLogs());
    final idx = list.indexWhere((e) => e.sessionKey == resolvedKey);
    if (idx >= 0) {
      final prev = list.removeAt(idx);
      list.insert(
        0,
        PlayLogEntry(
          sessionKey: resolvedKey,
          songId: song.id,
          title: song.title,
          artist: song.artist,
          thumbnailUrl: song.thumbnailUrl,
          durationSeconds: prev.durationSeconds + seconds,
          playedAt: playedAt,
        ),
      );
    } else {
      list.insert(
        0,
        PlayLogEntry(
          sessionKey: resolvedKey,
          songId: song.id,
          title: song.title,
          artist: song.artist,
          thumbnailUrl: song.thumbnailUrl,
          durationSeconds: seconds,
          playedAt: playedAt,
        ),
      );
    }
    if (list.length > 50) {
      list.removeRange(50, list.length);
    }
    await _prefs?.setString(
      _playLogsFallbackKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    _recentPlayLogsCache = List.unmodifiable(list);
  }

  static List<PlayLogEntry> _readFallbackPlayLogs() {
    final raw = _prefs?.getString(_playLogsFallbackKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => PlayLogEntry.fromJson(Map<String, dynamic>.from(item)))
            .where((entry) => entry.durationSeconds > 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> _refreshPlayLogsCache({int limit = 50}) async {
    if (_db != null) {
      try {
        final rows = await _db!.query(
          'listening_logs',
          orderBy: 'played_at_ms DESC, id DESC',
          limit: limit,
        );
        _recentPlayLogsCache = List.unmodifiable(
          rows
              .map(
                (r) => PlayLogEntry(
                  sessionKey: (r['session_key'] ?? '').toString(),
                  songId: (r['song_id'] ?? '').toString(),
                  title: (r['title'] ?? 'Unknown Track').toString(),
                  artist: (r['artist'] ?? 'Unknown Artist').toString(),
                  thumbnailUrl: (r['thumbnail_url'] ?? '').toString(),
                  durationSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 0,
                  playedAt: DateTime.fromMillisecondsSinceEpoch(
                    (r['played_at_ms'] as num?)?.toInt() ?? 0,
                  ),
                ),
              )
              .where((entry) => entry.durationSeconds > 0)
              .toList(),
        );
        return;
      } catch (e) {
        debugPrint('DatabaseService: Error reading listening_logs: $e');
      }
    }
    _recentPlayLogsCache = List.unmodifiable(_readFallbackPlayLogs());
  }

  /// Returns recent detailed play logs synchronously from the active cache.
  static List<PlayLogEntry> getRecentPlayLogs({int limit = 25}) {
    if (_recentPlayLogsCache.length <= limit) {
      return _recentPlayLogsCache;
    }
    return List.unmodifiable(_recentPlayLogsCache.take(limit));
  }

  /// Queries recent detailed play logs directly from SQLite (or fallback store).
  static Future<List<PlayLogEntry>> loadRecentPlayLogs({int limit = 50}) async {
    await _refreshPlayLogsCache(limit: limit);
    return getRecentPlayLogs(limit: limit);
  }

  /// Returns total local listening seconds recorded for today (or [now]).
  static int getTodayListeningSeconds({DateTime? now}) {
    final ref = now ?? DateTime.now();
    final map = _readDailyListeningMap();
    return map[_dayKey(ref)] ?? 0;
  }

  /// Returns total local listening seconds recorded in the current calendar month.
  static int getMonthlyListeningSeconds({DateTime? now}) {
    final ref = now ?? DateTime.now();
    final prefix =
        '${ref.year.toString().padLeft(4, '0')}-${ref.month.toString().padLeft(2, '0')}-';
    final map = _readDailyListeningMap();
    var total = 0;
    for (final entry in map.entries) {
      if (entry.key.startsWith(prefix) && entry.value > 0) {
        total += entry.value;
      }
    }
    return total;
  }

  /// Returns daily listening seconds for the trailing [days] ending at [now] (oldest to newest).
  static List<int> getDailyListeningSeries({int days = 14, DateTime? now}) {
    final count = days < 2 ? 2 : days;
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final map = _readDailyListeningMap();
    return List<int>.generate(count, (i) {
      final day = today.subtract(Duration(days: count - 1 - i));
      return map[_dayKey(day)] ?? 0;
    });
  }

  /// Returns structured daily buckets for the trailing [days] ending at [now] (oldest to newest).
  static List<PlaytimeBucket> getDailyPlaytimeBuckets({
    int days = 7,
    DateTime? now,
  }) {
    final count = days < 1 ? 1 : days;
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final map = _readDailyListeningMap();
    return List<PlaytimeBucket>.generate(count, (i) {
      final day = today.subtract(Duration(days: count - 1 - i));
      final key = _dayKey(day);
      return PlaytimeBucket(
        key: key,
        label: _shortWeekdays[day.weekday - 1],
        seconds: map[key] ?? 0,
        periodStart: day,
      );
    });
  }

  /// Returns structured monthly buckets for the trailing [months] ending at [now] (oldest to newest).
  static List<PlaytimeBucket> getMonthlyPlaytimeBuckets({
    int months = 6,
    DateTime? now,
  }) {
    final count = months < 1 ? 1 : months;
    final ref = now ?? DateTime.now();
    final map = _readDailyListeningMap();

    return List<PlaytimeBucket>.generate(count, (i) {
      final offset = count - 1 - i;
      final monthStart = DateTime(ref.year, ref.month - offset, 1);
      final ymPrefix =
          '${monthStart.year.toString().padLeft(4, '0')}-${monthStart.month.toString().padLeft(2, '0')}';
      var sum = 0;
      for (final entry in map.entries) {
        if (entry.key.startsWith('$ymPrefix-') && entry.value > 0) {
          sum += entry.value;
        }
      }
      return PlaytimeBucket(
        key: ymPrefix,
        label: _shortMonths[monthStart.month - 1],
        seconds: sum,
        periodStart: monthStart,
      );
    });
  }

  /// Formats [totalSeconds] into split stacked playtime units:
  /// - `< 3600s`: `min` on top, `sec` below (`0 min / 0 sec`, `59 min / 59 sec`)
  /// - `>= 3600s`: `hr` on top, `min` below (`1 hr / 0 min`, `2 hr / 15 min`)
  static FormattedSplitPlaytime formatSplitPlaytime(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    if (safe < 3600) {
      final mins = safe ~/ 60;
      final secs = safe % 60;
      return FormattedSplitPlaytime(
        primaryValue: '$mins',
        primaryUnit: 'min',
        secondaryValue: '$secs',
        secondaryUnit: 'sec',
      );
    }
    final hrs = safe ~/ 3600;
    final mins = (safe % 3600) ~/ 60;
    return FormattedSplitPlaytime(
      primaryValue: '$hrs',
      primaryUnit: 'hr',
      secondaryValue: '$mins',
      secondaryUnit: 'min',
    );
  }

  /// Formats [totalSeconds] concisely for bar inspection & play logs (`18s`, `14m 32s`, `2h 15m`).
  static String formatCompactPlaytime(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    if (safe < 60) return '${safe}s';
    if (safe < 3600) {
      final mins = safe ~/ 60;
      final secs = safe % 60;
      return '${mins}m ${secs}s';
    }
    final hrs = safe ~/ 3600;
    final mins = (safe % 3600) ~/ 60;
    return '${hrs}h ${mins}m';
  }

  /// Formats total listening seconds as compact hours (`36h`) or minutes (`0m` / `45m`).
  static String formatListeningDuration(int totalSeconds) {
    if (totalSeconds < 60) return '0m';
    final totalMinutes = totalSeconds ~/ 60;
    if (totalMinutes < 60) return '${totalMinutes}m';
    final totalHours = totalMinutes ~/ 60;
    return '${totalHours}h';
  }

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
  static bool hasExplicitPureBlack() =>
      _prefs?.containsKey(_pureBlackKey) ?? false;
  static Future<void> setPureBlack(bool val) async =>
      await _prefs?.setBool(_pureBlackKey, val);

  static String? getStoredSurfaceStyle() =>
      _prefs?.getString(_surfaceStyleKey);
  static Future<void> setSurfaceStyle(String style) async =>
      await _prefs?.setString(_surfaceStyleKey, style);

  static int getAccentColor() =>
      _prefs?.getInt(_accentColorKey) ?? 0xFF8E24AA; // Default Purple
  static Future<void> setAccentColor(int color) async =>
      await _prefs?.setInt(_accentColorKey, color);

  static bool getAdaptivePlayerTint() =>
      _prefs?.getBool(_adaptivePlayerTintKey) ?? false;
  static Future<void> setAdaptivePlayerTint(bool val) async =>
      await _prefs?.setBool(_adaptivePlayerTintKey, val);

  static String normalizeAudioQuality(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'high':
      default:
        return 'High';
    }
  }

  static String getAudioQuality() =>
      normalizeAudioQuality(_prefs?.getString(_audioQualityKey));
  static Future<void> setAudioQuality(String quality) async =>
      await _prefs?.setString(_audioQualityKey, normalizeAudioQuality(quality));

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

  // --- Persistent Offline Downloads Index ---
  static Map<String, Map<String, dynamic>> getDownloadedTracks() {
    final raw = _prefs?.getString(_downloadedTracksKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, Map<String, dynamic>>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            result[entry.key.toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
        return result;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveDownloadedTrackRecord({
    required String songId,
    required String contentUri,
    required String displayName,
    required String title,
    required String artist,
  }) async {
    final map = getDownloadedTracks();
    map[songId] = {
      'contentUri': contentUri,
      'displayName': displayName,
      'title': title,
      'artist': artist,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    await _prefs?.setString(_downloadedTracksKey, jsonEncode(map));
  }

  static Future<void> removeDownloadedTrackRecord(String songId) async {
    final map = getDownloadedTracks();
    if (map.remove(songId) != null) {
      await _prefs?.setString(_downloadedTracksKey, jsonEncode(map));
    }
  }

  static Future<void> replaceDownloadedTrackRecords(
    Map<String, Map<String, dynamic>> records,
  ) async {
    await _prefs?.setString(_downloadedTracksKey, jsonEncode(records));
  }
}
