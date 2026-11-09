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
}
