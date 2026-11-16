import 'package:flutter_test/flutter_test.dart';
import 'package:melody/models/song.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecommendationService Single Song Filter Tests', () {
    test('Identifies standard single songs correctly', () {
      const normalTrack = Song(
        id: 'track_1',
        title: 'Flowers',
        artist: 'Miley Cyrus',
        duration: 200,
        thumbnailUrl: 'https://i.ytimg.com/vi/track_1/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(normalTrack), isTrue);

      const bollywoodSingle = Song(
        id: 'track_2',
        title: 'Kesariya (From "Brahmastra")',
        artist: 'Arijit Singh, Pritam',
        duration: 268,
        thumbnailUrl: 'https://i.ytimg.com/vi/track_2/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(bollywoodSingle), isTrue);
    });

    test('Rejects multi-hour mixes, DJ compilations, and jukeboxes', () {
      const longJukebox = Song(
        id: 'mix_1',
        title: 'Best Romantic Songs | New Trending Bollywood Songs',
        artist: 'Grow Music',
        duration: 3290, // 54 mins
        thumbnailUrl: 'https://i.ytimg.com/vi/mix_1/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(longJukebox), isFalse);

      const partyMix = Song(
        id: 'mix_2',
        title: 'Bollywood Patakha Hits 2026 - Non Stop Party Mix',
        artist: 'Zee Music',
        duration: 250, // Short duration but compilation title
        thumbnailUrl: 'https://i.ytimg.com/vi/mix_2/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(partyMix), isFalse);

      const audioJukebox = Song(
        id: 'mix_3',
        title: 'Arijit Singh Audio Jukebox',
        artist: 'T-Series',
        duration: 350,
        thumbnailUrl: 'https://i.ytimg.com/vi/mix_3/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(audioJukebox), isFalse);

      const tooShortTeaser = Song(
        id: 'short_1',
        title: 'Song Teaser',
        artist: 'Artist',
        duration: 30, // < 60s
        thumbnailUrl: 'https://i.ytimg.com/vi/short_1/hqdefault.jpg',
      );
      expect(RecommendationService.isSingleSong(tooShortTeaser), isFalse);
    });
  });

  group('RecommendationService Genre Inference Tests', () {
    test('Infers genres accurately based on song metadata', () {
      const chillSong = Song(
        id: 's_chill',
        title: 'Midnight Coffee Lo-Fi Beats',
        artist: 'ChillHop Music',
        duration: 180,
        thumbnailUrl: '',
      );
      expect(RecommendationService.inferGenre(chillSong), equals('Chill'));

      const romanticSong = Song(
        id: 's_rom',
        title: 'Tum Hi Ho Dil Ki Baat (Romantic Love Song)',
        artist: 'Arijit Singh',
        duration: 260,
        thumbnailUrl: '',
      );
      expect(RecommendationService.inferGenre(romanticSong), equals('Romance'));

      const hipHopSong = Song(
        id: 's_rap',
        title: 'No Cap - Official Drill Rap Flow',
        artist: 'KRSNA',
        duration: 195,
        thumbnailUrl: '',
      );
      expect(RecommendationService.inferGenre(hipHopSong), equals('Hip-Hop'));

      const workoutSong = Song(
        id: 's_gym',
        title: 'Unstoppable Energy Beast Mode Gym Workout',
        artist: 'Gym Motivation',
        duration: 210,
        thumbnailUrl: '',
      );
      expect(RecommendationService.inferGenre(workoutSong), equals('Workout'));
    });
  });

  group('RecommendationService User Taste Profile & Algorithmic Re-ranking Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.init();
    });

    test('Initial user taste profile has empty history', () {
      final taste = RecommendationService.getUserTasteProfile();
      expect(taste.hasHistory, isFalse);
      expect(taste.dominantGenre, equals('Pop'));
    });

    test('Learns dominant genre and top artists from user listening history', () async {
      // Simulate user listening to romantic songs by Arijit Singh
      await DatabaseService.addToHistory(const Song(
        id: 'song_h1',
        title: 'Apna Bana Le - Romantic Love',
        artist: 'Arijit Singh',
        duration: 245,
        thumbnailUrl: '',
      ));
      await DatabaseService.addToHistory(const Song(
        id: 'song_h2',
        title: 'O Maahi Romantic Melodies',
        artist: 'Arijit Singh',
        duration: 230,
        thumbnailUrl: '',
      ));

      final taste = RecommendationService.getUserTasteProfile();
      expect(taste.hasHistory, isTrue);
      expect(taste.dominantGenre, equals('Romance'));
      expect(taste.topArtists, contains('Arijit Singh'));
    });
  });

  group('RecommendationService Slot-Based Interleaved Blending Tests', () {
    test('Guarantees trending songs in Slots 1-2 & 5-6 and personalized in Slots 3-4 & 7-8', () {
      final trendingPool = List.generate(
        6,
        (i) => Song(
          id: 'trend_$i',
          title: 'Trending Hit $i',
          artist: 'Global Star $i',
          duration: 200,
          thumbnailUrl: '',
        ),
      );

      final personalizedPool = List.generate(
        6,
        (i) => Song(
          id: 'pers_$i',
          title: 'Personalized Pick $i',
          artist: 'Favorite Artist $i',
          duration: 210,
          thumbnailUrl: '',
        ),
      );

      final blended = RecommendationService.blendIntoSlots(
        trendingPool: trendingPool,
        personalizedPool: personalizedPool,
      );

      expect(blended.length, greaterThanOrEqualTo(8));

      // Slot 1 & 2: Trending singles
      expect(blended[0].id, equals('trend_0'));
      expect(blended[1].id, equals('trend_1'));

      // Slot 3 & 4: Personalized recommendations
      expect(blended[2].id, equals('pers_0'));
      expect(blended[3].id, equals('pers_1'));

      // Slot 5 & 6: Trending singles
      expect(blended[4].id, equals('trend_2'));
      expect(blended[5].id, equals('trend_3'));

      // Slot 7 & 8: Personalized recommendations
      expect(blended[6].id, equals('pers_2'));
      expect(blended[7].id, equals('pers_3'));
    });

    test('Deduplicates song IDs that appear in both trending and personalized pools', () {
      final trending = [
        const Song(id: 'overlap_1', title: 'Shared Song', artist: 'Artist', duration: 180, thumbnailUrl: ''),
        const Song(id: 'trend_unique', title: 'Trend Only', artist: 'Artist', duration: 180, thumbnailUrl: ''),
      ];

      final personalized = [
        const Song(id: 'overlap_1', title: 'Shared Song', artist: 'Artist', duration: 180, thumbnailUrl: ''),
        const Song(id: 'pers_unique', title: 'Personalized Only', artist: 'Artist', duration: 180, thumbnailUrl: ''),
      ];

      final blended = RecommendationService.blendIntoSlots(
        trendingPool: trending,
        personalizedPool: personalized,
      );

      final ids = blended.map((s) => s.id).toList();
      expect(ids.where((id) => id == 'overlap_1').length, equals(1));
      expect(ids, contains('trend_unique'));
      expect(ids, contains('pers_unique'));
    });

    test('Gracefully serves trending singles when personalized pool is empty (fresh user)', () {
      final trending = List.generate(
        5,
        (i) => Song(
          id: 'fresh_trend_$i',
          title: 'Hit $i',
          artist: 'Artist $i',
          duration: 190,
          thumbnailUrl: '',
        ),
      );

      final blended = RecommendationService.blendIntoSlots(
        trendingPool: trending,
        personalizedPool: const [],
      );

      expect(blended.length, greaterThanOrEqualTo(5));
      expect(blended.take(5).map((s) => s.id), equals([
        'fresh_trend_0',
        'fresh_trend_1',
        'fresh_trend_2',
        'fresh_trend_3',
        'fresh_trend_4',
      ]));
    });
  });
}
