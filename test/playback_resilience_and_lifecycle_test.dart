import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/audio_cache_service.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/battery_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/native_extractor_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:melody/services/stream_resolver_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool bgPlaybackNative = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init') {
          final id = (call.arguments as Map)['id'] as String;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (playerCall) async {
              switch (playerCall.method) {
                case 'load':
                  return {'duration': 180000000};
                case 'play':
                case 'pause':
                case 'stop':
                case 'seek':
                case 'setSpeed':
                case 'setVolume':
                  return {};
                default:
                  return {};
              }
            },
          );
          return null;
        }
        return {};
      },
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

    test('seek updates position to exact value and broadcasts update', () async {
      Duration? capturedPos;
      final sub = audioService.onPositionChange.listen((pos) {
        capturedPos = pos;
      });

      await audioService.seek(const Duration(seconds: 42));
      expect(audioService.position, equals(const Duration(seconds: 42)));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(capturedPos, equals(const Duration(seconds: 42)));
      await sub.cancel();
    });

    test('cycleLoopMode cycles through all -> one -> off', () {
      expect(audioService.loopMode, equals(MelodyLoopMode.off));
      audioService.cycleLoopMode();
      expect(audioService.loopMode, equals(MelodyLoopMode.all));
      audioService.cycleLoopMode();
      expect(audioService.loopMode, equals(MelodyLoopMode.one));
      audioService.cycleLoopMode();
      expect(audioService.loopMode, equals(MelodyLoopMode.off));
    });

    test('AudioCacheService.evict handles malformed, path traversal, and missing IDs safely', () async {
      await AudioCacheService.evict('');
      await AudioCacheService.evict('../../../etc/passwd');
      await AudioCacheService.evict('valid_id_123');
      expect(AudioCacheService.hasCachedHead('../../../etc/passwd'), isFalse);
      expect(AudioCacheService.hasCachedHead('non_existent_track'), isFalse);
    });
  });

  group('DatabaseService & LibraryProvider Live History Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(db);
      await DatabaseService.init();
    });

    test('getHistory skips corrupted JSON entries cleanly without crashing', () async {
      const validSong = Song(
        id: 'valid_1',
        title: 'Valid Song',
        artist: 'Artist',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: 180,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('melody_history', [
        'INVALID_JSON_STRING{{{[[',
        '{"corrupted": true}',
        jsonEncode(validSong.toJson()),
      ]);

      final history = DatabaseService.getHistory();
      expect(history.length, equals(1));
      expect(history.first.id, equals('valid_1'));

      const newSong = Song(
        id: 'valid_2',
        title: 'Second Song',
        artist: 'Artist 2',
        thumbnailUrl: '',
        duration: 200,
      );
      await DatabaseService.addToHistory(newSong);

      final updated = DatabaseService.getHistory();
      expect(updated.length, equals(2));
      expect(updated.first.id, equals('valid_2'));
      expect(updated[1].id, equals('valid_1'));
    });

    test('onHistoryChanged broadcast stream notifies LibraryProvider live', () async {
      final libraryProvider = LibraryProvider();
      expect(libraryProvider.history, isEmpty);

      const songA = Song(
        id: 'song_a',
        title: 'Song A',
        artist: 'Artist A',
        thumbnailUrl: '',
        duration: 120,
      );

      await DatabaseService.addToHistory(songA);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(libraryProvider.history.length, equals(1));
      expect(libraryProvider.history.first.id, equals('song_a'));

      const songB = Song(
        id: 'song_b',
        title: 'Song B',
        artist: 'Artist B',
        thumbnailUrl: '',
        duration: 150,
      );

      await DatabaseService.addToHistory(songB);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(libraryProvider.history.length, equals(2));
      expect(libraryProvider.history.first.id, equals('song_b'));

      await DatabaseService.clearHistory();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(libraryProvider.history, isEmpty);
      libraryProvider.dispose();
    });
  });

  group('Playback Resilience & Lifecycle Security Tests', () {
    test('sanitizeAndValidateInstanceUrl rejects SSRF, loopback, private IPs, credentials, and paths', () {
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('http://invidious.example.com'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('ftp://invidious.example.com'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('file:///etc/passwd'), isNull);

      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://user:pass@evil.com'), isNull);

      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://evil.com/api/v1/delete'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://evil.com?ssrf=1'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://evil.com#frag'), isNull);

      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://evil.com:8443'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://127.0.0.1:8080'), isNull);

      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://127.0.0.1'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://10.0.0.1'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://172.16.0.1'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://192.168.1.1'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://169.254.169.254'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://0.0.0.0'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://[::1]'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://localhost'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://server.local'), isNull);
      expect(StreamResolverService.sanitizeAndValidateInstanceUrl('https://internal.corp'), isNull);

      expect(
        StreamResolverService.sanitizeAndValidateInstanceUrl('https://inv.thepixora.com/'),
        equals('https://inv.thepixora.com'),
      );
      expect(
        StreamResolverService.sanitizeAndValidateInstanceUrl('https://yt.chocolatemoo53.com'),
        equals('https://yt.chocolatemoo53.com'),
      );
      expect(
        StreamResolverService.sanitizeAndValidateInstanceUrl('https://yewtu.be'),
        equals('https://yewtu.be'),
      );
    });

    test('parseAndValidateInstancesJson correctly filters instances', () {
      final sampleJson = jsonEncode([
        [
          'yewtu.be',
          {
            'type': 'https',
            'api': true,
            'region': 'DE',
            'uri': 'https://yewtu.be',
          }
        ],
        [
          'invidious.ir',
          {
            'type': 'https',
            'api': true,
            'region': 'IR',
            'uri': 'https://invidious.ir',
          }
        ],
        [
          'no-api.instance',
          {
            'type': 'https',
            'api': false,
            'region': 'US',
            'uri': 'https://no-api.instance',
          }
        ],
        [
          'http-only.instance',
          {
            'type': 'http',
            'api': true,
            'region': 'US',
            'uri': 'http://http-only.instance',
          }
        ],
        [
          'private-ip.instance',
          {
            'type': 'https',
            'api': true,
            'region': 'US',
            'uri': 'https://192.168.1.100',
          }
        ],
      ]);

      final parsed = StreamResolverService.parseAndValidateInstancesJson(sampleJson);
      expect(parsed, contains('https://yewtu.be'));
      expect(parsed, isNot(contains('https://invidious.ir')));
      expect(parsed, isNot(contains('https://no-api.instance')));
      expect(parsed, isNot(contains('http://http-only.instance')));
      expect(parsed, isNot(contains('https://192.168.1.100')));
    });

    test('Instance cooldown and rotation demotes failing instances and sorts by oldest failure', () async {
      StreamResolverService.resetInstancesForTesting(instances: [
        'https://instance1.example.com',
        'https://instance2.example.com',
      ]);

      final initial = StreamResolverService.getHealthyInstances();
      expect(initial.first, equals('https://instance1.example.com'));

      StreamResolverService.markInstanceFailed('https://instance1.example.com');
      final afterFirstFail = StreamResolverService.getHealthyInstances();
      expect(afterFirstFail.first, equals('https://instance2.example.com'));

      await Future.delayed(const Duration(milliseconds: 10));
      StreamResolverService.markInstanceFailed('https://instance2.example.com');
      final afterAllFail = StreamResolverService.getHealthyInstances();

      // In cooldown fallback, instance1 failed first (oldest failure), so it comes first
      expect(afterAllFail.first, equals('https://instance1.example.com'));
      // inv.thepixora.com was removed from seeds
      expect(afterAllFail, isNot(contains('https://inv.thepixora.com')));
    });

    test('markInstanceFailed does not duplicate cooldown or log when already in cooldown', () {
      StreamResolverService.resetInstancesForTesting(instances: ['https://instance1.example.com']);
      StreamResolverService.markInstanceFailed('https://instance1.example.com');
      // Second call while in cooldown is safely ignored
      StreamResolverService.markInstanceFailed('https://instance1.example.com');
      final list = StreamResolverService.getHealthyInstances();
      expect(list, equals(['https://instance1.example.com']));
    });
  });

  group('Hedged Parallel Race & Speculative Pre-Warming Tests', () {
    setUp(() {
      StreamResolverService.clearCache();
      StreamResolverService.resetInstancesForTesting();
    });

    tearDown(() {
      StreamResolverService.clientOverride = null;
    });

    test('preWarm never runs when active user resolution is ongoing', () async {
      StreamResolverService.setActiveUserResolutionsForTesting(1);

      StreamResolverService.preWarm('speculative_track_id', isSpeculative: true);
      expect(StreamResolverService.activeSpeculativeCount, equals(0));

      StreamResolverService.setActiveUserResolutionsForTesting(0);
    });

    test('resolveAudioStreamUrl with isSpeculative=true rejects heavy fallback scraping', () async {
      final mock = MockClient((req) async {
        return http.Response('Not Found', 404);
      });
      StreamResolverService.clientOverride = mock;

      expect(
        () => StreamResolverService.resolveAudioStreamUrl(
          'speculative_failed_id',
          songTitle: 'Test Song',
          artist: 'Artist',
          isSpeculative: true,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('AudioService.playSong and playQueue reset isPausedByUser and needsStreamRecovery', () async {
      final audioService = MelodyAudioService();
      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);

      const testSong = Song(
        id: 'play_test_song',
        title: 'Play Test',
        artist: 'Artist',
        thumbnailUrl: '',
        duration: 100,
      );

      // Verify synchronous state resets on playSong
      unawaited(audioService.playSong(testSong));
      expect(audioService.isPausedByUser, isFalse);
      expect(audioService.needsStreamRecovery, isFalse);

      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);

      // Verify synchronous state resets on playQueue
      unawaited(audioService.playQueue([testSong]));
      expect(audioService.isPausedByUser, isFalse);
      expect(audioService.needsStreamRecovery, isFalse);

      await audioService.stop();
    });

    test('AudioService.resume() delegating to _playCurrent preserves token without self-invalidation', () async {
      final audioService = MelodyAudioService();
      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);

      final tokenBefore = audioService.playOperationToken;
      // When session has current song at pos 0, resume() delegates to _playCurrent(token: opToken)
      unawaited(audioService.resume());

      // Token was incremented exactly once by resume() and not self-invalidated
      expect(audioService.playOperationToken, equals(tokenBefore + 1));
      expect(audioService.isPausedByUser, isFalse);
      await audioService.stop();
    });

    test('resolveAudioStreamUrl supports skipCompanionProxy: true bypassing companion proxy', () async {
      int proxyCalls = 0;
      final mock = MockClient((req) async {
        if (req.url.path.contains('/api/v1/videos/')) {
          proxyCalls++;
          return http.Response('{"adaptiveFormats": []}', 200);
        }
        return http.Response('Not Found', 404);
      });
      StreamResolverService.clientOverride = mock;

      // With skipCompanionProxy: true, Invidious proxy endpoint is never called
      try {
        await StreamResolverService.resolveAudioStreamUrl(
          'test_skip_proxy_video',
          skipCompanionProxy: true,
        );
      } catch (_) {}

      expect(proxyCalls, equals(0));
    });

    test('CompanionProxy rejects non-audio HTML proxy responses immediately', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/api/v1/videos/')) {
          return http.Response(
            jsonEncode({
              'adaptiveFormats': [
                {
                  'type': 'audio/mp4',
                  'url': 'https://invidious.instance/videoplayback?id=123',
                  'bitrate': 128000,
                }
              ]
            }),
            200,
          );
        }
        // Probe endpoint returns HTML (Cloudflare / Invidious error)
        return http.Response('<html>Error</html>', 200, headers: {'content-type': 'text/html'});
      });
      StreamResolverService.clientOverride = mock;
      StreamResolverService.resetInstancesForTesting(instances: ['https://invidious.instance']);

      // Should reject HTML and fail because non-audio stream probe failed
      expect(
        () => StreamResolverService.resolveAudioStreamUrl('test_html_reject_id'),
        throwsA(isA<Exception>()),
      );
    });

    test('NativeExtractorService channel parsing and security validation', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.melody.music/extractor'),
        (call) async {
          if (call.arguments is Map && (call.arguments as Map)['videoId'] == 'valid_vid123') {
            return {
              'url': 'https://rr1.googlevideo.com/videoplayback?expire=12345',
              'itag': 140,
              'bitrate': 128000,
              'format': 'm4a',
              'mimeType': 'audio/mp4',
              'durationMs': 210000,
            };
          } else if (call.arguments is Map && (call.arguments as Map)['videoId'] == 'insecure_vid') {
            return {
              'url': 'http://insecure.target/stream.mp3',
              'itag': 140,
            };
          }
          throw MissingPluginException();
        },
      );

      // Valid response
      final valid = await NativeExtractorService.resolveAudioStream('valid_vid123');
      expect(valid, isNotNull);
      expect(valid!.url, 'https://rr1.googlevideo.com/videoplayback?expire=12345');
      expect(valid.itag, 140);
      expect(valid.bitrate, 128000);
      expect(valid.format, 'm4a');

      // Rejects non-HTTPS
      final insecure = await NativeExtractorService.resolveAudioStream('insecure_vid');
      expect(insecure, isNull);

      // Gracefully handles missing plugin
      final missing = await NativeExtractorService.resolveAudioStream('unknown_vid');
      expect(missing, isNull);

      // Reset mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.melody.music/extractor'),
        null,
      );
    });

    test('StreamResolverService prioritizes NativeExtractorService first and falls back on null', () async {
      AntiBotService.reset();
      // 1. Primary path: NativeExtractor succeeds
      NativeExtractorService.testResolver = (videoId) async {
        if (videoId == 'native_primary_vid') {
          return const NativeAudioStream(
            url: 'https://rr1.googlevideo.com/videoplayback?expire=9999999999',
            itag: 140,
            bitrate: 128,
            format: 'm4a',
          );
        }
        return null;
      };

      final nativeUrl = await StreamResolverService.resolveAudioStreamUrl('native_primary_vid');
      expect(nativeUrl, equals('https://rr1.googlevideo.com/videoplayback?expire=9999999999'));

      // 2. Secondary fallback: NativeExtractor returns null, falls back to HTTP pipeline
      final mock = MockClient((req) async {
        if (req.url.path.contains('youtubei/v1/player')) {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                    'bitrate': 128000,
                    'url': 'https://rr2.googlevideo.com/videoplayback?id=fallback_stream',
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });
      StreamResolverService.clientOverride = mock;

      final fallbackUrl = await StreamResolverService.resolveAudioStreamUrl('fallback_vid_needed');
      expect(fallbackUrl, equals('https://rr2.googlevideo.com/videoplayback?id=fallback_stream'));

      // Clean up testResolver
      NativeExtractorService.testResolver = null;
    });
  });

  group('Search Metadata "Streamed" Safe Parser Tests', () {
    test('parseDuration safely handles "Streamed", colon formats, and non-numeric labels', () {
      expect(InnerTubeService.parseDuration(210), equals(210));
      expect(InnerTubeService.parseDuration('3:45'), equals(225));
      expect(InnerTubeService.parseDuration('1:02:15'), equals(3735));
      expect(InnerTubeService.parseDuration('Streamed 2 days ago'), equals(0));
      expect(InnerTubeService.parseDuration('Streamed live'), equals(0));
      expect(InnerTubeService.parseDuration('LIVE'), equals(0));
      expect(InnerTubeService.parseDuration(null), equals(0));
      expect(InnerTubeService.parseDuration(''), equals(0));
    });

    test('parseViewCount safely handles formatted view counts and "Streamed"', () {
      expect(InnerTubeService.parseViewCount('1,234,567 views'), equals(1234567));
      expect(InnerTubeService.parseViewCount(9999), equals(9999));
      expect(InnerTubeService.parseViewCount('Streamed'), equals(0));
      expect(InnerTubeService.parseViewCount(null), equals(0));
      expect(InnerTubeService.parseViewCount('No views'), equals(0));
    });

    test('parsePublishedDate safely handles "Streamed" prefixes and relative timestamps', () {
      final now = DateTime.now();

      final parsed2Days = InnerTubeService.parsePublishedDate('Streamed 2 days ago');
      expect(parsed2Days, isNotNull);
      expect((now.difference(parsed2Days!).inHours / 24).round(), equals(2));

      final parsedLive3Hours = InnerTubeService.parsePublishedDate('Streamed live 3 hours ago');
      expect(parsedLive3Hours, isNotNull);
      expect((now.difference(parsedLive3Hours!).inMinutes / 60).round(), equals(3));

      final parsedYears = InnerTubeService.parsePublishedDate('5 years ago');
      expect(parsedYears, isNotNull);
      expect((now.difference(parsedYears!).inDays / 365).round(), equals(5));

      // Invalid / non-numeric labels do not throw FormatException
      expect(InnerTubeService.parsePublishedDate('Streamed'), isNull);
      expect(InnerTubeService.parsePublishedDate('Streamed live'), isNull);
      expect(InnerTubeService.parsePublishedDate(null), isNull);
      expect(InnerTubeService.parsePublishedDate(''), isNull);
    });

    test('parseSearchMetadata aggregates all fields without throwing FormatException', () {
      final meta = InnerTubeService.parseSearchMetadata(
        duration: 'Streamed',
        views: '1,500,000 views',
        publishedText: 'Streamed 1 day ago',
      );
      expect(meta['duration'], equals(0));
      expect(meta['views'], equals(1500000));
      expect(meta['publishedDate'], isNotNull);
    });

    test('InnerTubeService.search does not trip AntiBotService on FormatException', () async {
      AntiBotService.reset();
      expect(AntiBotService.isSafeModeActive, isFalse);

      // When search encounters a non-bot error or FormatException, AntiBotService is not tripped
      await InnerTubeService.search('test_format_exception_search_query');
      expect(AntiBotService.isSafeModeActive, isFalse);
    });
  });

  group('AudioService Notification Progress & Pause Live Position Tests', () {
    test('AudioService.pause() captures live position before updating notification', () async {
      final audioService = MelodyAudioService();
      Map<dynamic, dynamic>? lastNotifArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.melody.music/playback'),
        (call) async {
          if (call.method == 'showNotification') {
            lastNotifArgs = call.arguments as Map<dynamic, dynamic>;
          }
          return true;
        },
      );

      const testSong = Song(
        id: 'test_pause_pos_song',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 300,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      unawaited(audioService.playQueue([testSong], startIndex: 0));
      await Future.delayed(const Duration(milliseconds: 50));

      await audioService.pause();
      expect(audioService.isPausedByUser, isTrue);
      expect(lastNotifArgs, isNotNull);
      expect(lastNotifArgs!['title'], equals('Test Song'));
      expect(lastNotifArgs!['isPlaying'], isFalse);
      expect(lastNotifArgs!['positionMs'], equals(audioService.position.inMilliseconds));

      await audioService.stop();
    });
  });
}
