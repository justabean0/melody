import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/config/build_flags.dart';
import 'package:melody/main.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/models/search_result.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/providers/theme_provider.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:melody/services/stream_resolver_service.dart';
import 'package:melody/ui/components/album_card.dart';
import 'package:melody/ui/components/mini_player.dart';
import 'package:melody/ui/components/top_result_play_button.dart';
import 'package:melody/ui/screens/home_screen.dart';
import 'package:melody/ui/screens/library_screen.dart';
import 'package:melody/ui/screens/search_screen.dart';
import 'package:melody/ui/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestPlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int playSongCalls = 0;
  int nextCalls = 0;
  List<Song>? lastQueue;

  void setActive({
    Song? song,
    bool isPlaying = false,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    _currentSong = song;
    _isPlaying = isPlaying;
    _position = position;
    _duration = duration;
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
  bool get isLoading => false;
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
  Future<void> playSong(Song song,
      {List<Song>? contextQueue, int? startIndex}) async {
    playSongCalls++;
    lastQueue = contextQueue;
    _currentSong = song;
    _isPlaying = true;
    _duration = Duration(seconds: song.duration);
    notifyListeners();
  }

  @override
  Future<void> togglePlayPause() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> playNext() async {
    nextCalls++;
  }

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

  int batteryRequestCalls = 0;
  int batterySettingsCalls = 0;
  bool batteryUnrestrictedMock = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init') {
          final id = (call.arguments as Map)['id'] as String;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (playerCall) async {
              if (playerCall.method == 'load') {
                return {'duration': 180000000};
              }
              return {};
            },
          );
          return null;
        }
        return {};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.melody.music/playback'),
      (_) async => true,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.melody.music/battery'),
      (call) async {
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return batteryUnrestrictedMock;
        }
        if (call.method == 'requestIgnoreBatteryOptimizations') {
          batteryRequestCalls++;
          batteryUnrestrictedMock = true;
          return true;
        }
        if (call.method == 'openBatteryOptimizationSettings') {
          batterySettingsCalls++;
          return true;
        }
        if (call.method == 'setBackgroundPlaybackEnabled') {
          return true;
        }
        if (call.method == 'getBackgroundPlaybackEnabled') {
          return false;
        }
        return true;
      },
    );
  });

  setUp(() async {
    batteryRequestCalls = 0;
    batterySettingsCalls = 0;
    batteryUnrestrictedMock = false;
    AntiBotService.reset();
    InnerTubeService.clientOverride =
        MockClient((_) async => http.Response('{}', 200));
    StreamResolverService.clientOverride =
        MockClient((_) async => http.Response('{}', 200));
    InnerTubeService.clearQuickPicksCache();
    RecommendationService.clearCache();
    SharedPreferences.setMockInitialValues({
      'melody_auto_check_updates': false,
      'melody_language_onboarding_v2_completed': true,
      'melody_music_languages': ['English'],
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    DatabaseService.setDatabaseForTesting(db);
    await DatabaseService.init();
  });

  tearDown(() {
    InnerTubeService.clientOverride = null;
    StreamResolverService.clientOverride = null;
  });

  Widget wrapPhone({
    required WidgetTester tester,
    required Widget child,
    ThemeProvider? themeProvider,
    LibraryProvider? libraryProvider,
    _TestPlaybackProvider? playbackProvider,
    SearchProvider? searchProvider,
    double textScale = 1.0,
  }) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tp = themeProvider ?? ThemeProvider();
    final lp = libraryProvider ?? LibraryProvider();
    final pp = playbackProvider ?? _TestPlaybackProvider();
    final sp = searchProvider ?? SearchProvider();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: tp),
        ChangeNotifierProvider<LibraryProvider>.value(value: lp),
        ChangeNotifierProvider<PlaybackProvider>.value(value: pp),
        ChangeNotifierProvider<SearchProvider>.value(value: sp),
      ],
      child: MaterialApp(
        theme: tp.lightTheme,
        darkTheme: tp.darkTheme,
        themeMode: ThemeMode.dark,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        ),
        home: child,
      ),
    );
  }

  group('Monthly Listening Time Aggregation & Formatting Tests', () {
    test('formatListeningDuration formats 0m, minutes, and hours cleanly', () {
      expect(DatabaseService.formatListeningDuration(0), equals('0m'));
      expect(DatabaseService.formatListeningDuration(59), equals('0m'));
      expect(DatabaseService.formatListeningDuration(60), equals('1m'));
      expect(DatabaseService.formatListeningDuration(2700), equals('45m'));
      expect(DatabaseService.formatListeningDuration(3600), equals('1h'));
      expect(DatabaseService.formatListeningDuration(129600), equals('36h'));
    });

    test('recordListeningSeconds aggregates current month and trailing daily series', () async {
      final now = DateTime(2026, 11, 20);
      expect(DatabaseService.getMonthlyListeningSeconds(now: now), equals(0));
      expect(
        DatabaseService.getDailyListeningSeries(days: 14, now: now),
        equals(List<int>.filled(14, 0)),
      );

      // Previous month entry should not count toward current month total
      await DatabaseService.recordListeningSeconds(
        3600,
        date: DateTime(2026, 10, 28),
      );
      await DatabaseService.recordListeningSeconds(
        1800,
        date: DateTime(2026, 11, 10),
      );
      await DatabaseService.recordListeningSeconds(
        5400,
        date: DateTime(2026, 11, 20),
      );

      expect(
        DatabaseService.getMonthlyListeningSeconds(now: now),
        equals(7200),
      );
      expect(
        DatabaseService.formatListeningDuration(
          DatabaseService.getMonthlyListeningSeconds(now: now),
        ),
        equals('2h'),
      );

      final series = DatabaseService.getDailyListeningSeries(days: 14, now: now);
      expect(series.length, equals(14));
      expect(series.last, equals(5400));
      expect(series[3], equals(1800)); // Nov 10 is 10 days before Nov 20 (index 13 - 10 = 3)
    });

    test('ignores corrupted JSON and non-date keys in stored listening stats', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 11, 20);

      await prefs.setString('melody_daily_listening_seconds', '{not-valid-json');
      expect(DatabaseService.getMonthlyListeningSeconds(now: now), equals(0));
      expect(
        DatabaseService.getDailyListeningSeries(days: 14, now: now),
        equals(List<int>.filled(14, 0)),
      );

      await prefs.setString(
        'melody_daily_listening_seconds',
        '{"not-a-date": 9999, "2026-02-30": 500, "2026-11-20": 180, "2026-11-19": -50}',
      );
      expect(DatabaseService.getMonthlyListeningSeconds(now: now), equals(180));
      await DatabaseService.recordListeningSeconds(60, date: now);
      expect(DatabaseService.getMonthlyListeningSeconds(now: now), equals(240));
    });

    test('LibraryProvider reacts live to recorded listening seconds', () async {
      final library = LibraryProvider();
      expect(library.monthlyListeningLabel, equals('0m'));

      await DatabaseService.recordListeningSeconds(3600 * 36);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(library.monthlyListeningLabel, equals('36h'));
      library.dispose();
    });
  });

  group('Material 3 ColorScheme & Contrast Verification Tests', () {
    test('All 8 accent swatches verify >= 7:1 primary contrast in Light, Standard Dark, and AMOLED Dark', () {
      for (final accent in ThemeProvider.availableAccents) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final pureBlackModes =
              brightness == Brightness.dark ? [false, true] : [false];
          for (final pureBlack in pureBlackModes) {
            final scheme = ThemeProvider.buildColorScheme(
              seed: accent,
              brightness: brightness,
              pureBlack: pureBlack,
            );
            final primaryRatio = ThemeProvider.contrastRatio(
              scheme.primary,
              scheme.onPrimary,
            );
            expect(
              primaryRatio,
              greaterThanOrEqualTo(7.0),
              reason:
                  'Accent $accent ($brightness, pureBlack=$pureBlack) primary contrast was $primaryRatio',
            );
            if (pureBlack) {
              expect(scheme.surface, equals(Colors.black));
              expect(scheme.surfaceContainerLow, equals(const Color(0xFF131318)));
            }
          }
        }
      }
    });
  });

  group('Home, Search, Library, Settings & Shell Widget Tests', () {
    testWidgets('HomeScreen renders logo.png lockup, sans-serif Melody, mood chips, and Quick Picks', (tester) async {
      const songs = [
        Song(id: 's1', title: 'Alfaaz', artist: 'Hamza Malik', thumbnailUrl: ''),
        Song(id: 's2', title: 'Husn', artist: 'Anuv Jain', thumbnailUrl: ''),
        Song(id: 's3', title: 'Sahiba', artist: 'Aditya Rikhari', thumbnailUrl: ''),
        Song(id: 's4', title: 'Shape of You', artist: 'Ed Sheeran', thumbnailUrl: ''),
        Song(id: 's5', title: 'Blue', artist: 'Yung Kai', thumbnailUrl: ''),
      ];
      await DatabaseService.saveCachedFeed('All:English', songs);

      await tester.pumpWidget(wrapPhone(tester: tester, child: const HomeScreen()));
      await tester.pump();

      expect(find.text('Melody'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Quick Picks'), findsOneWidget);
      expect(find.text('Play all'), findsOneWidget);
      expect(find.text('Alfaaz'), findsOneWidget);
      expect(find.text('Blue'), findsOneWidget);

      // Verify zero overflow under 1.4x font scaling
      await tester.pumpWidget(
        wrapPhone(tester: tester, child: const HomeScreen(), textScale: 1.4),
      );
      await tester.pump();

      // Unmount before 1.5s preWarm timer fires, then drain feed timers cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('SearchScreen omits top Search heading and renders headerless bar + Top Result ring + 80dp Artists', (tester) async {
      const topSong = Song(
        id: 'top_1',
        title: 'Alfaaz',
        artist: 'Hamza Malik',
        duration: 210,
        thumbnailUrl: '',
      );
      const album = Album(
        id: 'alb_1',
        title: 'Love Songs',
        artist: 'Sunset Acoustic',
        thumbnailUrl: '',
      );
      const artist = Artist(
        id: 'art_1',
        name: 'Arijit Singh',
        subscribers: '35M subscribers',
        thumbnailUrl: '',
      );

      final search = SearchProvider()
        ..setResultsForTesting(
          const SearchResult(
            topResult: topSong,
            albums: [album],
            artists: [artist],
          ),
        );

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const SearchScreen(),
          searchProvider: search,
        ),
      );
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SearchBar), findsOneWidget);
      expect(find.text('Top Result'), findsOneWidget);
      expect(find.byType(TopResultPlayButton), findsOneWidget);
      expect(find.text('Albums'), findsWidgets);
      expect(find.text('Artists'), findsWidgets);

      final artistCards = tester.widgetList<MediaCard>(find.byType(MediaCard)).where(
            (card) => card.isCircle,
          );
      expect(artistCards.length, equals(1));
      expect(artistCards.first.size, equals(80));
    });

    testWidgets('LibraryScreen Overview displays Hero Liked card + monthly stats + sparkline + History and Playlists displays round + button', (tester) async {
      await DatabaseService.toggleLike(
        const Song(id: 'fav_1', title: 'Alfaaz', artist: 'Hamza Malik', thumbnailUrl: ''),
      );
      await DatabaseService.addToHistory(
        const Song(id: 'hist_1', title: 'Sajni', artist: 'Arijit Singh', thumbnailUrl: ''),
      );
      await DatabaseService.recordListeningSeconds(3600 * 36);
      await DatabaseService.createPlaylist('Late Night Drive');

      final library = LibraryProvider();
      final playback = _TestPlaybackProvider();

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const LibraryScreen(),
          libraryProvider: library,
          playbackProvider: playback,
        ),
      );
      await tester.pumpAndSettle();

      // LibraryScreen displays Overview, Playlists, and Local tabs
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Favorites'), findsNothing);

      // No + New pill in top header
      expect(find.text('+ New'), findsNothing);
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      expect(find.textContaining('36h'), findsOneWidget);
      expect(find.textContaining('played this month'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Sajni'), findsOneWidget);
      expect(find.text('Recently Liked'), findsNothing);

      // Tapping Liked Songs Play button starts favorites queue sequentially from index 0
      await tester.tap(find.byTooltip('Play Liked Songs'));
      await tester.pump();
      expect(playback.playSongCalls, equals(1));
      expect(playback.lastQueue?.length, equals(1));

      // Switch to Playlists tab -> shows "Your Playlists · 1" and circular + button
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();

      expect(find.text('Your Playlists · 1'), findsOneWidget);
      expect(find.text('Late Night Drive'), findsOneWidget);
      expect(find.byTooltip('New Playlist'), findsOneWidget);

      await tester.tap(find.byTooltip('New Playlist'));
      await tester.pumpAndSettle();
      expect(find.text('New Playlist'), findsOneWidget);
    });

    testWidgets('SettingsScreen bundles headers in cards, preserves real-only rows, and uses Switch for Unrestricted Battery', (tester) async {
      await tester.pumpWidget(wrapPhone(tester: tester, child: const SettingsScreen()));
      await tester.pumpAndSettle();

      // Bundled uppercase card headers
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('AUDIO & PLAYBACK'), findsOneWidget);

      // Audio Normalization stub was removed; wired controls are present with exact defaults
      expect(find.text('Audio Normalization'), findsNothing);
      expect(find.text('Streaming Quality'), findsOneWidget);
      expect(find.text('Highest available (Opus / AAC 160kbps+)'), findsOneWidget);

      final skipSilenceSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Skip Silence'),
      );
      expect(skipSilenceSwitch.value, isFalse);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Skip Silence'));
      await tester.pumpAndSettle();
      expect(DatabaseService.getSkipSilence(), isTrue);
      expect(MelodyAudioService().skipSilence, isTrue);
      expect(MelodyAudioService().player.skipSilenceEnabled, isTrue);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Skip Silence'));
      await tester.pumpAndSettle();
      expect(DatabaseService.getSkipSilence(), isFalse);
      expect(MelodyAudioService().skipSilence, isFalse);
      expect(MelodyAudioService().player.skipSilenceEnabled, isFalse);

      final bgPlaybackSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Background Playback'),
      );
      expect(bgPlaybackSwitch.value, isFalse);

      // Switching Streaming Quality updates subtitle and persists normalized tier
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium').last);
      await tester.pumpAndSettle();
      expect(DatabaseService.getAudioQuality(), equals('Medium'));
      expect(find.text('Balanced (~128kbps)'), findsOneWidget);

      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low').last);
      await tester.pumpAndSettle();
      expect(DatabaseService.getAudioQuality(), equals('Low'));
      expect(find.text('Data saver (~48–64kbps)'), findsOneWidget);

      // Verify Unrestricted Battery is a SwitchListTile (not a chevron ListTile) and triggers BatteryService
      await tester.scrollUntilVisible(
        find.text('Unrestricted Battery'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final batterySwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Unrestricted Battery'),
      );
      expect(batterySwitch.value, isFalse);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Unrestricted Battery'));
      await tester.pumpAndSettle();
      expect(batteryRequestCalls, equals(1));
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Unrestricted Battery'),
            )
            .value,
        isTrue,
      );

      // Tapping OFF opens system battery settings and reflects actual OS state without faking OFF
      await tester.tap(find.widgetWithText(SwitchListTile, 'Unrestricted Battery'));
      await tester.pumpAndSettle();
      expect(batterySettingsCalls, equals(1));
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Unrestricted Battery'),
            )
            .value,
        isTrue,
      );

      // Verify remaining real sections exist and no fake extra settings appear
      for (final section in [
        'CONTENT & RECOMMENDATIONS',
        'LYRICS & SYNC',
        'APP UPDATES',
        'INNERTUBE ENGINE HEALTH',
        if (kIsDiagnosticsEnabled) 'DIAGNOSTICS & DEBUGGING',
        'ABOUT',
      ]) {
        await tester.scrollUntilVisible(
          find.text(section),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(section), findsOneWidget);
      }
    });

    testWidgets('SystemUiOverlayStyle sets dark status bar icons in Light Mode and light icons in Dark Mode', (tester) async {
      final lightStyle = systemUiOverlayStyleForBrightness(Brightness.light);
      expect(lightStyle.statusBarColor, equals(Colors.transparent));
      expect(lightStyle.statusBarIconBrightness, equals(Brightness.dark));
      expect(lightStyle.statusBarBrightness, equals(Brightness.light));
      expect(lightStyle.systemNavigationBarColor, equals(Colors.transparent));
      expect(lightStyle.systemNavigationBarIconBrightness, equals(Brightness.dark));

      final darkStyle = systemUiOverlayStyleForBrightness(Brightness.dark);
      expect(darkStyle.statusBarColor, equals(Colors.transparent));
      expect(darkStyle.statusBarIconBrightness, equals(Brightness.light));
      expect(darkStyle.statusBarBrightness, equals(Brightness.dark));
      expect(darkStyle.systemNavigationBarColor, equals(Colors.transparent));
      expect(darkStyle.systemNavigationBarIconBrightness, equals(Brightness.light));

      final themeProvider = ThemeProvider()..setThemeMode(ThemeMode.light);
      final playback = _TestPlaybackProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider(create: (_) => LibraryProvider()),
            ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
            ChangeNotifierProvider(create: (_) => SearchProvider()),
          ],
          child: const MelodyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final lightRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(lightRegion.value.statusBarIconBrightness, equals(Brightness.dark));
      expect(lightRegion.value.systemNavigationBarIconBrightness, equals(Brightness.dark));

      themeProvider.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      final darkRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(darkRegion.value.statusBarIconBrightness, equals(Brightness.light));
      expect(darkRegion.value.systemNavigationBarIconBrightness, equals(Brightness.light));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    test('Skip Silence and Streaming Quality defaults preserve saved prefs and wire AudioPlayer.setSkipSilenceEnabled', () async {
      expect(DatabaseService.getSkipSilence(), isFalse);
      expect(DatabaseService.getAudioQuality(), equals('High'));

      final audioService = MelodyAudioService.forTesting();
      audioService.init();
      expect(audioService.skipSilence, isFalse);
      expect(audioService.player.skipSilenceEnabled, isFalse);

      await audioService.setSkipSilence(true);
      expect(audioService.skipSilence, isTrue);
      expect(audioService.player.skipSilenceEnabled, isTrue);

      await audioService.setSkipSilence(false);
      expect(audioService.skipSilence, isFalse);
      expect(audioService.player.skipSilenceEnabled, isFalse);

      await DatabaseService.setSkipSilence(true);
      await DatabaseService.setAudioQuality('medium');
      // Re-init must preserve user preference instead of resetting to default
      await DatabaseService.init();
      expect(DatabaseService.getSkipSilence(), isTrue);
      expect(DatabaseService.getAudioQuality(), equals('Medium'));

      audioService.init();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(audioService.skipSilence, isTrue);
      expect(audioService.player.skipSilenceEnabled, isTrue);

      await audioService.player.dispose();
    });

    testWidgets('MainScaffold floating dock renders 4 nav destinations and MiniPlayer with Next + inset progress', (tester) async {
      final playback = _TestPlaybackProvider()
        ..setActive(
          song: const Song(
            id: 'mp_1',
            title: 'Alfaaz',
            artist: 'Hamza Malik, Zain Zohaib',
            duration: 200,
            thumbnailUrl: '',
          ),
          isPlaying: true,
          position: const Duration(seconds: 60),
          duration: const Duration(seconds: 200),
        );

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const MainScaffold(),
          playbackProvider: playback,
        ),
      );
      await tester.pump();

      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Library'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      await tester.tap(find.byTooltip('Next track'));
      await tester.pump();
      expect(playback.nextCalls, equals(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Quick Picks displays at least 4 columns x 4 rows (16+ songs) cleanly and scrolls to column 4', (tester) async {
      final songs = List.generate(
        20,
        (i) => Song(
          id: 'qp_$i',
          title: 'Quick Pick ${i + 1}',
          artist: 'Artist ${i + 1}',
          duration: 200,
          thumbnailUrl: '',
        ),
      );
      await DatabaseService.saveCachedFeed('All:English', songs);

      await tester.pumpWidget(wrapPhone(tester: tester, child: const HomeScreen()));
      await tester.pump();

      final horizScrollFinder = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizScrollFinder, findsOneWidget);

      final scrollView = tester.widget<SingleChildScrollView>(horizScrollFinder);
      final row = scrollView.child as Row;
      expect(row.children.length, greaterThanOrEqualTo(4));
      expect(row.children.length, equals(5));

      for (final colChild in row.children) {
        final sizedBox = colChild as SizedBox;
        final col = sizedBox.child as Column;
        expect(col.children.length, equals(4));
      }

      // Column 0 tracks visible immediately
      expect(find.text('Quick Pick 1'), findsOneWidget);
      expect(find.text('Quick Pick 4'), findsOneWidget);

      // Horizontal scroll reveals columns 3 and 4+ cleanly
      final scrollableState = tester.state<ScrollableState>(
        find.descendant(of: horizScrollFinder, matching: find.byType(Scrollable)),
      );
      scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
      await tester.pump();

      expect(find.text('Quick Pick 17'), findsOneWidget);
      expect(find.text('Quick Pick 20'), findsOneWidget);

      // Font scaling safety (1.4x)
      await tester.pumpWidget(
        wrapPhone(tester: tester, child: const HomeScreen(), textScale: 1.4),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('SettingsScreen removes Pure Black (AMOLED) toggle and ThemeProvider always uses #000000 Dark Mode surface', (tester) async {
      SharedPreferences.setMockInitialValues({
        'melody_pure_black': false,
        'melody_theme_mode': 'dark',
      });
      final prefs = await SharedPreferences.getInstance();
      DatabaseService.setPrefsForTesting(prefs);

      final themeProvider = ThemeProvider();
      expect(themeProvider.darkTheme.colorScheme.surface, equals(const Color(0xFF000000)));
      expect(themeProvider.darkTheme.scaffoldBackgroundColor, equals(const Color(0xFF000000)));
      expect(themeProvider.lightTheme.colorScheme.surface, equals(const Color(0xFFF8F5FA)));

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const SettingsScreen(),
          themeProvider: themeProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pure Black (AMOLED)'), findsNothing);
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Accent Color'), findsOneWidget);
    });

    testWidgets('Settings nav icon uses matched outlined/filled gear pair without Icons.settings_rounded', (tester) async {
      await DatabaseService.saveCachedFeed('All:English', const [
        Song(id: 'nav_1', title: 'Track 1', artist: 'Artist 1', duration: 180, thumbnailUrl: ''),
      ]);
      await tester.pumpWidget(
        wrapPhone(tester: tester, child: const MainScaffold()),
      );
      await tester.pump();

      // Unselected on Home tab -> Icons.settings_outlined
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_rounded), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();

      // Selected on Settings tab -> Icons.settings (matched geometry, not rounded)
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.byIcon(Icons.settings_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('FloatingNavBar hides when soft keyboard opens (viewInsets.bottom > 0) and restores when closed', (tester) async {
      await DatabaseService.saveCachedFeed('All:English', const [
        Song(id: 'kb_seed_1', title: 'Seed Song', artist: 'Artist', duration: 180, thumbnailUrl: ''),
      ]);
      final playback = _TestPlaybackProvider();

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const MainScaffold(),
          playbackProvider: playback,
        ),
      );
      await tester.pump();

      // Switch to Search tab while keyboard is closed
      await tester.tap(find.byTooltip('Search'));
      await tester.pump();

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Library'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      // Simulate keyboard opening
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(find.byTooltip('Home'), findsNothing);
      expect(find.byTooltip('Search'), findsNothing);
      expect(find.byTooltip('Library'), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing);

      // Also verify with MiniPlayer visible that nav bar stays hidden while keyboard is open
      playback.setActive(
        song: const Song(
          id: 'kb_1',
          title: 'Active Song',
          artist: 'Artist',
          duration: 180,
          thumbnailUrl: '',
        ),
      );
      await tester.pump();
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byTooltip('Home'), findsNothing);

      // Close keyboard -> nav bar restores cleanly and tab switching works
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Home'));
      await tester.pump();
      expect(find.text('Quick Picks'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('FloatingBottomDock blocks click-through and long-press-through on Home and Settings in both MiniPlayer visible and hidden states', (tester) async {
      final songs = List.generate(
        30,
        (i) => Song(
          id: 'dock_song_$i',
          title: 'Dock Song ${i + 1}',
          artist: 'Artist ${i + 1}',
          duration: 210,
          thumbnailUrl: '',
        ),
      );
      await DatabaseService.saveCachedFeed('All:English', songs);

      final playback = _TestPlaybackProvider()
        ..setActive(
          song: const Song(
            id: 'now_playing',
            title: 'Now Playing',
            artist: 'Active Artist',
            duration: 210,
            thumbnailUrl: '',
          ),
          isPlaying: true,
        );

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const MainScaffold(),
          playbackProvider: playback,
        ),
      );
      tester.view.padding = const FakeViewPadding(bottom: 24);
      await tester.pump();

      // Scroll Home slightly so "More For You" SongTiles sit both above and behind the bottom dock
      final homeScrollable = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      ).first;
      await tester.drag(homeScrollable, const Offset(0, -180));
      await tester.pump();

      // 1. HOME TAB with MiniPlayer VISIBLE
      final miniRect = tester.getRect(find.byType(MiniPlayer));
      final navDestRect = tester.getRect(find.byTooltip('Home'));
      final gapY = (miniRect.bottom + navDestRect.top) / 2;

      // Tap & long-press side margins, NavBar rounded padding cutout, MiniPlayer/Nav gap, and bottom SafeArea strip
      final homeDockPoints = <Offset>[
        Offset(5, miniRect.center.dy), // left margin beside MiniPlayer
        Offset(407, navDestRect.center.dy), // right margin beside NavBar
        Offset(18, navDestRect.top + 3), // NavBar side padding / rounded cutout
        Offset(206, gapY), // vertical gap between MiniPlayer & NavBar
        const Offset(206, 915 - 8), // bottom SafeArea gesture strip below NavBar
      ];

      for (final point in homeDockPoints) {
        await tester.tapAt(point);
        await tester.pump();
        await tester.longPressAt(point);
        await tester.pump();
      }
      expect(playback.playSongCalls, equals(0));

      // Verify MiniPlayer controls above the barrier remain interactive
      await tester.tap(find.byTooltip('Next track'));
      await tester.pump();
      expect(playback.nextCalls, equals(1));

      // 2. HOME TAB with MiniPlayer HIDDEN
      playback.setActive(song: null);
      await tester.pump();
      expect(find.byType(MiniPlayer), findsNothing);

      final navOnlyRect = tester.getRect(find.byTooltip('Home'));
      final homeNavOnlyPoints = <Offset>[
        Offset(5, navOnlyRect.center.dy), // left side margin beside NavBar
        Offset(407, navOnlyRect.center.dy), // right side margin beside NavBar
        Offset(18, navOnlyRect.top + 3), // rounded corner cutout of NavBar
        const Offset(206, 915 - 8), // bottom SafeArea gesture strip
      ];
      for (final point in homeNavOnlyPoints) {
        await tester.tapAt(point);
        await tester.pump();
        await tester.longPressAt(point);
        await tester.pump();
      }
      expect(playback.playSongCalls, equals(0));

      // Verify normal content ABOVE the dock stays tappable
      final visibleTile = find.ancestor(
        of: find.text('Dock Song 21'),
        matching: find.byType(ListTile),
      );
      final tileRect = tester.getRect(visibleTile);
      expect(tileRect.top, greaterThan(100));
      expect(tileRect.bottom, lessThan(navOnlyRect.top - 18));
      await tester.tap(visibleTile);
      await tester.pump();
      expect(playback.playSongCalls, equals(1));

      // 3. SETTINGS TAB with MiniPlayer VISIBLE (after tapping a song above)
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      expect(find.byType(MiniPlayer), findsOneWidget);

      // Position "Auto-check for updates" SwitchListTile directly behind the dock footprint
      final settingsListView = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(
        find.text('Auto-check for updates'),
        150,
        scrollable: settingsListView,
      );
      await tester.pump();
      final autoUpdateSwitchFinder = find.widgetWithText(
        SwitchListTile,
        'Auto-check for updates',
      );
      final initialAutoUpdateVal =
          tester.widget<SwitchListTile>(autoUpdateSwitchFinder).value;

      final miniRectOnSettings = tester.getRect(find.byType(MiniPlayer));
      final navRectOnSettings = tester.getRect(find.byTooltip('Settings'));
      final settingsGapY = (miniRectOnSettings.bottom + navRectOnSettings.top) / 2;

      final settingsScrollState = tester.state<ScrollableState>(settingsListView);
      final beforeRect = tester.getRect(autoUpdateSwitchFinder);
      settingsScrollState.position.jumpTo(
        (settingsScrollState.position.pixels +
                (beforeRect.center.dy - settingsGapY))
            .clamp(0.0, settingsScrollState.position.maxScrollExtent),
      );
      await tester.pump();

      final switchRect = tester.getRect(autoUpdateSwitchFinder);
      expect(switchRect.bottom, greaterThan(miniRectOnSettings.top));

      // Tap side margins, gap, and bottom strip over Settings
      final settingsDockPoints = <Offset>[
        Offset(5, switchRect.center.dy.clamp(miniRectOnSettings.top + 2, 910.0)),
        Offset(407, switchRect.center.dy.clamp(miniRectOnSettings.top + 2, 910.0)),
        Offset(206, settingsGapY),
        const Offset(206, 915 - 8),
      ];
      for (final point in settingsDockPoints) {
        await tester.tapAt(point);
        await tester.pump();
        await tester.longPressAt(point);
        await tester.pump();
      }
      expect(
        tester.widget<SwitchListTile>(autoUpdateSwitchFinder).value,
        equals(initialAutoUpdateVal),
      );

      // 4. SETTINGS TAB with MiniPlayer HIDDEN
      playback.setActive(song: null);
      await tester.pump();
      expect(find.byType(MiniPlayer), findsNothing);

      final navOnlySettingsRect = tester.getRect(find.byTooltip('Settings'));
      final beforeNavOnlyRect = tester.getRect(autoUpdateSwitchFinder);
      settingsScrollState.position.jumpTo(
        (settingsScrollState.position.pixels +
                (beforeNavOnlyRect.center.dy - navOnlySettingsRect.center.dy))
            .clamp(0.0, settingsScrollState.position.maxScrollExtent),
      );
      await tester.pump();

      final switchRectNavOnly = tester.getRect(autoUpdateSwitchFinder);
      expect(switchRectNavOnly.bottom, greaterThan(navOnlySettingsRect.top));

      for (final point in <Offset>[
        Offset(5, switchRectNavOnly.center.dy.clamp(navOnlySettingsRect.top + 2, 910.0)),
        Offset(407, switchRectNavOnly.center.dy.clamp(navOnlySettingsRect.top + 2, 910.0)),
        const Offset(206, 915 - 8),
      ]) {
        await tester.tapAt(point);
        await tester.pump();
        await tester.longPressAt(point);
        await tester.pump();
      }
      expect(
        tester.widget<SwitchListTile>(autoUpdateSwitchFinder).value,
        equals(initialAutoUpdateVal),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
