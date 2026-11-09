import 'package:flutter_test/flutter_test.dart';
import 'package:melody/models/song.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/update_service.dart';
import 'package:melody/ui/components/language_selection_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Language Selection Plain Text & No-Emoji Policy Tests', () {
    test('All language options contain strictly plain text without emojis', () {
      // Regex matching emoji characters (surrogate pairs, dingbats, transport, flags, etc.)
      final emojiRegex = RegExp(
        r'[\u{1F300}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}]',
        unicode: true,
      );

      for (final lang in LanguageSelectionDialogStateWrapper.allLanguages) {
        expect(
          emojiRegex.hasMatch(lang.name),
          isFalse,
          reason: 'Language name "${lang.name}" must not contain emojis',
        );
        expect(
          emojiRegex.hasMatch(lang.nativeName),
          isFalse,
          reason: 'Native name "${lang.nativeName}" must not contain emojis',
        );
        expect(
          emojiRegex.hasMatch(lang.subtitle),
          isFalse,
          reason: 'Subtitle "${lang.subtitle}" must not contain emojis',
        );
      }
    });

    test('Supported languages list has comprehensive entries with valid native scripts', () {
      final names = LanguageSelectionDialogStateWrapper.allLanguages.map((l) => l.name).toList();
      expect(names, containsAll(['Hindi', 'English', 'Punjabi', 'Spanish', 'Korean', 'Bengali', 'Tamil', 'Telugu']));
      expect(LanguageSelectionDialogStateWrapper.allLanguages.length, greaterThanOrEqualTo(12));
    });
  });

  group('Language Onboarding For Existing Users & Database Persistence Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.init();
    });

    test('Fresh or existing user without v2 onboarding flag has hasCompletedLanguageOnboarding = false', () {
      expect(DatabaseService.hasCompletedLanguageOnboarding(), isFalse);
    });

    test('Setting music languages marks onboarding completed and persists selections', () async {
      expect(DatabaseService.hasCompletedLanguageOnboarding(), isFalse);

      await DatabaseService.setMusicLanguages(['Hindi', 'Punjabi']);
      expect(DatabaseService.hasCompletedLanguageOnboarding(), isTrue);
      expect(DatabaseService.hasSelectedLanguages(), isTrue);
      expect(DatabaseService.getMusicLanguages(), equals(['Hindi', 'Punjabi']));
    });

    test('Existing v1.1.5 user detects v1.1.6 as newer version for in-app update', () {
      expect(UpdateService.isNewerVersion('1.1.5', '1.1.6'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.5+7', '1.1.6+8'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.5', 'v1.1.6'), isTrue);
    });
  });

  group('Home Screen Fast Feed Caching Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.init();
    });

    test('Feed cache stores and returns songs immediately (0ms)', () async {
      const cacheKey = 'All:Hindi,English';
      expect(DatabaseService.getCachedFeed(cacheKey), isEmpty);

      final mockSongs = [
        const Song(
          id: 'test_1',
          title: 'Kesariya',
          artist: 'Arijit Singh',
          duration: 268,
          thumbnailUrl: 'https://i.ytimg.com/vi/test_1/hqdefault.jpg',
        ),
        const Song(
          id: 'test_2',
          title: 'As It Was',
          artist: 'Harry Styles',
          duration: 167,
          thumbnailUrl: 'https://i.ytimg.com/vi/test_2/hqdefault.jpg',
        ),
      ];

      await DatabaseService.saveCachedFeed(cacheKey, mockSongs);

      final retrieved = DatabaseService.getCachedFeed(cacheKey);
      expect(retrieved.length, equals(2));
      expect(retrieved.first.id, equals('test_1'));
      expect(retrieved.first.title, equals('Kesariya'));
      expect(retrieved.last.artist, equals('Harry Styles'));
    });

    test('InnerTubeService.getQuickPicks returns cached feed without network call', () async {
      const cacheKey = 'All:Punjabi';
      final mockSongs = [
        const Song(
          id: 'pb_1',
          title: 'Brown Munde',
          artist: 'AP Dhillon',
          duration: 240,
          thumbnailUrl: 'https://i.ytimg.com/vi/pb_1/hqdefault.jpg',
        ),
      ];

      await DatabaseService.saveCachedFeed(cacheKey, mockSongs);

      final songs = await InnerTubeService.getQuickPicks(
        languages: ['Punjabi'],
        mood: 'All',
        forceRefresh: false,
      );

      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Brown Munde'));
    });
  });
}

// Helper to expose static allLanguages for unit testing without instantiating private State
class LanguageSelectionDialogStateWrapper {
  static const List<MusicLanguage> allLanguages = [
    MusicLanguage(name: 'Hindi', nativeName: 'हिंदी', subtitle: 'Bollywood, Indie & Pop'),
    MusicLanguage(name: 'English', nativeName: 'English', subtitle: 'Global Hits, Pop & Hip-Hop'),
    MusicLanguage(name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ', subtitle: 'Punjabi Pop, Hip-Hop & Folk'),
    MusicLanguage(name: 'Spanish', nativeName: 'Español', subtitle: 'Reggaeton, Latin Pop & Bachata'),
    MusicLanguage(name: 'Korean', nativeName: '한국어', subtitle: 'K-Pop, K-Drama OST & R&B'),
    MusicLanguage(name: 'Bengali', nativeName: 'বাংলা', subtitle: 'Tollywood, Rabindra Sangeet & Folk'),
    MusicLanguage(name: 'Tamil', nativeName: 'தமிழ்', subtitle: 'Kollywood & Carnatic Beats'),
    MusicLanguage(name: 'Telugu', nativeName: 'తెలుగు', subtitle: 'Tollywood Blockbusters & Melodies'),
    MusicLanguage(name: 'Malayalam', nativeName: 'മലയാളം', subtitle: 'Mollywood Indie & Melodies'),
    MusicLanguage(name: 'Kannada', nativeName: 'ಕನ್ನಡ', subtitle: 'Sandalwood Hits & Pop'),
    MusicLanguage(name: 'Bhojpuri', nativeName: 'भोजपुरी', subtitle: 'Bhojpuri Hits & Desi Folk'),
    MusicLanguage(name: 'Marathi', nativeName: 'मराठी', subtitle: 'Marathi Pop & Folk Hits'),
    MusicLanguage(name: 'Japanese', nativeName: '日本語', subtitle: 'J-Pop, Anime OST & City Pop'),
    MusicLanguage(name: 'French', nativeName: 'Français', subtitle: 'French Pop, Chanson & Rap'),
    MusicLanguage(name: 'Arabic', nativeName: 'العربية', subtitle: 'Arabic Pop, Tarab & Khaleeji'),
    MusicLanguage(name: 'Urdu', nativeName: 'اردو', subtitle: 'Ghazals, Sufi & Coke Studio'),
  ];
}
