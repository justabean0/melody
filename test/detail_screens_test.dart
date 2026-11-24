import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/search_result.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/ui/screens/artist_detail_screen.dart';
import 'package:melody/ui/screens/collection_detail_screen.dart';
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

  Widget buildTestApp({
    required SearchProvider searchProvider,
    required PlaybackProvider playbackProvider,
    required LibraryProvider libraryProvider,
    Widget home = const SearchScreen(),
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
        ChangeNotifierProvider<PlaybackProvider>.value(value: playbackProvider),
        ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
      ],
      child: MaterialApp(
        home: home,
      ),
    );
  }

  group('Detail Screens Navigation & Skeleton Tests', () {
    testWidgets(
      'Tapping an Album card in SearchScreen navigates to CollectionDetailScreen and displays CollectionDetailSkeleton while loading',
      (tester) async {
        final albumCompleter = Completer<http.Response>();

        InnerTubeService.clientOverride = MockClient((request) async {
          if (request.url.path.contains('browse')) {
            return albumCompleter.future;
          }
          return http.Response('{}', 200);
        });

        final searchProvider = SearchProvider();
        final playbackProvider = PlaybackProvider();
        final libraryProvider = LibraryProvider();

        // Seed searchProvider with an album result
        final testAlbum = const Album(
          id: 'MPREb_album123',
          title: 'Rockstar',
          artist: 'A.R. Rahman',
          year: 2011,
          thumbnailUrl: 'https://lh3.googleusercontent.com/album_thumb',
        );

        searchProvider.setResultsForTesting(
          SearchResult(
            albums: [testAlbum],
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            searchProvider: searchProvider,
            playbackProvider: playbackProvider,
            libraryProvider: libraryProvider,
          ),
        );

        // Verify Album is visible on SearchScreen
        expect(find.text('Rockstar'), findsOneWidget);

        // Tap the Album card
        await tester.tap(find.text('Rockstar'));
        await tester.pump(); // Start navigation transition
        await tester.pump(const Duration(milliseconds: 100)); // Halfway into transition

        // CollectionDetailScreen is pushed and displays skeleton while loading
        expect(find.byType(CollectionDetailScreen), findsOneWidget);
        expect(find.byType(CollectionDetailSkeleton), findsOneWidget);

        // Mock response for album browse matching InnerTube twoColumn format
        const mockAlbumJson = '''
{
  "contents": {
    "twoColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "content": {
              "sectionListRenderer": {
                "contents": [
                  {
                    "musicResponsiveHeaderRenderer": {
                      "title": {
                        "runs": [{"text": "Rockstar"}]
                      },
                      "straplineTextOne": {
                        "runs": [
                          {
                            "text": "A.R. Rahman",
                            "navigationEndpoint": {
                              "browseEndpoint": {"browseId": "UC_ar_rahman"}
                            }
                          }
                        ]
                      },
                      "subtitle": {
                        "runs": [
                          {"text": "Album"},
                          {"text": " • "},
                          {"text": "2011"}
                        ]
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      ],
      "secondaryContents": {
        "sectionListRenderer": {
          "contents": [
            {
              "musicPlaylistShelfRenderer": {
                "contents": [
                  {
                    "musicResponsiveListItemRenderer": {
                      "playlistItemData": {"videoId": "vid_kun_faya_kun"},
                      "flexColumns": [
                        {
                          "musicResponsiveListItemFlexColumnRenderer": {
                            "text": {
                              "runs": [{"text": "Kun Faya Kun"}]
                            }
                          }
                        },
                        {
                          "musicResponsiveListItemFlexColumnRenderer": {
                            "text": {
                              "runs": [{"text": "A.R. Rahman, Javed Ali"}]
                            }
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}
''';

        albumCompleter.complete(
          http.Response(
            mockAlbumJson,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );

        await tester.pumpAndSettle();

        // Skeleton is replaced by real content
        expect(find.byType(CollectionDetailSkeleton), findsNothing);
        expect(find.text('Kun Faya Kun'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Shuffle'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping an Artist card in SearchScreen navigates to ArtistDetailScreen and displays ArtistDetailSkeleton while loading',
      (tester) async {
        final artistCompleter = Completer<http.Response>();

        InnerTubeService.clientOverride = MockClient((request) async {
          if (request.url.path.contains('browse')) {
            return artistCompleter.future;
          }
          return http.Response('{}', 200);
        });

        final searchProvider = SearchProvider();
        final playbackProvider = PlaybackProvider();
        final libraryProvider = LibraryProvider();

        final testArtist = const Artist(
          id: 'UC_artist123',
          name: 'Arijit Singh',
          subscribers: '35M subscribers',
          thumbnailUrl: 'https://lh3.googleusercontent.com/artist_thumb',
        );

        searchProvider.setResultsForTesting(
          SearchResult(
            artists: [testArtist],
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            searchProvider: searchProvider,
            playbackProvider: playbackProvider,
            libraryProvider: libraryProvider,
          ),
        );

        expect(find.text('Arijit Singh'), findsOneWidget);

        // Tap the Artist card
        await tester.tap(find.text('Arijit Singh'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(ArtistDetailScreen), findsOneWidget);
        expect(find.byType(ArtistDetailSkeleton), findsOneWidget);

        // Mock response for artist browse
        const mockArtistJson = '''
{
  "header": {
    "musicImmersiveHeaderRenderer": {
      "title": {"runs": [{"text": "Arijit Singh"}]},
      "subscriptionButton": {
        "subscribeButtonRenderer": {
          "subscriberCountText": {"runs": [{"text": "35M subscribers"}]}
        }
      }
    }
  },
  "contents": {
    "singleColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "content": {
              "sectionListRenderer": {
                "contents": [
                  {
                    "musicShelfRenderer": {
                      "title": {"runs": [{"text": "Songs"}]},
                      "contents": [
                        {
                          "musicResponsiveListItemRenderer": {
                            "flexColumns": [
                              {
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": {"runs": [{"text": "Tum Hi Ho"}]}
                                }
                              },
                              {
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": {"runs": [{"text": "Arijit Singh"}]}
                                }
                              }
                            ],
                            "overlay": {
                              "musicItemThumbnailOverlayRenderer": {
                                "content": {
                                  "musicPlayButtonRenderer": {
                                    "playNavigationEndpoint": {
                                      "watchEndpoint": {"videoId": "tum_hi_ho_id"}
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
}
''';

        artistCompleter.complete(
          http.Response(
            mockArtistJson,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(ArtistDetailSkeleton), findsNothing);
        expect(find.text('Tum Hi Ho'), findsOneWidget);
        expect(find.text('Play Songs'), findsOneWidget);
      },
    );

    testWidgets(
      'SearchScreen Top Result hero card renders and navigates to CollectionDetailScreen for Album top result',
      (tester) async {
        final albumCompleter = Completer<http.Response>();

        InnerTubeService.clientOverride = MockClient((request) async {
          if (request.url.path.contains('browse')) {
            return albumCompleter.future;
          }
          return http.Response('{}', 200);
        });

        final searchProvider = SearchProvider();
        final playbackProvider = PlaybackProvider();
        final libraryProvider = LibraryProvider();

        final topAlbum = const Album(
          id: 'MPREb_top_album',
          title: 'Top Album Hit',
          artist: 'Hit Artist',
          year: 2024,
          thumbnailUrl: 'https://lh3.googleusercontent.com/top_album',
        );

        searchProvider.setResultsForTesting(
          SearchResult(
            topResult: topAlbum,
            albums: [topAlbum],
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            searchProvider: searchProvider,
            playbackProvider: playbackProvider,
            libraryProvider: libraryProvider,
          ),
        );

        expect(find.text('Top Result'), findsOneWidget);
        expect(find.text('Top Album Hit'), findsWidgets);

        // Tap the Top Result card
        await tester.tap(find.text('Top Album Hit').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(CollectionDetailScreen), findsOneWidget);
        expect(find.byType(CollectionDetailSkeleton), findsOneWidget);

        albumCompleter.complete(
          http.Response(
            '{"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[]}}}}]}}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  });
}
