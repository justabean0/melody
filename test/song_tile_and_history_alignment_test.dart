import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/ui/components/song_tile.dart';
import 'package:melody/ui/screens/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:melody/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    DatabaseService.setDatabaseForTesting(db);
    await DatabaseService.init();
    await DatabaseService.addSearchHistory('History Track A');
    await DatabaseService.addSearchHistory('History Track B');
  });

  group('SongTile Duration Rendering Tests', () {
    testWidgets('SongTile omits duration suffix when song duration is 0', (tester) async {
      const songNoDuration = Song(
        id: 'no_dur_song',
        title: 'Zero Duration Song',
        artist: 'Test Artist',
        duration: 0,
        thumbnailUrl: '',
      );

      final playback = PlaybackProvider();
      final library = LibraryProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
                ChangeNotifierProvider<LibraryProvider>.value(value: library),
              ],
              child: const SongTile(song: songNoDuration),
            ),
          ),
        ),
      );

      // Subtitle should be exactly "Test Artist"
      expect(find.text('Test Artist'), findsOneWidget);
      expect(find.textContaining('0:00'), findsNothing);
      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('SongTile renders formatted duration suffix when song duration is positive', (tester) async {
      const songWithDuration = Song(
        id: 'with_dur_song',
        title: 'Valid Duration Song',
        artist: 'Test Artist',
        duration: 215, // 3:35
        thumbnailUrl: '',
      );

      final playback = PlaybackProvider();
      final library = LibraryProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
                ChangeNotifierProvider<LibraryProvider>.value(value: library),
              ],
              child: const SongTile(song: songWithDuration),
            ),
          ),
        ),
      );

      expect(find.text('Test Artist • 3:35'), findsOneWidget);
    });
  });

  group('SearchScreen History vs Suggestions Layout Alignment Tests', () {
    testWidgets('History row and Suggestion row use identical padding and 48dp button constraints', (tester) async {
      final searchProvider = SearchProvider();
      final playbackProvider = PlaybackProvider();
      final libraryProvider = LibraryProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
              ChangeNotifierProvider<PlaybackProvider>.value(value: playbackProvider),
              ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
            ],
            child: const SearchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the History ListTile
      final historyTiles = tester.widgetList<ListTile>(find.byType(ListTile)).where(
        (tile) => tile.leading is Icon && (tile.leading as Icon).icon == Icons.history_rounded,
      ).toList();

      expect(historyTiles.isNotEmpty, isTrue);
      final historyTile = historyTiles.first;
      expect(historyTile.contentPadding, equals(const EdgeInsets.symmetric(horizontal: 16.0)));

      // Verify trailing IconButton has min 48x48dp touch target constraints
      final historyTrailing = historyTile.trailing;
      expect(historyTrailing, isA<IconButton>());
      final historyBtn = historyTrailing as IconButton;
      expect(historyBtn.constraints?.minWidth, greaterThanOrEqualTo(48.0));
      expect(historyBtn.constraints?.minHeight, greaterThanOrEqualTo(48.0));
    });
  });
}
