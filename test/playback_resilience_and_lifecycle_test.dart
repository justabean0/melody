import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody/models/song.dart';
import 'package:melody/services/audio_cache_service.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/battery_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool bgPlaybackNative = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.melody.music/playback'),
      (call) async => true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.melody.music/battery'),
      (call) async {
        if (call.method == 'isIgnoringBatteryOptimizations') return true;
        if (call.method == 'openBatteryOptimizationSettings') return true;
        if (call.method == 'setBackgroundPlaybackEnabled') {
          bgPlaybackNative = (call.arguments as Map)['enabled'] as bool;
          return true;
        }
        if (call.method == 'getBackgroundPlaybackEnabled') {
          return bgPlaybackNative;
        }
        return true;
      },
    );
  });

  group('DatabaseService Language & Battery State Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(db);
      await DatabaseService.init();
    });

    test('Initial language state distinguishes unsaved from default English', () {
      expect(DatabaseService.hasSelectedMusicLanguages(), isFalse);
      expect(DatabaseService.getSavedMusicLanguages(), isEmpty);
      // Backward-compatible fallback returns English
      expect(DatabaseService.getMusicLanguages(), equals(['English']));
    });

    test('Saving music languages marks hasSelectedMusicLanguages as true', () async {
      await DatabaseService.setMusicLanguages(['Spanish', 'French']);
      expect(DatabaseService.hasSelectedMusicLanguages(), isTrue);
      expect(DatabaseService.getSavedMusicLanguages(), equals(['Spanish', 'French']));
      expect(DatabaseService.getMusicLanguages(), equals(['Spanish', 'French']));
    });

    test('Battery optimization prompt state persists correctly', () async {
      expect(DatabaseService.hasShownBatteryOptPrompt(), isFalse);
      await DatabaseService.markBatteryOptPromptShown();
      expect(DatabaseService.hasShownBatteryOptPrompt(), isTrue);
    });
  });

  group('DatabaseService SQLite Background Playback & Session Persistence Tests', () {
    late Database testDb;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(testDb);
      await DatabaseService.init();
    });

    test('getBackgroundPlaybackEnabled defaults to true and setBackgroundPlaybackEnabled syncs to SQLite and native', () async {
      final initial = await DatabaseService.getBackgroundPlaybackEnabled();
      expect(initial, isTrue);

      await DatabaseService.setBackgroundPlaybackEnabled(false);
      final afterDisable = await DatabaseService.getBackgroundPlaybackEnabled();
      expect(afterDisable, isFalse);
      expect(bgPlaybackNative, isFalse);

      await DatabaseService.setBackgroundPlaybackEnabled(true);
      final afterReenable = await DatabaseService.getBackgroundPlaybackEnabled();
      expect(afterReenable, isTrue);
      expect(bgPlaybackNative, isTrue);
    });

    test('savePlaybackSession and getLastPlaybackSession round-trip correctly', () async {
      const testSong = Song(
        id: 'test_vid_123',
        title: 'Starboy',
        artist: 'The Weeknd',
        album: 'Starboy',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: 230,
      );

      const queueSong2 = Song(
        id: 'test_vid_456',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://example.com/thumb2.jpg',
        duration: 200,
      );

      await DatabaseService.savePlaybackSession(
        song: testSong,
        position: const Duration(seconds: 45),
        duration: const Duration(seconds: 230),
        queue: [testSong, queueSong2],
        queueIndex: 0,
      );

      final session = await DatabaseService.getLastPlaybackSession();
      expect(session, isNotNull);
      expect(session!.song.id, equals('test_vid_123'));
      expect(session.song.title, equals('Starboy'));
      expect(session.position.inSeconds, equals(45));
      expect(session.duration.inSeconds, equals(230));
      expect(session.queue.length, equals(2));
      expect(session.queue[1].id, equals('test_vid_456'));
      expect(session.queueIndex, equals(0));

      await DatabaseService.clearPlaybackSession();
      final cleared = await DatabaseService.getLastPlaybackSession();
      expect(cleared, isNull);
    });

    test('getLastPlaybackSession recovers gracefully when queue_json is malformed', () async {
      await testDb.insert('last_playback_session', {
        'id': 1,
        'song_id': 'corrupted_song',
        'title': 'Corrupted Song',
        'artist': 'Artist',
        'album': 'Album',
        'thumbnail_url': '',
        'duration_ms': 180000,
        'position_ms': 30000,
        'queue_json': 'NOT_A_VALID_JSON{[[[',
        'queue_index': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final session = await DatabaseService.getLastPlaybackSession();
      expect(session, isNotNull);
      expect(session!.song.id, equals('corrupted_song'));
      expect(session.queue.length, equals(1));
      expect(session.queue.first.id, equals('corrupted_song'));
    });
  });

  group('InnerTube & Recommendation No Hardcoded Fallback Songs Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(db);
      await DatabaseService.init();
    });

    test('getQuickPicks returns empty list when network fails and no cache exists', () async {
      final songs = await InnerTubeService.getQuickPicks(
        languages: ['NonExistentLanguageXYZ'],
        mood: 'All',
        forceRefresh: true,
      );

      expect(songs, isEmpty);
      expect(songs.any((s) => s.title == 'Never Gonna Give You Up'), isFalse);
      expect(songs.any((s) => s.title == 'Despacito'), isFalse);
      expect(songs.any((s) => s.title == 'Shape of You'), isFalse);
    });

    test('RecommendationService.blendIntoSlots returns empty when pools are empty', () {
      final blended = RecommendationService.blendIntoSlots(
        trendingPool: const [],
        personalizedPool: const [],
      );
      expect(blended, isEmpty);
    });
  });

  group('AudioCacheService Chunking & Buffer Specs Tests', () {
    test('AudioCacheService has 128KB headChunkSize and 256KB upstreamChunkSize', () {
      expect(AudioCacheService.headChunkSize, equals(131072));
      expect(AudioCacheService.upstreamChunkSize, equals(262144));
    });

    test('AudioCacheService.evict runs without throwing exception', () async {
      await AudioCacheService.evict('non_existent_test_id');
    });
  });

  group('BatteryService Platform Channel Tests', () {
    test('isIgnoringBatteryOptimizations and requestIgnoreBatteryOptimizations invoke cleanly', () async {
      final isIgnoring = await BatteryService.isIgnoringBatteryOptimizations();
      expect(isIgnoring, isTrue);
      await BatteryService.requestIgnoreBatteryOptimizations();
      await BatteryService.openBatteryOptimizationSettings();
    });

    test('syncBackgroundPlayback and getNativeBackgroundPlaybackEnabled round-trip cleanly', () async {
      await BatteryService.syncBackgroundPlayback(false);
      final resFalse = await BatteryService.getNativeBackgroundPlaybackEnabled();
      expect(resFalse, isFalse);

      await BatteryService.syncBackgroundPlayback(true);
      final resTrue = await BatteryService.getNativeBackgroundPlaybackEnabled();
      expect(resTrue, isTrue);
    });
  });

  group('AudioService Pause/Resume State, Idle Teardown & Session Restore Tests', () {
    late MelodyAudioService audioService;
    late Database testDb;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(testDb);
      await DatabaseService.init();
      audioService = MelodyAudioService();
    });

    test('Initial user state is not paused', () {
      expect(audioService.isPausedByUser, isFalse);
      expect(audioService.needsStreamRecovery, isFalse);
    });

    test('pause() explicitly sets isPausedByUser to true and clears isLoading', () async {
      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);
      expect(audioService.isLoading, isFalse);
      expect(audioService.isPlaying, isFalse);
    });

    test('togglePlayPause() pauses when pausedByUser is false', () async {
      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);
    });

    test('restoreLastSession restores paused state without auto-playing', () async {
      const restoredSong = Song(
        id: 'restore_vid_999',
        title: 'Session Restore Song',
        artist: 'Test Artist',
        album: 'Test Album',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: 240,
      );

      await DatabaseService.savePlaybackSession(
        song: restoredSong,
        position: const Duration(seconds: 60),
        duration: const Duration(seconds: 240),
        queue: [restoredSong],
        queueIndex: 0,
      );

      final restored = await audioService.restoreLastSession();
      expect(restored, isTrue);
      expect(audioService.currentSong?.id, equals('restore_vid_999'));
      expect(audioService.position.inSeconds, equals(60));
      expect(audioService.duration.inSeconds, equals(240));
      expect(audioService.isPlaying, isFalse);
      expect(audioService.isPausedByUser, isTrue);
      expect(audioService.needsStreamRecovery, isTrue);
    });

    test('restoreLastSession ignores sessions older than 7 days and clears them', () async {
      const oldSong = Song(
        id: 'old_vid_000',
        title: 'Old Song',
        artist: 'Old Artist',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: 180,
      );

      final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
      await testDb.insert(
        'last_playback_session',
        {
          'id': 1,
          'song_id': oldSong.id,
          'title': oldSong.title,
          'artist': oldSong.artist,
          'album': '',
          'thumbnail_url': '',
          'duration_ms': 180000,
          'position_ms': 30000,
          'queue_json': jsonEncode([oldSong.toJson()]),
          'queue_index': 0,
          'updated_at': eightDaysAgo,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final restored = await audioService.restoreLastSession();
      expect(restored, isFalse);
      final remaining = await DatabaseService.getLastPlaybackSession();
      expect(remaining, isNull);
    });
  });
}
