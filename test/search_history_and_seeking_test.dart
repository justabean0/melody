import 'package:flutter_test/flutter_test.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/services/audio_cache_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseService & SearchProvider Search History Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.init();
      await DatabaseService.clearSearchHistory();
    });

    test('Search history is initially empty', () {
      expect(DatabaseService.getSearchHistory(), isEmpty);
    });

    test('addSearchHistory adds items with recency ordering and case-insensitive deduplication', () async {
      await DatabaseService.addSearchHistory('Arijit Singh');
      await DatabaseService.addSearchHistory('Miley Cyrus');
      await DatabaseService.addSearchHistory('arijit singh'); // duplicate with different casing

      final history = DatabaseService.getSearchHistory();
      expect(history.length, equals(2));
      expect(history[0], equals('arijit singh')); // most recent at index 0
      expect(history[1], equals('Miley Cyrus'));
    });

    test('removeSearchHistory removes target query correctly', () async {
      await DatabaseService.addSearchHistory('Song 1');
      await DatabaseService.addSearchHistory('Song 2');
      await DatabaseService.addSearchHistory('Song 3');

      await DatabaseService.removeSearchHistory('Song 2');
      final history = DatabaseService.getSearchHistory();
      expect(history, equals(['Song 3', 'Song 1']));
    });

    test('clearSearchHistory wipes all history entries', () async {
      await DatabaseService.addSearchHistory('Song 1');
      await DatabaseService.addSearchHistory('Song 2');
      await DatabaseService.clearSearchHistory();
      expect(DatabaseService.getSearchHistory(), isEmpty);
    });

    test('SearchProvider loads history and returns matching history entries', () async {
      await DatabaseService.addSearchHistory('Believer Imagine Dragons');
      await DatabaseService.addSearchHistory('Kesariya Arijit');
      await DatabaseService.addSearchHistory('Bones Imagine Dragons');

      final provider = SearchProvider();
      expect(provider.history.length, equals(3));

      // Query matching 'imagine'
      final matches = provider.getMatchingHistory('imagine');
      expect(matches.length, equals(2));
      expect(matches, contains('Bones Imagine Dragons'));
      expect(matches, contains('Believer Imagine Dragons'));

      // Remove from history through provider
      await provider.removeFromHistory('Kesariya Arijit');
      expect(provider.history.length, equals(2));
      expect(provider.history, isNot(contains('Kesariya Arijit')));
    });
  });

  group('AudioCacheService Long Track Content Length & Range Tests', () {
    test('headChunkSize is standard 128KB (~6-8s of audio)', () {
      expect(AudioCacheService.headChunkSize, equals(131072));
    });

    test('getPlayableUrl returns direct URL when head is not cached', () {
      const url = 'https://googlevideo.com/videoplayback?id=123&clen=16000000';
      final playable = AudioCacheService.getPlayableUrl('uncached_vid', url);
      expect(playable, equals(url));
    });
  });
}
