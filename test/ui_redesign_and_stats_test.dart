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
import 'package:melody/ui/components/song_tile.dart';
import 'package:melody/ui/components/top_result_play_button.dart';
import 'package:melody/ui/screens/home_screen.dart';
import 'package:melody/ui/screens/library_screen.dart';
import 'package:melody/ui/screens/liked_songs_screen.dart';
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
    Size size = const Size(412, 915),
    bool disableAnimations = false,
  }) {
    tester.view.physicalSize = size;
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
            disableAnimations: disableAnimations,
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
    test('All accent swatches verify >= 7:1 primary contrast in Light, Standard Dark, and AMOLED Dark', () {
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
              final expectedLow = ThemeProvider.isMonochromeSeed(accent)
                  ? const Color(0xFF121214)
                  : const Color(0xFF131318);
              expect(scheme.surfaceContainerLow, equals(expectedLow));
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

    testWidgets('LibraryScreen Overview displays monthly stats + sparkline + History without Liked card, and Playlists pins Favourite Songs above custom playlists', (tester) async {
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

      // LibraryScreen displays Overview, Playlists, and Local tabs without TabBar sliding indicator
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Favorites'), findsNothing);

      // Overview no longer contains Liked Songs / Favourite Songs hero card or + New
      expect(find.text('+ New'), findsNothing);
      expect(find.text('Liked Songs'), findsNothing);
      expect(find.text('Favourite Songs'), findsNothing);
      expect(find.byKey(const Key('library_playtime_hero_card')), findsOneWidget);
      expect(find.text('Playtime'), findsOneWidget);
      expect(find.text('36 hr'), findsOneWidget);
      expect(find.text('0 min'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Sajni'), findsOneWidget);
      expect(find.text('Recently Liked'), findsNothing);

      // Switch to Playlists tab -> shows "Your Playlists · 1", circular + button, and pinned Favourite Songs above custom playlists
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();

      expect(find.text('Your Playlists · 1'), findsOneWidget);
      expect(find.text('Favourite Songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      expect(find.text('Late Night Drive'), findsOneWidget);
      expect(find.byTooltip('New Playlist'), findsOneWidget);
      expect(find.byTooltip('Play Favourite Songs'), findsOneWidget);

      final favCardRect =
          tester.getRect(find.byKey(const Key('library_favourite_songs_card')));
      final customPlaylistRect = tester.getRect(find.text('Late Night Drive'));
      expect(favCardRect.top, lessThan(customPlaylistRect.top));

      // Pinned Favourite Songs card has no delete button
      expect(
        find.descendant(
          of: find.byKey(const Key('library_favourite_songs_card')),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );

      // Tapping Favourite Songs Play button starts favorites queue sequentially from index 0
      await tester.tap(find.byTooltip('Play Favourite Songs'));
      await tester.pump();
      expect(playback.playSongCalls, equals(1));
      expect(playback.lastQueue?.length, equals(1));

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
      await tester.ensureVisible(find.text('Streaming Quality'));
      await tester.pumpAndSettle();
      expect(find.text('Audio Normalization'), findsNothing);
      expect(find.text('Streaming Quality'), findsOneWidget);
      expect(find.text('Highest available (Opus / AAC 160kbps+)'), findsOneWidget);

      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Skip Silence'),
      );
      await tester.pumpAndSettle();
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
      await tester.ensureVisible(find.byKey(const Key('settings_streaming_quality_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_streaming_quality_menu')));
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

    testWidgets('SettingsScreen supports Surface Styles while keeping OLED #000000 default and migrating legacy pureBlack=false', (tester) async {
      // Fresh install defaults to OLED Black (#000000 Dark / crisp #FFFFFF Light)
      SharedPreferences.setMockInitialValues({'melody_theme_mode': 'dark'});
      var prefs = await SharedPreferences.getInstance();
      DatabaseService.setPrefsForTesting(prefs);

      final defaultThemeProvider = ThemeProvider();
      expect(defaultThemeProvider.surfaceStyle, equals(ThemeSurfaceStyle.oledBlack));
      expect(defaultThemeProvider.darkTheme.colorScheme.surface, equals(const Color(0xFF000000)));
      expect(defaultThemeProvider.darkTheme.scaffoldBackgroundColor, equals(const Color(0xFF000000)));
      expect(defaultThemeProvider.lightTheme.colorScheme.surface, equals(const Color(0xFFFFFFFF)));

      // Explicit legacy pure_black=false migrates cleanly to Material Neutral (#121212 Dark)
      SharedPreferences.setMockInitialValues({
        'melody_pure_black': false,
        'melody_theme_mode': 'dark',
      });
      prefs = await SharedPreferences.getInstance();
      DatabaseService.setPrefsForTesting(prefs);

      final themeProvider = ThemeProvider();
      expect(themeProvider.surfaceStyle, equals(ThemeSurfaceStyle.materialNeutral));
      expect(themeProvider.darkTheme.colorScheme.surface, equals(const Color(0xFF121212)));
      expect(themeProvider.lightTheme.colorScheme.surface, equals(const Color(0xFFF7F7F9)));

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          child: const SettingsScreen(),
          themeProvider: themeProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pure Black (AMOLED)'), findsNothing);
      expect(find.text('Theme Presets'), findsOneWidget);
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Surface Style'), findsOneWidget);
      expect(find.text('Accent Color'), findsOneWidget);
      expect(find.text('Adaptive Player Tint'), findsOneWidget);
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

    testWidgets('Library Playlists pins Favourite Songs with 0 custom playlists and tapping opens Favourite Songs screen', (tester) async {
      await DatabaseService.toggleLike(
        const Song(id: 'fav_only_1', title: 'Track A', artist: 'Artist A', thumbnailUrl: ''),
      );
      await DatabaseService.toggleLike(
        const Song(id: 'fav_only_2', title: 'Track B', artist: 'Artist B', thumbnailUrl: ''),
      );

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

      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();

      expect(find.text('Your Playlists'), findsOneWidget);
      expect(find.byTooltip('New Playlist'), findsOneWidget);
      expect(find.text('Favourite Songs'), findsOneWidget);
      expect(find.text('2 songs'), findsOneWidget);
      expect(find.text('No custom playlists yet'), findsOneWidget);
      expect(find.text('Create Playlist'), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_favourite_songs_card')));
      await tester.pumpAndSettle();

      expect(find.byType(LikedSongsScreen), findsOneWidget);
      expect(find.text('Favourite Songs'), findsOneWidget);
      expect(find.text('Track A'), findsOneWidget);
      expect(find.text('Track B'), findsOneWidget);
    });

    testWidgets('Library tabs update active pill in place from Overview to Local without sliding over Playlists', (tester) async {
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

      // No TabBar sliding indicator widget
      expect(find.byType(TabBar), findsNothing);

      final themeColorScheme =
          Theme.of(tester.element(find.byType(LibraryScreen))).colorScheme;

      Color? pillColorFor(String keyName) {
        final animContainer = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(Key(keyName)),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(animContainer.duration, equals(const Duration(milliseconds: 180)));
        expect(animContainer.curve, equals(Curves.easeOutCubic));
        return (animContainer.decoration as BoxDecoration?)?.color;
      }

      expect(pillColorFor('library_tab_overview'), equals(themeColorScheme.primary));
      expect(pillColorFor('library_tab_playlists'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_local'), equals(Colors.transparent));

      // Switch directly from Overview (0) to Local (2) and check intermediate frames
      await tester.tap(find.byKey(const Key('library_tab_local')));
      await tester.pump();
      expect(pillColorFor('library_tab_overview'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_playlists'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_local'), equals(themeColorScheme.primary));

      await tester.pump(const Duration(milliseconds: 80));
      expect(pillColorFor('library_tab_playlists'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_local'), equals(themeColorScheme.primary));

      await tester.pumpAndSettle();
      expect(pillColorFor('library_tab_overview'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_playlists'), equals(Colors.transparent));
      expect(pillColorFor('library_tab_local'), equals(themeColorScheme.primary));
      expect(find.text('Access Local Music'), findsOneWidget);
    });

    testWidgets('FloatingNavBar renders only one active pill and disables Material focus/hover overlays across Search focus lifecycle', (tester) async {
      await DatabaseService.saveCachedFeed('All:English', const [
        Song(id: 'nav_ghost_1', title: 'Track 1', artist: 'Artist 1', duration: 180, thumbnailUrl: ''),
      ]);

      await tester.pumpWidget(
        wrapPhone(tester: tester, child: const MainScaffold()),
      );
      await tester.pump();

      final colorScheme =
          Theme.of(tester.element(find.byType(MainScaffold))).colorScheme;

      // Verify every nav destination InkWell disables focus, hover, highlight, and splash overlays
      for (final label in ['Home', 'Search', 'Library', 'Settings']) {
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: find.byTooltip(label),
            matching: find.byType(InkWell),
          ),
        );
        expect(inkWell.canRequestFocus, isFalse);
        expect(inkWell.splashColor, equals(Colors.transparent));
        expect(inkWell.highlightColor, equals(Colors.transparent));
        expect(inkWell.hoverColor, equals(Colors.transparent));
        expect(inkWell.focusColor, equals(Colors.transparent));
        expect(inkWell.splashFactory, equals(NoSplash.splashFactory));
        expect(inkWell.overlayColor?.resolve({}), equals(Colors.transparent));
      }

      int activePillCount() {
        int count = 0;
        for (final label in ['Home', 'Search', 'Library', 'Settings']) {
          if (find.byKey(Key('nav_active_pill_$label')).evaluate().isNotEmpty) {
            final container = tester.widget<Container>(
              find.byKey(Key('nav_active_pill_$label')),
            );
            final deco = container.decoration as BoxDecoration?;
            if (deco?.color == colorScheme.primaryContainer) {
              count++;
            }
          }
        }
        return count;
      }

      expect(activePillCount(), equals(1));
      expect(find.byKey(const Key('nav_active_pill_Home')), findsOneWidget);

      // Tap Search, focus SearchBar, open/close keyboard, then switch to Library
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(activePillCount(), equals(1));
      expect(find.byKey(const Key('nav_active_pill_Search')), findsOneWidget);

      await tester.tap(find.byType(SearchBar));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      await tester.tap(find.byTooltip('Library'));
      await tester.pumpAndSettle();

      expect(activePillCount(), equals(1));
      expect(find.byKey(const Key('nav_active_pill_Library')), findsOneWidget);
      expect(find.byKey(const Key('nav_active_pill_Search')), findsNothing);
      expect(find.byKey(const Key('nav_active_pill_Home')), findsNothing);
      expect(find.byKey(const Key('nav_active_pill_Settings')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('MiniPlayer enforces >= 20dp gap between text column and play/pause button at 360dp and 1.4x text scale without overflow', (tester) async {
      final playback = _TestPlaybackProvider()
        ..setActive(
          song: const Song(
            id: 'mp_long_1',
            title: 'An Extraordinarily Long Song Title That Must Ellipsize Cleanly',
            artist: 'An Extraordinarily Long Artist Credits String With Multiple Collaborators',
            duration: 245,
            thumbnailUrl: '',
          ),
          isPlaying: true,
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 245),
        );

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          size: const Size(360, 780),
          textScale: 1.4,
          playbackProvider: playback,
          child: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: MiniPlayer(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      final titleFinder = find.text(
        'An Extraordinarily Long Song Title That Must Ellipsize Cleanly',
      );
      final textColumnFinder = find.ancestor(
        of: titleFinder,
        matching: find.byType(Column),
      ).first;
      final pauseButtonFinder = find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byTooltip('Pause'),
      );

      final textRect = tester.getRect(textColumnFinder);
      final pauseRect = tester.getRect(pauseButtonFinder);
      expect(pauseRect.left - textRect.right, greaterThanOrEqualTo(20.0));
    });

    testWidgets('SongTile renders animated equalizer bars while playing, pauses cleanly, respects disableAnimations, scopes rebuilds via Selector, and disposes cleanly', (tester) async {
      const songA = Song(
        id: 'eq_a',
        title: 'First Track',
        artist: 'Artist One',
        duration: 200,
        thumbnailUrl: '',
      );
      const songB = Song(
        id: 'eq_b',
        title: 'Second Track',
        artist: 'Artist Two',
        duration: 210,
        thumbnailUrl: '',
      );

      final playback = _TestPlaybackProvider()
        ..setActive(
          song: songA,
          isPlaying: true,
          duration: const Duration(seconds: 200),
        );
      final library = LibraryProvider();

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          playbackProvider: playback,
          libraryProvider: library,
          child: const Scaffold(
            body: Column(
              children: [
                SongTile(song: songA),
                SongTile(song: songB),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Active playing song shows equalizer bars; inactive song does not
      expect(find.byKey(const Key('playing_equalizer_bars_eq_a')), findsOneWidget);
      expect(find.byKey(const Key('playing_equalizer_bars_eq_b')), findsNothing);

      final eqPaintFinder = find.descendant(
        of: find.byKey(const Key('playing_equalizer_bars_eq_a')),
        matching: find.byType(CustomPaint),
      );
      expect(eqPaintFinder, findsOneWidget);

      // Verify animated progress advances smoothly while playing
      final painterFrame0 = tester.widget<CustomPaint>(eqPaintFinder).painter as dynamic;
      final progress0 = painterFrame0.progress as double;
      await tester.pump(const Duration(milliseconds: 250));
      final painterFrame1 = tester.widget<CustomPaint>(eqPaintFinder).painter as dynamic;
      final progress1 = painterFrame1.progress as double;
      expect(progress1, isNot(equals(progress0)));

      // Position-only updates must NOT rebuild any SongTile ListTile
      final tileABeforeSeek = tester.widget<ListTile>(
        find.ancestor(of: find.text('First Track'), matching: find.byType(ListTile)),
      );
      final tileBBeforeSeek = tester.widget<ListTile>(
        find.ancestor(of: find.text('Second Track'), matching: find.byType(ListTile)),
      );
      await playback.seek(const Duration(seconds: 45));
      await tester.pump();
      expect(
        identical(
          tileABeforeSeek,
          tester.widget<ListTile>(
            find.ancestor(of: find.text('First Track'), matching: find.byType(ListTile)),
          ),
        ),
        isTrue,
      );
      expect(
        identical(
          tileBBeforeSeek,
          tester.widget<ListTile>(
            find.ancestor(of: find.text('Second Track'), matching: find.byType(ListTile)),
          ),
        ),
        isTrue,
      );

      // Play/pause toggle rebuilds ONLY matching SongTile (songA) and never songB
      await playback.togglePlayPause();
      await tester.pumpAndSettle(); // Succeeds cleanly -> ticker stopped on pause!

      expect(
        identical(
          tileABeforeSeek,
          tester.widget<ListTile>(
            find.ancestor(of: find.text('First Track'), matching: find.byType(ListTile)),
          ),
        ),
        isFalse,
      );
      expect(
        identical(
          tileBBeforeSeek,
          tester.widget<ListTile>(
            find.ancestor(of: find.text('Second Track'), matching: find.byType(ListTile)),
          ),
        ),
        isTrue,
      );
      expect(find.byKey(const Key('playing_equalizer_bars_eq_a')), findsOneWidget);

      // Respects MediaQuery.disableAnimations when actively playing (settles cleanly)
      await playback.togglePlayPause();
      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          disableAnimations: true,
          playbackProvider: playback,
          libraryProvider: library,
          child: const Scaffold(
            body: Column(
              children: [
                SongTile(song: songA),
                SongTile(song: songB),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playing_equalizer_bars_eq_a')), findsOneWidget);

      // Switching away or disposing leaves zero ticker leaks
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsScreen replaces DropdownButton with fixed-anchor PopupMenuPosition.under menus for Theme Mode and Streaming Quality', (tester) async {
      final themeProvider = ThemeProvider()..setThemeMode(ThemeMode.system);

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          themeProvider: themeProvider,
          child: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Zero DropdownButton widgets anywhere in SettingsScreen
      expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(DropdownButtonHideUnderline), findsNothing);

      final themeMenu = tester.widget<PopupMenuButton<ThemeMode>>(
        find.byKey(const Key('settings_theme_mode_menu')),
      );
      expect(themeMenu.position, equals(PopupMenuPosition.under));
      expect(themeMenu.offset, equals(const Offset(0, 6)));

      final qualityMenu = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('settings_streaming_quality_menu')),
      );
      expect(qualityMenu.position, equals(PopupMenuPosition.under));
      expect(qualityMenu.offset, equals(const Offset(0, 6)));

      // Measure Theme Mode menu offset below trigger across System -> Light -> Dark (never jumps)
      final systemTriggerRect = tester.getRect(
        find.byKey(const Key('settings_theme_mode_menu')),
      );

      await tester.tap(find.byKey(const Key('settings_theme_mode_menu')));
      await tester.pumpAndSettle();
      final systemMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<ThemeMode>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(systemMenuTop - systemTriggerRect.bottom, closeTo(6.0, 1.0));
      expect(find.byIcon(Icons.check_rounded), findsWidgets);

      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      expect(themeProvider.themeMode, equals(ThemeMode.light));

      final lightTriggerRect = tester.getRect(
        find.byKey(const Key('settings_theme_mode_menu')),
      );
      await tester.tap(find.byKey(const Key('settings_theme_mode_menu')));
      await tester.pumpAndSettle();
      final lightMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<ThemeMode>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(lightMenuTop - lightTriggerRect.bottom, closeTo(6.0, 1.0));

      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(themeProvider.themeMode, equals(ThemeMode.dark));

      final darkTriggerRect = tester.getRect(
        find.byKey(const Key('settings_theme_mode_menu')),
      );
      await tester.tap(find.byKey(const Key('settings_theme_mode_menu')));
      await tester.pumpAndSettle();
      final darkMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<ThemeMode>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(darkMenuTop - darkTriggerRect.bottom, closeTo(6.0, 1.0));

      await tester.tap(find.text('System').last);
      await tester.pumpAndSettle();
      expect(themeProvider.themeMode, equals(ThemeMode.system));

      // Verify Streaming Quality menu stays anchored below trigger for High -> Medium -> Low
      await tester.ensureVisible(
        find.byKey(const Key('settings_streaming_quality_menu')),
      );
      await tester.pumpAndSettle();
      final qualityTriggerRect = tester.getRect(
        find.byKey(const Key('settings_streaming_quality_menu')),
      );

      await tester.tap(find.byKey(const Key('settings_streaming_quality_menu')));
      await tester.pumpAndSettle();
      final highMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<String>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(highMenuTop - qualityTriggerRect.bottom, closeTo(6.0, 1.0));

      await tester.tap(find.text('Medium').last);
      await tester.pumpAndSettle();
      expect(DatabaseService.getAudioQuality(), equals('Medium'));

      final mediumTriggerRect = tester.getRect(
        find.byKey(const Key('settings_streaming_quality_menu')),
      );
      await tester.tap(find.byKey(const Key('settings_streaming_quality_menu')));
      await tester.pumpAndSettle();
      final mediumMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<String>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(mediumMenuTop - mediumTriggerRect.bottom, closeTo(6.0, 1.0));

      await tester.tap(find.text('Low').last);
      await tester.pumpAndSettle();
      expect(DatabaseService.getAudioQuality(), equals('Low'));

      final lowTriggerRect = tester.getRect(
        find.byKey(const Key('settings_streaming_quality_menu')),
      );
      await tester.tap(find.byKey(const Key('settings_streaming_quality_menu')));
      await tester.pumpAndSettle();
      final lowMenuTop = tester.getRect(
        find.ancestor(
          of: find.byType(PopupMenuItem<String>).first,
          matching: find.byType(Material),
        ).first,
      ).top;
      expect(lowMenuTop - lowTriggerRect.bottom, closeTo(6.0, 1.0));

      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();
      expect(DatabaseService.getAudioQuality(), equals('High'));
    });

    testWidgets('Playlist tracks support swipe-left-to-reveal delete without auto-delete, single open row coordination, and Remove from playlist menu fallback', (tester) async {
      await DatabaseService.createPlaylist('Roadtrip Mix');
      final playlistId = DatabaseService.getPlaylists().first.id;
      const s1 = Song(id: 'pl_s1', title: 'Track Alpha', artist: 'Artist 1', duration: 190, thumbnailUrl: '');
      const s2 = Song(id: 'pl_s2', title: 'Track Beta', artist: 'Artist 2', duration: 205, thumbnailUrl: '');
      const s3 = Song(id: 'pl_s3', title: 'Track Gamma', artist: 'Artist 3', duration: 215, thumbnailUrl: '');
      await DatabaseService.addSongToPlaylist(playlistId, s1);
      await DatabaseService.addSongToPlaylist(playlistId, s2);
      await DatabaseService.addSongToPlaylist(playlistId, s3);

      final library = LibraryProvider();
      final playback = _TestPlaybackProvider();

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          libraryProvider: library,
          playbackProvider: playback,
          child: const LibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roadtrip Mix'));
      await tester.pumpAndSettle();

      expect(find.text('3 tracks'), findsOneWidget);
      expect(find.text('Track Alpha'), findsOneWidget);
      expect(find.text('Track Beta'), findsOneWidget);
      expect(find.text('Track Gamma'), findsOneWidget);

      // 1. Swiping left on Track Alpha reveals delete button without deleting track
      await tester.drag(find.text('Track Alpha'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.text('Track Alpha'), findsOneWidget);
      expect(find.byKey(const Key('swipe_delete_button_pl_s1')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('swipe_delete_button_pl_s1'))).width,
        greaterThanOrEqualTo(48.0),
      );
      expect(
        tester.getSize(find.byKey(const Key('swipe_delete_button_pl_s1'))).height,
        greaterThanOrEqualTo(48.0),
      );

      // 2. Swiping left on Track Beta closes Track Alpha's delete button (only 1 open at a time)
      await tester.drag(find.text('Track Beta'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swipe_delete_button_pl_s1')), findsNothing);
      expect(find.byKey(const Key('swipe_delete_button_pl_s2')), findsOneWidget);

      // 3. Tapping open Track Beta row closes reveal without triggering playback
      final betaSwipeRow = find.byKey(ValueKey('playlist_swipe_${playlistId}_pl_s2'));
      await tester.tapAt(
        tester.getTopLeft(betaSwipeRow) + const Offset(60, 24),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swipe_delete_button_pl_s2')), findsNothing);
      expect(playback.playSongCalls, equals(0));

      // 4. Swipe left then swipe right closes cleanly
      await tester.drag(find.text('Track Beta'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swipe_delete_button_pl_s2')), findsOneWidget);
      await tester.drag(betaSwipeRow, const Offset(80, 0), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swipe_delete_button_pl_s2')), findsNothing);

      // 5. Swipe left on Track Beta and tap revealed delete button removes it cleanly
      await tester.drag(find.text('Track Beta'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('swipe_delete_button_pl_s2')));
      await tester.pumpAndSettle();

      expect(find.text('Track Beta'), findsNothing);
      expect(find.text('2 tracks'), findsOneWidget);
      expect(
        library.playlists.first.songs.map((s) => s.id).toList(),
        equals(['pl_s1', 'pl_s3']),
      );
      expect(
        DatabaseService.getPlaylists().first.songs.map((s) => s.id).toList(),
        equals(['pl_s1', 'pl_s3']),
      );

      // 6. 3-dot overflow menu "Remove from playlist" removes Track Gamma cleanly
      final gammaRow = find.ancestor(
        of: find.text('Track Gamma'),
        matching: find.byType(SongTile),
      );
      await tester.tap(
        find.descendant(
          of: gammaRow,
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Track Gamma'), findsNothing);
      expect(find.text('1 track'), findsOneWidget);
      expect(
        library.playlists.first.songs.map((s) => s.id).toList(),
        equals(['pl_s1']),
      );
    });

    testWidgets('LikedSongsScreen supports swipe-left-to-reveal removal from Favourite Songs', (tester) async {
      await DatabaseService.toggleLike(
        const Song(id: 'fav_sw_1', title: 'Heart One', artist: 'Artist', thumbnailUrl: ''),
      );
      await DatabaseService.toggleLike(
        const Song(id: 'fav_sw_2', title: 'Heart Two', artist: 'Artist', thumbnailUrl: ''),
      );

      final library = LibraryProvider();
      final playback = _TestPlaybackProvider();

      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          libraryProvider: library,
          playbackProvider: playback,
          child: const LikedSongsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.text('Heart Two'), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.text('Heart Two'), findsOneWidget);
      expect(find.byKey(const Key('swipe_delete_button_fav_sw_2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('swipe_delete_button_fav_sw_2')));
      await tester.pumpAndSettle();

      expect(find.text('Heart Two'), findsNothing);
      expect(find.text('1 song'), findsOneWidget);
      expect(library.likedSongs.map((s) => s.id).toList(), equals(['fav_sw_1']));
    });
  });

  group('Playtime Hero Card, Bar Chart & Play Logs Tests', () {
    test('formatSplitPlaytime and formatCompactPlaytime format <1h and >=1h accurately', () {
      expect(DatabaseService.formatSplitPlaytime(0).summary, equals('0 min / 0 sec'));
      expect(DatabaseService.formatSplitPlaytime(3599).summary, equals('59 min / 59 sec'));
      expect(DatabaseService.formatSplitPlaytime(3600).summary, equals('1 hr / 0 min'));
      expect(DatabaseService.formatSplitPlaytime(8100).summary, equals('2 hr / 15 min'));

      expect(DatabaseService.formatCompactPlaytime(0), equals('0s'));
      expect(DatabaseService.formatCompactPlaytime(18), equals('18s'));
      expect(DatabaseService.formatCompactPlaytime(872), equals('14m 32s'));
      expect(DatabaseService.formatCompactPlaytime(8100), equals('2h 15m'));
    });

    test('Daily (7-day), Monthly (6-month), and SQLite listening_logs upgrade & session upsert work accurately', () async {
      // Simulate upgrading an existing schema version 1 SQLite database lacking listening_logs
      final legacyDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await legacyDb.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      await legacyDb.insert('app_settings', {
        'key': 'background_playback_enabled',
        'value': '1',
      });
      await legacyDb.execute('''
        CREATE TABLE last_playback_session (
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

      DatabaseService.setDatabaseForTesting(legacyDb);
      await DatabaseService.init();

      // Legacy data preserved and listening_logs table exists
      expect(await DatabaseService.getBackgroundPlaybackEnabled(), isTrue);

      final now = DateTime(2026, 11, 27, 20, 30);
      const track1 = Song(
        id: 'log_t1',
        title: 'Midnight Echoes',
        artist: 'Luna',
        duration: 240,
        thumbnailUrl: '',
      );
      const track2 = Song(
        id: 'log_t2',
        title: 'Sunrise Horizon',
        artist: 'Sol',
        duration: 180,
        thumbnailUrl: '',
      );

      // Record across previous months & days (exact second retention > 60 days)
      await DatabaseService.recordListeningSeconds(
        3600,
        date: DateTime(2026, 6, 15, 12, 0),
      );
      await DatabaseService.recordListeningSeconds(
        900,
        date: DateTime(2026, 11, 25, 18, 0),
        song: track1,
        sessionKey: 'sess_prev_day',
      );
      await DatabaseService.recordListeningSeconds(
        18,
        date: now,
        song: track2,
        sessionKey: 'sess_today_1',
      );
      // Same session updates cumulative duration instead of duplicating row
      await DatabaseService.recordListeningSeconds(
        14,
        date: now,
        song: track2,
        sessionKey: 'sess_today_1',
      );

      expect(DatabaseService.getTodayListeningSeconds(now: now), equals(32));
      expect(DatabaseService.getMonthlyListeningSeconds(now: now), equals(932));

      final dailyBuckets =
          DatabaseService.getDailyPlaytimeBuckets(days: 7, now: now);
      expect(dailyBuckets.length, equals(7));
      expect(dailyBuckets.last.label, equals('Fri'));
      expect(dailyBuckets.last.seconds, equals(32));
      expect(dailyBuckets[4].label, equals('Wed'));
      expect(dailyBuckets[4].seconds, equals(900));

      final monthlyBuckets =
          DatabaseService.getMonthlyPlaytimeBuckets(months: 6, now: now);
      expect(monthlyBuckets.length, equals(6));
      expect(monthlyBuckets.first.label, equals('Jun'));
      expect(monthlyBuckets.first.seconds, equals(3600));
      expect(monthlyBuckets.last.label, equals('Nov'));
      expect(monthlyBuckets.last.seconds, equals(932));

      final logs = await DatabaseService.loadRecentPlayLogs();
      expect(logs.length, equals(2));
      expect(logs.first.songId, equals('log_t2'));
      expect(logs.first.durationSeconds, equals(32));
      expect(logs.last.songId, equals('log_t1'));
      expect(logs.last.durationSeconds, equals(900));

      await legacyDb.close();
      DatabaseService.setDatabaseForTesting(null);
    });

    testWidgets('Playtime Hero Card renders split counter (<1h and >=1h), expands Daily/Monthly bar charts, inspects tapped bars, displays play logs, and never overflows at 360dp / 1.4x', (tester) async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      const song = Song(
        id: 'pt_song_1',
        title: 'Starlight Symphony',
        artist: 'Aurora Ensemble',
        duration: 210,
        thumbnailUrl: '',
      );

      await tester.runAsync(() async {
        await DatabaseService.recordListeningSeconds(
          45,
          date: yesterday,
        );
        await DatabaseService.recordListeningSeconds(
          872, // 14 min 32 sec
          date: now,
          song: song,
          sessionKey: 'pt_sess_1',
        );
      });

      final library = LibraryProvider();
      final playback = _TestPlaybackProvider();

      // Render on narrow 360dp screen at 1.4x text scale
      await tester.pumpWidget(
        wrapPhone(
          tester: tester,
          size: const Size(360, 780),
          textScale: 1.4,
          libraryProvider: library,
          playbackProvider: playback,
          child: const LibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Collapsed split layout: Playtime, Daily badge, trend graph, 14 min / 32 sec
      expect(find.byKey(const Key('library_playtime_hero_card')), findsOneWidget);
      expect(find.byKey(const Key('playtime_trend_graph')), findsOneWidget);
      expect(find.text('Playtime'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('14 min'), findsOneWidget);
      expect(find.text('32 sec'), findsOneWidget);
      expect(find.text('Recent Play Logs'), findsNothing);

      // Tap card to expand -> shows Daily/Monthly chips, 7 daily bars, and play logs
      await tester.tap(find.byKey(const Key('playtime_hero_toggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('playtime_scope_daily')), findsOneWidget);
      expect(find.byKey(const Key('playtime_scope_monthly')), findsOneWidget);
      expect(find.text('Recent Play Logs'), findsOneWidget);
      expect(find.text('Starlight Symphony'), findsOneWidget);
      expect(find.text('14m 32s'), findsOneWidget);

      // Tap yesterday's bar to inspect its exact duration
      final yesterdayKey =
          '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      await tester.tap(find.byKey(Key('playtime_bar_$yesterdayKey')));
      await tester.pumpAndSettle();
      expect(find.text('0 min'), findsOneWidget);
      expect(find.text('45 sec'), findsOneWidget);
      expect(find.textContaining('45s'), findsWidgets);

      // Switch to Monthly scope -> updates to 6 month bars and This Month total
      await tester.tap(find.byKey(const Key('playtime_scope_monthly')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('Last 6 months'), findsOneWidget);

      // Flushing more seconds crosses >= 3600s -> automatically switches to hr / min
      await tester.runAsync(
        () => DatabaseService.recordListeningSeconds(3600, date: now),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 hr'), findsOneWidget);

      // Verify Light Mode renders cleanly with zero overflows as well
      final tp = ThemeProvider()..setThemeMode(ThemeMode.light);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: tp),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
            ChangeNotifierProvider<SearchProvider>.value(value: SearchProvider()),
          ],
          child: MaterialApp(
            theme: tp.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 780),
                textScaler: TextScaler.linear(1.4),
              ),
              child: const LibraryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
