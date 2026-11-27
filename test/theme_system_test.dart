import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody/main.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/providers/theme_provider.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/download_service.dart';
import 'package:melody/ui/screens/player_screen.dart';
import 'package:melody/ui/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThemeTestPlaybackProvider extends ChangeNotifier
    implements PlaybackProvider {
  Song? _currentSong;
  List<Song> _queue = const [];

  void seed(Song song) {
    _currentSong = song;
    _queue = [song];
    notifyListeners();
  }

  @override
  Song? get currentSong => _currentSong;
  @override
  List<Song> get queue => _queue;
  @override
  int get currentIndex => _currentSong == null ? -1 : 0;
  @override
  bool get isPlaying => false;
  @override
  bool get isLoading => false;
  @override
  Duration get position => const Duration(seconds: 25);
  @override
  Duration get duration => const Duration(seconds: 180);
  @override
  bool get isShuffle => false;
  @override
  MelodyLoopMode get loopMode => MelodyLoopMode.off;
  @override
  LyricsData? get lyrics => null;
  @override
  bool get isLoadingLyrics => false;
  @override
  int get activeLyricIndex => -1;

  @override
  Future<void> playSong(
    Song song, {
    List<Song>? contextQueue,
    int? startIndex,
  }) async =>
      seed(song);
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> playNext() async {}
  @override
  Future<void> playPrevious() async {}
  @override
  Future<void> seek(Duration pos) async {}
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    DatabaseService.setPrefsForTesting(prefs);
    DatabaseService.setDatabaseForTesting(null);
    await DatabaseService.markLanguageOnboardingCompleted();
  });

  Widget wrapThemed({
    required WidgetTester tester,
    required Widget child,
    ThemeProvider? themeProvider,
    PlaybackProvider? playbackProvider,
    LibraryProvider? libraryProvider,
    Size size = const Size(412, 915),
    double textScale = 1.0,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tp = themeProvider ?? ThemeProvider();
    final pp = playbackProvider ?? _ThemeTestPlaybackProvider();
    final lp = libraryProvider ?? LibraryProvider();
    final sp = SearchProvider();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: tp),
        ChangeNotifierProvider<PlaybackProvider>.value(value: pp),
        ChangeNotifierProvider<LibraryProvider>.value(value: lp),
        ChangeNotifierProvider<SearchProvider>.value(value: sp),
      ],
      child: MaterialApp(
        themeMode: tp.themeMode,
        theme: tp.lightTheme,
        darkTheme: tp.darkTheme,
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

  group('ThemeProvider Persistence, Migration & Palette Matrix Tests', () {
    test('Persists defaults, migrates legacy keys cleanly, and restores surface style & tint', () async {
      // Fresh install defaults
      var tp = ThemeProvider();
      expect(tp.themeMode, equals(ThemeMode.system));
      expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.oledBlack));
      expect(ThemeProvider.argb32(tp.accentColor), equals(0xFF8E24AA));
      expect(tp.adaptivePlayerTint, isFalse);
      expect(tp.activePreset, isNull);

      // Existing install without surface style migrates to OLED Black & matches curated preset
      SharedPreferences.setMockInitialValues({
        'melody_theme_mode': 'dark',
        'melody_accent_color': 0xFFE53935,
      });
      DatabaseService.setPrefsForTesting(await SharedPreferences.getInstance());
      tp = ThemeProvider();
      expect(tp.themeMode, equals(ThemeMode.dark));
      expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.oledBlack));
      expect(tp.activePreset?.id, equals('oled_crimson'));

      // Explicit legacy pure_black=false migrates to Material Neutral
      SharedPreferences.setMockInitialValues({
        'melody_theme_mode': 'dark',
        'melody_pure_black': false,
        'melody_accent_color': 0xFF607D8B,
      });
      DatabaseService.setPrefsForTesting(await SharedPreferences.getInstance());
      tp = ThemeProvider();
      expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.materialNeutral));
      expect(tp.activePreset?.id, equals('nordic_slate'));

      // Preset application & manual tweak clearing activePreset
      final indigoPreset = ThemeProvider.curatedPresets
          .firstWhere((p) => p.id == 'midnight_indigo');
      tp.applyPreset(indigoPreset);
      expect(tp.activePreset?.id, equals('midnight_indigo'));
      expect(tp.themeMode, equals(ThemeMode.dark));
      expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.tinted));

      tp.setSurfaceStyle(ThemeSurfaceStyle.highContrast);
      tp.setAdaptivePlayerTint(true);

      // Recreating ThemeProvider restores persisted style + tint flag
      final restored = ThemeProvider();
      expect(restored.surfaceStyle, equals(ThemeSurfaceStyle.highContrast));
      expect(restored.adaptivePlayerTint, isTrue);
      expect(restored.activePreset, isNull);
    });

    test('All 16 curated accents x 4 surface styles x Light/Dark satisfy WCAG contrast invariants', () {
      expect(ThemeProvider.accentPresets.length, equals(16));
      final names = ThemeProvider.accentPresets.map((a) => a.name).toSet();
      expect(names.length, equals(16));
      expect(
        names,
        containsAll([
          'Crimson Red',
          'Rose Coral',
          'Sunset Orange',
          'Amber Gold',
          'Warm Sand',
          'Lime Sage',
          'Emerald',
          'Teal',
          'Ice Cyan',
          'Sky Blue',
          'Cobalt',
          'Indigo',
          'Royal Purple',
          'Orchid Magenta',
          'Slate Steel',
          'Monochrome',
        ]),
      );

      for (final preset in ThemeProvider.accentPresets) {
        for (final style in ThemeSurfaceStyle.values) {
          for (final brightness in [Brightness.light, Brightness.dark]) {
            final scheme = ThemeProvider.buildColorScheme(
              seed: preset.color,
              brightness: brightness,
              surfaceStyle: style,
            );
            final minPrimary = style == ThemeSurfaceStyle.highContrast ? 8.5 : 7.0;
            final minVariantInk =
                style == ThemeSurfaceStyle.highContrast ? 7.0 : 4.5;

            expect(
              ThemeProvider.contrastRatio(scheme.primary, scheme.onPrimary),
              greaterThanOrEqualTo(minPrimary),
              reason: '${preset.name} ($style, $brightness) primary contrast',
            );
            expect(
              ThemeProvider.contrastRatio(
                scheme.onPrimaryContainer,
                scheme.primaryContainer,
              ),
              greaterThanOrEqualTo(7.0),
              reason: '${preset.name} ($style, $brightness) container contrast',
            );
            expect(
              ThemeProvider.contrastRatio(scheme.onSurface, scheme.surface),
              greaterThanOrEqualTo(10.0),
              reason: '${preset.name} ($style, $brightness) surface ink contrast',
            );
            expect(
              ThemeProvider.contrastRatio(
                scheme.onSurfaceVariant,
                scheme.surface,
              ),
              greaterThanOrEqualTo(minVariantInk),
              reason: '${preset.name} ($style, $brightness) variant ink contrast',
            );

            if (brightness == Brightness.dark &&
                style == ThemeSurfaceStyle.oledBlack) {
              expect(scheme.surface, equals(const Color(0xFF000000)));
            }
            if (brightness == Brightness.light &&
                style == ThemeSurfaceStyle.oledBlack) {
              expect(scheme.surface, equals(const Color(0xFFFFFFFF)));
            }
            if (brightness == Brightness.dark &&
                style == ThemeSurfaceStyle.materialNeutral) {
              expect(scheme.surface, equals(const Color(0xFF121212)));
            }
            if (brightness == Brightness.light &&
                style == ThemeSurfaceStyle.materialNeutral) {
              expect(scheme.surface, equals(const Color(0xFFF7F7F9)));
            }
          }
        }
      }
    });

    test('Adaptive Player Tint caches up to 64 entries with LRU eviction and falls back safely on error', () async {
      var loaderCalls = 0;
      var shouldThrow = false;
      final tp = ThemeProvider(
        adaptiveSchemeLoader: (provider, brightness) async {
          loaderCalls++;
          if (shouldThrow) {
            throw Exception('Offline image failure');
          }
          return ColorScheme.fromSeed(
            seedColor: const Color(0xFF00ACC1),
            brightness: brightness,
          );
        },
      );

      final baseDark = ThemeProvider.buildColorScheme(
        seed: const Color(0xFFE53935),
        brightness: Brightness.dark,
        surfaceStyle: ThemeSurfaceStyle.oledBlack,
      );

      // Default OFF performs zero loads and returns null
      expect(
        await tp.resolveAdaptivePlayerScheme(
          thumbnailUrl: 'https://lh3.googleusercontent.com/track_a=w120-h120',
          baseScheme: baseDark,
        ),
        isNull,
      );
      expect(loaderCalls, equals(0));

      tp.setAdaptivePlayerTint(true);

      // Empty or non-HTTP URLs fall back cleanly without invoking loader
      expect(
        await tp.resolveAdaptivePlayerScheme(
          thumbnailUrl: '',
          baseScheme: baseDark,
        ),
        isNull,
      );
      expect(
        await tp.resolveAdaptivePlayerScheme(
          thumbnailUrl: 'content://media/external/audio/12',
          baseScheme: baseDark,
        ),
        isNull,
      );
      expect(loaderCalls, equals(0));

      // Valid URL loads once and serves subsequent hits from bounded cache
      final tinted1 = await tp.resolveAdaptivePlayerScheme(
        thumbnailUrl: 'https://lh3.googleusercontent.com/track_a=w120-h120',
        baseScheme: baseDark,
      );
      expect(tinted1, isNotNull);
      expect(tinted1!.surface, isNot(equals(baseDark.surface)));
      expect(loaderCalls, equals(1));
      expect(tp.adaptiveCacheLength, equals(1));

      final tinted2 = await tp.resolveAdaptivePlayerScheme(
        thumbnailUrl: 'https://lh3.googleusercontent.com/track_a=w120-h120',
        baseScheme: baseDark,
      );
      expect(tinted2!.surface, equals(tinted1.surface));
      expect(loaderCalls, equals(1));

      // Offline / decoding error falls back to null without caching error
      shouldThrow = true;
      final failed = await tp.resolveAdaptivePlayerScheme(
        thumbnailUrl: 'https://lh3.googleusercontent.com/offline_track=w120-h120',
        baseScheme: baseDark,
      );
      expect(failed, isNull);
      shouldThrow = false;

      // Fill beyond 64 entries and verify LRU bound
      for (int i = 0; i < 70; i++) {
        await tp.resolveAdaptivePlayerScheme(
          thumbnailUrl: 'https://lh3.googleusercontent.com/art_$i=w120-h120',
          baseScheme: baseDark,
        );
      }
      expect(tp.adaptiveCacheLength, equals(ThemeProvider.maxAdaptiveCacheEntries));
    });
  });

  group('SettingsScreen Theme Controls & Curated Presets Widget Tests', () {
    testWidgets(
      'Renders 8 presets, Surface Style selector, 16 swatches with 48dp targets at 360dp, and high-contrast checkmarks',
      (tester) async {
        final tp = ThemeProvider();
        await tester.pumpWidget(
          wrapThemed(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.3,
            themeProvider: tp,
            child: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(ThemeProvider.curatedPresets.length, equals(8));
        expect(find.byKey(const Key('theme_preset_oled_crimson')), findsOneWidget);

        // Tap curated dark tinted preset -> updates mode, style, accent
        final indigoFinder = find.byKey(const Key('theme_preset_midnight_indigo'));
        await tester.scrollUntilVisible(
          indigoFinder,
          120,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        );
        await tester.tap(indigoFinder);
        await tester.pumpAndSettle();
        expect(tp.themeMode, equals(ThemeMode.dark));
        expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.tinted));
        expect(ThemeProvider.argb32(tp.accentColor), equals(0xFF3949AB));

        // Scroll presets to Soft Paper -> switches to Light Tinted Warm Sand
        final paperFinder = find.byKey(const Key('theme_preset_soft_paper'));
        await tester.scrollUntilVisible(
          paperFinder,
          160,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        );
        await tester.tap(paperFinder);
        await tester.pumpAndSettle();
        expect(tp.themeMode, equals(ThemeMode.light));
        expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.tinted));
        expect(ThemeProvider.argb32(tp.accentColor), equals(0xFFC89B6E));

        // Every one of 16 accent swatches uses >= 48x48dp touch target without overflow
        await tester.ensureVisible(
          find.byKey(const Key('accent_swatch_Warm Sand')),
        );
        await tester.pumpAndSettle();
        for (final accent in ThemeProvider.accentPresets) {
          final swatch = find.byKey(Key('accent_swatch_${accent.name}'));
          expect(swatch, findsOneWidget);
          final size = tester.getSize(swatch);
          expect(size.width, greaterThanOrEqualTo(48.0));
          expect(size.height, greaterThanOrEqualTo(48.0));
        }

        // Light accent checkmarks choose higher-contrast ink (black on Warm Sand / Lime Sage)
        await tester.tap(find.byKey(const Key('accent_swatch_Lime Sage')));
        await tester.pumpAndSettle();
        final sageCheck = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('accent_swatch_Lime Sage')),
            matching: find.byIcon(Icons.check_rounded),
          ),
        );
        expect(
          sageCheck.color,
          equals(ThemeProvider.bestContrastInk(const Color(0xFF7CB342))),
        );

        // Surface Style selector switches to High Contrast cleanly
        await tester.ensureVisible(
          find.byKey(const Key('settings_surface_style_menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings_surface_style_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('High Contrast').last);
        await tester.pumpAndSettle();
        expect(tp.surfaceStyle, equals(ThemeSurfaceStyle.highContrast));

        // Adaptive Player Tint toggle switches cleanly
        final tintSwitch = find.byKey(
          const Key('settings_adaptive_player_tint_switch'),
        );
        await tester.ensureVisible(tintSwitch);
        await tester.pumpAndSettle();
        await tester.tap(tintSwitch);
        await tester.pumpAndSettle();
        expect(tp.adaptivePlayerTint, isTrue);
      },
    );
  });

  group('PlayerScreen Adaptive Tint & Cross-App Monochrome Cohesion Tests', () {
    testWidgets(
      'PlayerScreen applies album-art surface tint when enabled and restores active theme when disabled',
      (tester) async {
        const song = Song(
          id: 'tint_1',
          title: 'Ocean Waves',
          artist: 'Prateek Kuhad',
          duration: 210,
          thumbnailUrl: 'https://lh3.googleusercontent.com/ocean=w544-h544',
        );
        final tp = ThemeProvider(
          adaptiveSchemeLoader: (provider, brightness) async =>
              ColorScheme.fromSeed(
            seedColor: const Color(0xFF00ACC1),
            brightness: brightness,
          ),
        )
          ..setThemeMode(ThemeMode.dark)
          ..setSurfaceStyle(ThemeSurfaceStyle.oledBlack)
          ..setAdaptivePlayerTint(true);

        final pp = _ThemeTestPlaybackProvider()..seed(song);

        await tester.pumpWidget(
          wrapThemed(
            tester: tester,
            themeProvider: tp,
            playbackProvider: pp,
            child: PlayerScreen(downloadService: DownloadService.forTesting()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Adaptive Player Tint shifts PlayerScreen Scaffold surface away from pure black
        final tintedScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        final tintedBg =
            Theme.of(tester.element(find.byType(TabBarView))).colorScheme.surface;
        expect(tintedBg, isNot(equals(const Color(0xFF000000))));
        expect(tintedScaffold, isNotNull);

        // Disabling Adaptive Player Tint immediately restores pure #000000 active theme surface
        tp.setAdaptivePlayerTint(false);
        await tester.pumpAndSettle();
        final restoredBg =
            Theme.of(tester.element(find.byType(TabBarView))).colorScheme.surface;
        expect(restoredBg, equals(const Color(0xFF000000)));
      },
    );

    testWidgets(
      'Monochrome Ink High Contrast renders shell dock, MiniPlayer, and Library Favorites badge with crisp ink contrast',
      (tester) async {
        final monoPreset = ThemeProvider.curatedPresets
            .firstWhere((p) => p.id == 'monochrome_ink');
        final tp = ThemeProvider()..applyPreset(monoPreset);
        await DatabaseService.saveCachedFeed('All:English', const [
          Song(id: 'm1', title: 'Mono Track', artist: 'Artist', thumbnailUrl: ''),
        ]);
        final pp = _ThemeTestPlaybackProvider()
          ..seed(
            const Song(
              id: 'm1',
              title: 'Mono Track',
              artist: 'Artist',
              thumbnailUrl: '',
            ),
          );

        await tester.pumpWidget(
          wrapThemed(
            tester: tester,
            themeProvider: tp,
            playbackProvider: pp,
            child: const MainScaffold(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Library'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Playlists'));
        await tester.pumpAndSettle();
        expect(find.text('Favourite Songs'), findsOneWidget);

        // Heart icon on Monochrome Favourite Songs badge uses contrasting black ink on white primary
        final badgeIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('library_favourite_songs_card')),
            matching: find.byIcon(Icons.favorite_rounded),
          ),
        );
        expect(badgeIcon.color, equals(Colors.black));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 11));
      },
    );
  });
}
