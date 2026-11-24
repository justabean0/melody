import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
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
