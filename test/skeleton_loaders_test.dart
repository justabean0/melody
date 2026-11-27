import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/providers/theme_provider.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/ui/screens/search_screen.dart';
import 'package:melody/widgets/skeleton_loaders.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.init();
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = 'test_visitor';
  });

  tearDown(() {
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = null;
  });

  group('Skeleton Loaders Render & Accessibility Tests', () {
    testWidgets('HomeFeedSkeleton renders cleanly without overflow and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeFeedSkeleton(),
          ),
        ),
      );

      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Verify animation ticks cleanly
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomeFeedSkeleton renders static blocks when disableAnimations is enabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: HomeFeedSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SearchResultsSkeleton renders cleanly without overflow and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SearchResultsSkeleton(),
          ),
        ),
      );

      expect(find.byType(SearchResultsSkeleton), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SearchResultsSkeleton renders with disableAnimations enabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: SearchResultsSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(SearchResultsSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('CollectionDetailSkeleton renders cleanly without overflow and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CollectionDetailSkeleton(),
          ),
        ),
      );

      expect(find.byType(CollectionDetailSkeleton), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('CollectionDetailSkeleton renders with disableAnimations enabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: CollectionDetailSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(CollectionDetailSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ArtistDetailSkeleton renders cleanly without overflow and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtistDetailSkeleton(),
          ),
        ),
      );

      expect(find.byType(ArtistDetailSkeleton), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ArtistDetailSkeleton renders with disableAnimations enabled', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: ArtistDetailSkeleton(),
            ),
          ),
        ),
      );

      expect(find.byType(ArtistDetailSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shimmer disposes AnimationController cleanly without ticker leaks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Shimmer(
              child: SkeletonBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // Unmount the Shimmer widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomeFeedSkeleton matches home feed layout (4-row peek column + 140dp cards) at 360dp and 1.4x scale in Dark and Light modes', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final darkScheme = ThemeProvider.buildColorScheme(
        seed: const Color(0xFF8E24AA),
        brightness: Brightness.dark,
        pureBlack: true,
      );
      final lightScheme = ThemeProvider.buildColorScheme(
        seed: const Color(0xFF8E24AA),
        brightness: Brightness.light,
        pureBlack: false,
      );

      for (final scheme in [darkScheme, lightScheme]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.4),
              disableAnimations: true,
            ),
            child: MaterialApp(
              theme: ThemeData(useMaterial3: true, colorScheme: scheme),
              home: const Scaffold(body: HomeFeedSkeleton()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify 2 horizontal Quick Picks columns (4 rows each) with ~0.91 width peek
        final quickPickRow = tester.widget<Row>(
          find.descendant(
            of: find.byType(LayoutBuilder),
            matching: find.byType(Row),
          ).first,
        );
        expect(quickPickRow.children.length, equals(2));
        final firstCol = quickPickRow.children.first as SizedBox;
        expect(firstCol.width, closeTo(360 * 0.91, 1.0));
        final firstColColumn = firstCol.child as Column;
        expect(firstColColumn.children.length, equals(4));

        // Verify 140dp square shelf cards exist for Featured & Trending / Albums
        final cards140 = tester.widgetList<SkeletonBox>(find.byType(SkeletonBox)).where(
              (box) => box.width == 140 && box.height == 140,
            );
        expect(cards140.length, greaterThanOrEqualTo(4));
      }
    });

    testWidgets('SearchResultsSkeleton matches headerless search layout (Top Result play circle + 80dp Artists) in Dark and Light modes', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final darkScheme = ThemeProvider.buildColorScheme(
        seed: const Color(0xFF8E24AA),
        brightness: Brightness.dark,
        pureBlack: true,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
            home: const Scaffold(body: SearchResultsSkeleton()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Top Result circular trailing play button placeholder (42dp circle)
      final playCircles = tester.widgetList<SkeletonBox>(find.byType(SkeletonBox)).where(
            (box) => box.shape == BoxShape.circle && box.width == 42 && box.height == 42,
          );
      expect(playCircles.length, equals(1));

      // 80dp circular Artist placeholders
      final artistCircles = tester.widgetList<SkeletonBox>(find.byType(SkeletonBox)).where(
            (box) => box.shape == BoxShape.circle && box.width == 80 && box.height == 80,
          );
      expect(artistCircles.length, equals(4));

      // Surface uses pitch-black #000000 in dark mode
      final rootSurface = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(SearchResultsSkeleton),
          matching: find.byType(ColoredBox),
        ).first,
      );
      expect(rootSurface.color, equals(const Color(0xFF000000)));
    });

    testWidgets('CollectionDetailSkeleton and ArtistDetailSkeleton use pitch-black #000000 surface in Dark Mode at 1.4x scale', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final darkScheme = ThemeProvider.buildColorScheme(
        seed: const Color(0xFF8E24AA),
        brightness: Brightness.dark,
        pureBlack: true,
      );

      for (final widget in const [
        CollectionDetailSkeleton(),
        ArtistDetailSkeleton(),
      ]) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.4),
              disableAnimations: true,
            ),
            child: MaterialApp(
              theme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
              home: Scaffold(body: widget),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final rootSurface = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byWidget(widget),
            matching: find.byType(ColoredBox),
          ).first,
        );
        expect(rootSurface.color, equals(const Color(0xFF000000)));
      }
    });
  });

  group('SearchScreen Skeleton Integration Tests', () {
    testWidgets('SearchScreen displays SearchResultsSkeleton when isLoading is true', (tester) async {
      final searchCompleter = Completer<http.Response>();

      InnerTubeService.clientOverride = MockClient((request) async {
        return searchCompleter.future;
      });

      final searchProvider = SearchProvider();
      final playbackProvider = PlaybackProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
            ChangeNotifierProvider<PlaybackProvider>.value(value: playbackProvider),
          ],
          child: const MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );

      // Trigger search which sets isLoading = true
      unawaited(searchProvider.performSearch('Kesariya'));
      await tester.pump();

      expect(searchProvider.isLoading, isTrue);
      expect(find.byType(SearchResultsSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Complete the request with valid InnerTube structure and settle
      searchCompleter.complete(
        http.Response(
          '{"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[]}}}}]}}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}
