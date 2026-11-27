import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/models/search_result.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/ui/components/mini_player.dart';
import 'package:melody/ui/components/top_result_play_button.dart';
import 'package:melody/ui/screens/search_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  int toggleCount = 0;
  int playSongCount = 0;
  Song? lastPlayedSong;

  void setPlaybackState({
    Song? song,
    bool isPlaying = false,
    bool isLoading = false,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    _currentSong = song;
    _isPlaying = isPlaying;
    _isLoading = isLoading;
    _position = position;
    _duration = duration;
    notifyListeners();
  }

  void tickPosition(Duration pos) {
    _position = pos;
    notifyListeners();
  }

  @override
  Song? get currentSong => _currentSong;
  @override
  List<Song> get queue => _currentSong != null ? [_currentSong!] : const [];
  @override
  int get currentIndex => _currentSong != null ? 0 : -1;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isLoading => _isLoading;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  MelodyLoopMode get loopMode => MelodyLoopMode.off;
  @override
  bool get isShuffle => false;
  @override
  LyricsData? get lyrics => null;
  @override
  bool get isLoadingLyrics => false;
  @override
  int get activeLyricIndex => -1;

  @override
  Future<void> playSong(Song song, {List<Song>? contextQueue, int? startIndex}) async {
    playSongCount++;
    lastPlayedSong = song;
    _currentSong = song;
    _isPlaying = true;
    _isLoading = false;
    _position = Duration.zero;
    _duration = Duration(seconds: song.duration);
    notifyListeners();
  }

  @override
  Future<void> togglePlayPause() async {
    toggleCount++;
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> playNext() async {}
  @override
  Future<void> playPrevious() async {}
  @override
  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
  }
  @override
  void toggleShuffle() {}
  @override
  void cycleLoopMode() {}
  @override
  void setPlaybackSpeed(double speed) {}
  @override
  void addToQueue(Song song) {}
  @override
  void playNextInQueue(Song song) {}
  @override
  void removeFromQueue(int index) {}
  @override
  void clearQueue() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const topSong = Song(
    id: 'top_song_1',
    title: 'Starboy',
    artist: 'The Weeknd',
    duration: 200,
    thumbnailUrl: '',
  );

  const otherSong = Song(
    id: 'other_song_2',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    duration: 200,
    thumbnailUrl: '',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    DatabaseService.setDatabaseForTesting(db);
    await DatabaseService.init();
  });

  CustomPaint? findProgressRingPaint(WidgetTester tester) {
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    for (final p in paints) {
      if (p.painter is TopResultProgressRingPainter) {
        return p;
      }
    }
    return null;
  }

  Widget buildSearchApp({
    required _FakePlaybackProvider playback,
    required SearchProvider search,
    required LibraryProvider library,
    Color seedColor = const Color(0xFF00897B),
    bool includeMiniPlayer = false,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
        ChangeNotifierProvider<SearchProvider>.value(value: search),
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SearchScreen()),
              if (includeMiniPlayer) const MiniPlayer(),
            ],
          ),
        ),
      ),
    );
  }

  group('TopResultPlayButton Sync & Progress Ring Tests', () {
    testWidgets('Shows pause icon + active ring when matching track is playing, and tapping pauses without restarting', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: topSong,
        isPlaying: true,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      final btnFinder = find.byType(TopResultPlayButton);
      expect(btnFinder, findsOneWidget);
      expect(tester.getSize(btnFinder), equals(const Size(48, 48)));

      // Pause icon shown cleanly
      expect(
        find.descendant(of: btnFinder, matching: find.byIcon(Icons.pause_rounded)),
        findsOneWidget,
      );

      // Ring rendered with exact progress 50/200 = 0.25
      final ringPaint = findProgressRingPaint(tester);
      expect(ringPaint, isNotNull);
      final painter = ringPaint!.painter as TopResultProgressRingPainter;
      expect(painter.progress, closeTo(0.25, 0.001));
      expect(painter.isIndeterminate, isFalse);

      // Tapping button toggles play/pause without calling playSong (must not restart)
      await tester.tap(find.descendant(of: btnFinder, matching: find.byType(IconButton)));
      await tester.pump();

      expect(playback.toggleCount, equals(1));
      expect(playback.playSongCount, equals(0));
      expect(playback.isPlaying, isFalse);
      expect(playback.position, equals(const Duration(seconds: 50)));
    });

    testWidgets('Shows play icon + retained ring when matching track is paused, and tapping resumes instead of restarting', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: topSong,
        isPlaying: false,
        position: const Duration(seconds: 80),
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      final btnFinder = find.byType(TopResultPlayButton);
      expect(
        find.descendant(of: btnFinder, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsOneWidget,
      );

      // Retained ring at paused progress (80/200 = 0.40)
      final ringPaint = findProgressRingPaint(tester);
      expect(ringPaint, isNotNull);
      final painter = ringPaint!.painter as TopResultProgressRingPainter;
      expect(painter.progress, closeTo(0.40, 0.001));

      // Tapping resumes from 80s instead of restarting
      await tester.tap(find.descendant(of: btnFinder, matching: find.byType(IconButton)));
      await tester.pump();

      expect(playback.toggleCount, equals(1));
      expect(playback.playSongCount, equals(0));
      expect(playback.isPlaying, isTrue);
      expect(playback.position, equals(const Duration(seconds: 80)));
      expect(
        find.descendant(of: btnFinder, matching: find.byIcon(Icons.pause_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('Shows play icon + NO ring when a different track is active, and tapping starts topSong', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: otherSong,
        isPlaying: true,
        position: const Duration(seconds: 60),
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      final btnFinder = find.byType(TopResultPlayButton);
      expect(
        find.descendant(of: btnFinder, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsOneWidget,
      );
      expect(findProgressRingPaint(tester), isNull);

      await tester.tap(find.descendant(of: btnFinder, matching: find.byType(IconButton)));
      await tester.pump();

      expect(playback.playSongCount, equals(1));
      expect(playback.lastPlayedSong?.id, equals(topSong.id));
      expect(findProgressRingPaint(tester), isNotNull);
    });

    testWidgets('Ring arc color resolves from Theme.of(context).colorScheme.primary across different themes', (tester) async {
      const amberSeed = Color(0xFFFB8C00);
      final expectedScheme = ColorScheme.fromSeed(seedColor: amberSeed, brightness: Brightness.dark);

      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: topSong,
        isPlaying: true,
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(
        buildSearchApp(
          playback: playback,
          search: search,
          library: library,
          seedColor: amberSeed,
        ),
      );
      await tester.pump();

      final ringPaint = findProgressRingPaint(tester);
      expect(ringPaint, isNotNull);
      final painter = ringPaint!.painter as TopResultProgressRingPainter;
      expect(painter.activeColor, equals(expectedScheme.primary));
      expect(painter.trackColor, equals(expectedScheme.primary.withAlpha(51)));
    });

    testWidgets('Shows indeterminate loading ring when active track is buffering without layout shift', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: topSong,
        isPlaying: false,
        isLoading: true,
        position: Duration.zero,
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      final btnFinder = find.byType(TopResultPlayButton);
      expect(tester.getSize(btnFinder), equals(const Size(48, 48)));

      final loadingPaint = findProgressRingPaint(tester);
      expect(loadingPaint, isNotNull);
      expect((loadingPaint!.painter as TopResultProgressRingPainter).isIndeterminate, isTrue);

      // Transition to loaded playing state cleanly with identical size
      playback.setPlaybackState(
        song: topSong,
        isPlaying: true,
        isLoading: false,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 200),
      );
      await tester.pump();

      expect(tester.getSize(btnFinder), equals(const Size(48, 48)));
      final loadedPaint = findProgressRingPaint(tester);
      expect(loadedPaint, isNotNull);
      final loadedPainter = loadedPaint!.painter as TopResultProgressRingPainter;
      expect(loadedPainter.isIndeterminate, isFalse);
      expect(loadedPainter.progress, closeTo(0.10, 0.001));
    });

    testWidgets('MiniPlayer and TopResultPlayButton stay bidirectionally synced, and position ticks do not rebuild Top Result card', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: topSong,
        isPlaying: true,
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 200),
      );

      int outerBuilds = 0;
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: Brightness.dark);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
            ChangeNotifierProvider<SearchProvider>.value(value: search),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, colorScheme: scheme),
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        outerBuilds++;
                        return const SearchScreen();
                      },
                    ),
                  ),
                  const MiniPlayer(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(outerBuilds, equals(1));

      // Tapping pause on MiniPlayer immediately flips TopResultPlayButton to play_arrow_rounded
      await tester.tap(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byIcon(Icons.pause_rounded),
        ),
      );
      await tester.pump();

      expect(playback.isPlaying, isFalse);
      expect(
        find.descendant(
          of: find.byType(TopResultPlayButton),
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
      );

      // Position ticks update ring progress without rebuilding SearchScreen Top Result card or title widget
      final topTitleBefore = tester.widget<Text>(
        find.descendant(of: find.byType(SearchScreen), matching: find.text('Starboy')),
      );
      playback.tickPosition(const Duration(seconds: 120));
      await tester.pump();
      expect(outerBuilds, equals(1));
      final topTitleAfter = tester.widget<Text>(
        find.descendant(of: find.byType(SearchScreen), matching: find.text('Starboy')),
      );
      expect(identical(topTitleBefore, topTitleAfter), isTrue);
      final updatedPainter = findProgressRingPaint(tester)!.painter as TopResultProgressRingPainter;
      expect(updatedPainter.progress, closeTo(0.60, 0.001));

      // Tapping the Top Result card itself also toggles playback cleanly without restarting
      await tester.tap(find.descendant(of: find.byType(SearchScreen), matching: find.text('Starboy')));
      await tester.pump();
      expect(playback.isPlaying, isTrue);
      expect(playback.playSongCount, equals(0));
      expect(playback.position, equals(const Duration(seconds: 120)));
    });

    testWidgets('Non-Song TopResult (Artist) keeps chevron and does not render TopResultPlayButton', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()
        ..setResultsForTesting(
          const SearchResult(
            topResult: Artist(
              id: 'UC_weeknd',
              name: 'The Weeknd',
              subscribers: '35M subscribers',
              thumbnailUrl: '',
            ),
          ),
        );
      final library = LibraryProvider();

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      expect(find.byType(TopResultPlayButton), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('Tapping Search Top Result card while another song is playing switches playback and activates progress ring', (tester) async {
      final playback = _FakePlaybackProvider();
      final search = SearchProvider()..setResultsForTesting(const SearchResult(topResult: topSong));
      final library = LibraryProvider();

      playback.setPlaybackState(
        song: otherSong,
        isPlaying: true,
        position: const Duration(seconds: 45),
        duration: const Duration(seconds: 200),
      );

      await tester.pumpWidget(buildSearchApp(playback: playback, search: search, library: library));
      await tester.pump();

      expect(findProgressRingPaint(tester), isNull);

      await tester.tap(find.descendant(of: find.byType(SearchScreen), matching: find.text('Starboy')));
      await tester.pump();

      expect(playback.playSongCount, equals(1));
      expect(playback.lastPlayedSong?.id, equals(topSong.id));
      expect(playback.currentSong?.id, equals(topSong.id));
      expect(findProgressRingPaint(tester), isNotNull);
      expect(
        find.descendant(of: find.byType(TopResultPlayButton), matching: find.byIcon(Icons.pause_rounded)),
        findsOneWidget,
      );
    });
  });
}
