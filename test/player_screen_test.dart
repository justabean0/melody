import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/lyrics.dart';
import 'package:melody/models/song.dart';
import 'package:melody/providers/library_provider.dart';
import 'package:melody/providers/playback_provider.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/audio_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/download_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/ui/screens/artist_detail_screen.dart';
import 'package:melody/ui/screens/player_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestPlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  final bool _isLoading = false;
  Duration _position = const Duration(seconds: 42);
  final Duration _duration = const Duration(seconds: 210);
  MelodyLoopMode _loopMode = MelodyLoopMode.off;
  bool _isShuffle = false;
  double lastSpeed = 1.0;
  int clearQueueCalls = 0;

  void seed(Song song, {List<Song>? queue, int currentIndex = 0}) {
    _currentSong = song;
    _queue = queue ?? [song];
    _currentIndex = currentIndex;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Song? get currentSong => _currentSong;
  @override
  List<Song> get queue => List.unmodifiable(_queue);
  @override
  int get currentIndex => _currentIndex;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isLoading => _isLoading;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  MelodyLoopMode get loopMode => _loopMode;
  @override
  bool get isShuffle => _isShuffle;
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
  }) async {
    _currentSong = song;
    if (contextQueue != null) {
      _queue = List.of(contextQueue);
      _currentIndex = startIndex ?? 0;
    } else {
      _queue = [song];
      _currentIndex = 0;
    }
    notifyListeners();
  }

  @override
  Future<void> togglePlayPause() async {
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
  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  @override
  void cycleLoopMode() {
    _loopMode = MelodyLoopMode
        .values[(_loopMode.index + 1) % MelodyLoopMode.values.length];
    notifyListeners();
  }

  @override
  void setPlaybackSpeed(double speed) {
    lastSpeed = speed;
  }

  @override
  void addToQueue(Song song) {
    _queue = [..._queue, song];
    notifyListeners();
  }

  @override
  void playNextInQueue(Song song) {
    final nextIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue = List.of(_queue)..insert(nextIdx, song);
    notifyListeners();
  }

  @override
  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue = List.of(_queue)..removeAt(index);
      notifyListeners();
    }
  }

  @override
  void clearQueue() {
    clearQueueCalls++;
    if (_currentSong != null) {
      _queue = [_currentSong!];
      _currentIndex = 0;
    } else {
      _queue = [];
      _currentIndex = 0;
    }
    notifyListeners();
  }
}

Map<String, dynamic> _artistSearchResponseJson({
  required String artistName,
  required String browseId,
}) {
  return {
    'contents': {
      'tabbedSearchResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'musicShelfRenderer': {
                        'title': {
                          'runs': [
                            {'text': 'Artists'}
                          ],
                        },
                        'contents': [
                          {
                            'musicResponsiveListItemRenderer': {
                              'navigationEndpoint': {
                                'browseEndpoint': {
                                  'browseId': browseId,
                                  'browseEndpointContextSupportedConfigs': {
                                    'browseEndpointContextMusicConfig': {
                                      'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
                                    },
                                  },
                                },
                              },
                              'flexColumns': [
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': artistName}
                                      ],
                                    },
                                  },
                                },
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Artist'},
                                        {'text': ' • '},
                                        {'text': '12M monthly listeners'},
                                      ],
                                    },
                                  },
                                },
                              ],
                              'thumbnail': {
                                'musicThumbnailRenderer': {
                                  'thumbnail': {
                                    'thumbnails': <dynamic>[],
                                  },
                                },
                              },
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
  };
}

Map<String, dynamic> _artistBrowseResponseJson(String artistName) {
  return {
    'header': {
      'musicImmersiveHeaderRenderer': {
        'title': {
          'runs': [
            {'text': artistName}
          ],
        },
        'subscriptionButton': {
          'subscribeButtonRenderer': {
            'subscriberCountText': {
              'runs': [
                {'text': '20M subscribers'}
              ],
            },
          },
        },
      },
    },
    'contents': {
      'singleColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'musicShelfRenderer': {
                        'title': {
                          'runs': [
                            {'text': 'Top songs'}
                          ],
                        },
                        'contents': [
                          {
                            'musicResponsiveListItemRenderer': {
                              'flexColumns': [
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Signature Track'}
                                      ],
                                    },
                                  },
                                },
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': artistName}
                                      ],
                                    },
                                  },
                                },
                              ],
                              'overlay': {
                                'musicItemThumbnailOverlayRenderer': {
                                  'content': {
                                    'musicPlayButtonRenderer': {
                                      'playNavigationEndpoint': {
                                        'watchEndpoint': {
                                          'videoId': 'sig_track_01',
                                        },
                                      },
                                    },
                                  },
                                },
                              },
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Database? memoryDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    AntiBotService.reset();
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = 'test_visitor';
    SharedPreferences.setMockInitialValues({});
    memoryDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    DatabaseService.setDatabaseForTesting(memoryDb);
    await DatabaseService.init();
  });

  tearDown(() async {
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = null;
    DatabaseService.setDatabaseForTesting(null);
    DatabaseService.setPrefsForTesting(null);
    await memoryDb?.close();
    memoryDb = null;
  });

  Widget buildPlayerHarness({
    required _TestPlaybackProvider playback,
    required LibraryProvider library,
    required DownloadService downloadService,
    Size screenSize = const Size(412, 915),
    double textScale = 1.0,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackProvider>.value(value: playback),
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: PlayerScreen(downloadService: downloadService),
        ),
      ),
    );
  }

  group('DownloadService Unit Tests', () {
    const sampleSong = Song(
      id: 'dl_song_01',
      title: 'Tum Hi Ho',
      artist: 'Arijit Singh',
      duration: 262,
      thumbnailUrl: '',
    );

    test('starts idle and remains safe no-op when no downloader is attached',
        () async {
      final service = DownloadService.forTesting();
      expect(service.statusFor(sampleSong.id), DownloadStatus.notDownloaded);
      expect(service.progressFor(sampleSong.id), 0.0);
      expect(service.isDownloaded(sampleSong.id), isFalse);

      final result = await service.downloadSong(sampleSong);
      expect(result.status, DownloadStatus.notDownloaded);
      expect(service.isDownloaded(sampleSong.id), isFalse);
    });

    test('tracks progress updates, completion, duplicate guard, and removal',
        () async {
      final observedStatuses = <DownloadStatus>[];
      final observedProgress = <double>[];
      var downloaderInvocations = 0;

      final service = DownloadService.forTesting(
        downloader: (song, onProgress) async {
          downloaderInvocations++;
          onProgress(0.4);
          onProgress(1.5); // Verify clamping to 1.0
          return '/music/melody/${song.id}.m4a';
        },
      );

      service.addListener(() {
        final s = service.stateFor(sampleSong.id);
        observedStatuses.add(s.status);
        observedProgress.add(s.progress);
      });

      final done = await service.downloadSong(sampleSong);
      expect(done.status, DownloadStatus.downloaded);
      expect(done.progress, 1.0);
      expect(done.filePath, '/music/melody/dl_song_01.m4a');
      expect(service.isDownloaded(sampleSong.id), isTrue);
      expect(
        observedStatuses,
        equals([
          DownloadStatus.downloading,
          DownloadStatus.downloading,
          DownloadStatus.downloading,
          DownloadStatus.downloaded,
        ]),
      );
      expect(observedProgress, equals([0.0, 0.4, 1.0, 1.0]));

      // Second call while already downloaded does not invoke downloader again
      await service.downloadSong(sampleSong);
      expect(downloaderInvocations, 1);

      await service.removeDownload(sampleSong.id);
      expect(service.statusFor(sampleSong.id), DownloadStatus.notDownloaded);
    });

    test('records failed status cleanly when downloader throws or returns null',
        () async {
      final service = DownloadService.forTesting(
        downloader: (_, __) async => throw StateError('storage full'),
      );

      final failed = await service.downloadSong(sampleSong);
      expect(failed.status, DownloadStatus.failed);
      expect(failed.errorMessage, contains('storage full'));
      expect(service.isDownloaded(sampleSong.id), isFalse);

      // Retry with working downloader after failure succeeds
      service.downloader = (_, __) async => '/music/melody/recovered.m4a';
      final recovered = await service.downloadSong(sampleSong);
      expect(recovered.status, DownloadStatus.downloaded);
      expect(recovered.filePath, '/music/melody/recovered.m4a');
    });
  });

  group('InnerTubeService.resolveArtistByName Unit Tests', () {
    test('cleans play counts and resolves matching artist browseId via MockClient',
        () async {
      String? sentQuery;

      InnerTubeService.clientOverride = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        sentQuery = payload['query'] as String?;
        return http.Response(
          jsonEncode(
            _artistSearchResponseJson(
              artistName: 'Arijit Singh',
              browseId: 'UC_arijit_resolved_01',
            ),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final resolved = await InnerTubeService.resolveArtistByName(
        'Arijit Singh, 1.2B plays',
      );
      expect(sentQuery, equals('Arijit Singh'));
      expect(resolved, isNotNull);
      expect(resolved!.browseId, equals('UC_arijit_resolved_01'));
      expect(resolved.name, equals('Arijit Singh'));
    });

    test('returns null cleanly for unknown or unresolved artists', () async {
      InnerTubeService.clientOverride = MockClient(
        (_) async => http.Response('{}', 200),
      );

      expect(await InnerTubeService.resolveArtistByName('Unknown Artist'), isNull);
      expect(await InnerTubeService.resolveArtistByName(''), isNull);
      expect(
        await InnerTubeService.resolveArtistByName('Nonexistent Indie Act'),
        isNull,
      );
    });
  });

  group('Now Playing Screen Layout & Action Widget Tests', () {
    testWidgets(
      'keeps only Now Playing & Lyrics tabs with equal indicator width and removes top heart & bottom pills',
      (tester) async {
        final playback = _TestPlaybackProvider()
          ..seed(
            const Song(
              id: 'song_1',
              title: 'Tum Hi Ho',
              artist: 'Arijit Singh',
              artistId: 'UC_arijit',
              duration: 262,
              thumbnailUrl: '',
            ),
          );
        final library = LibraryProvider();
        final downloadService = DownloadService.forTesting();

        await tester.pumpWidget(
          buildPlayerHarness(
            playback: playback,
            library: library,
            downloadService: downloadService,
          ),
        );
        await tester.pump();

        // Only 2 tabs: Now Playing and Lyrics; Up Next completely removed from tabs & body
        final tabBarFinder = find.byType(TabBar);
        expect(tabBarFinder, findsOneWidget);
        final tabBar = tester.widget<TabBar>(tabBarFinder);
        expect(tabBar.tabs.length, 2);
        expect(tabBar.isScrollable, isFalse);
        expect(tabBar.indicatorSize, TabBarIndicatorSize.tab);

        final tabsFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byType(Tab),
        );
        expect(tabsFinder, findsNWidgets(2));
        expect(
          find.descendant(of: tabBarFinder, matching: find.text('Now Playing')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tabBarFinder, matching: find.text('Lyrics')),
          findsOneWidget,
        );
        expect(find.text('Up Next'), findsNothing);

        // Equal tab / underline width for both tabs (and verify switching to Lyrics keeps equal width)
        final firstTabSize = tester.getSize(tabsFinder.at(0));
        final secondTabSize = tester.getSize(tabsFinder.at(1));
        expect(firstTabSize.width, greaterThan(90));
        expect((firstTabSize.width - secondTabSize.width).abs(), lessThan(0.01));

        await tester.tap(find.descendant(of: tabBarFinder, matching: find.text('Lyrics')));
        await tester.pumpAndSettle();
        final firstAfterSwitch = tester.getSize(tabsFinder.at(0));
        final secondAfterSwitch = tester.getSize(tabsFinder.at(1));
        expect((firstAfterSwitch.width - secondAfterSwitch.width).abs(), lessThan(0.01));

        // Top AppBar no longer contains a Like heart button
        final appBarFinder = find.byType(AppBar);
        expect(
          find.descendant(
            of: appBarFinder,
            matching: find.byIcon(Icons.favorite),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: appBarFinder,
            matching: find.byIcon(Icons.favorite_border),
          ),
          findsNothing,
        );

        // Bottom pill chips removed completely
        expect(find.byType(Chip), findsNothing);
        expect(find.byType(ActionChip), findsNothing);
        expect(find.byType(FilterChip), findsNothing);
      },
    );

    testWidgets(
      'left-aligns track info, strips play counts, and fits 4 borderless icons above seek bar at 360dp with 1.4x text scale without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        final playback = _TestPlaybackProvider()
          ..seed(
            const Song(
              id: 'song_clean',
              title: 'Tum Hi Ho (From Aashiqui 2)',
              artist: 'Arijit Singh, 1.2B plays',
              artistId: 'UC_arijit',
              duration: 262,
              thumbnailUrl: '',
            ),
          );
        final library = LibraryProvider();
        final downloadService = DownloadService.forTesting();

        await tester.pumpWidget(
          buildPlayerHarness(
            playback: playback,
            library: library,
            downloadService: downloadService,
            screenSize: const Size(360, 780),
            textScale: 1.4,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Defensive artist cleanup strips play counts
        expect(find.text('Arijit Singh'), findsOneWidget);
        expect(find.textContaining('1.2B plays'), findsNothing);
        expect(find.textContaining('plays'), findsNothing);

        // Left alignment of title & artist
        final titleFinder = find.text('Tum Hi Ho (From Aashiqui 2)');
        final artistFinder = find.text('Arijit Singh');
        expect(tester.widget<Text>(titleFinder).textAlign, TextAlign.start);
        expect(tester.widget<Text>(artistFinder).textAlign, TextAlign.start);
        final titleRect = tester.getRect(titleFinder);
        final artistRect = tester.getRect(artistFinder);
        expect(titleRect.left, closeTo(24.0, 4.0));
        expect(artistRect.left, closeTo(24.0, 4.0));

        // Exact order: Speed -> Queue -> Download -> Like, directly above the Slider
        final speedRect = tester.getRect(find.byKey(const Key('player_speed_button')));
        final queueRect = tester.getRect(find.byKey(const Key('player_queue_button')));
        final downloadRect =
            tester.getRect(find.byKey(const Key('player_download_button')));
        final likeRect = tester.getRect(find.byKey(const Key('player_like_button')));
        final sliderRect = tester.getRect(find.byType(Slider));

        expect(speedRect.center.dx, lessThan(queueRect.center.dx));
        expect(queueRect.center.dx, lessThan(downloadRect.center.dx));
        expect(downloadRect.center.dx, lessThan(likeRect.center.dx));
        expect(likeRect.right, lessThanOrEqualTo(360.0));

        expect(speedRect.center.dy, lessThan(sliderRect.center.dy));
        expect(queueRect.center.dy, lessThan(sliderRect.center.dy));
        expect(downloadRect.center.dy, lessThan(sliderRect.center.dy));
        expect(likeRect.center.dy, lessThan(sliderRect.center.dy));
      },
    );

    testWidgets(
      'wires Speed menu, Queue bottom sheet, Download states, and Like toggle cleanly',
      (tester) async {
        const song1 = Song(
          id: 'song_a',
          title: 'Kesariya',
          artist: 'Arijit Singh',
          artistId: 'UC_arijit',
          duration: 240,
          thumbnailUrl: '',
        );
        const song2 = Song(
          id: 'song_b',
          title: 'Raatan Lambiyan',
          artist: 'Jubin Nautiyal',
          artistId: 'UC_jubin',
          duration: 230,
          thumbnailUrl: '',
        );

        final playback = _TestPlaybackProvider()
          ..seed(song1, queue: [song1, song2], currentIndex: 0);
        final library = LibraryProvider();

        final dlCompleter = Completer<String?>();
        final downloadService = DownloadService.forTesting(
          downloader: (song, onProgress) {
            onProgress(0.5);
            return dlCompleter.future;
          },
        );

        await tester.pumpWidget(
          buildPlayerHarness(
            playback: playback,
            library: library,
            downloadService: downloadService,
          ),
        );
        await tester.pump();

        // 1. Speed menu
        await tester.tap(find.byKey(const Key('player_speed_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1.5x'));
        await tester.pumpAndSettle();
        expect(playback.lastSpeed, equals(1.5));

        // 2. Like toggle
        expect(
          find.descendant(
            of: find.byKey(const Key('player_like_button')),
            matching: find.byIcon(Icons.favorite_border),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('player_like_button')));
        await tester.pumpAndSettle();
        expect(library.isLiked(song1.id), isTrue);
        expect(
          find.descendant(
            of: find.byKey(const Key('player_like_button')),
            matching: find.byIcon(Icons.favorite),
          ),
          findsOneWidget,
        );

        // 3. Download flow (idle -> downloading indicator -> downloaded checkmark)
        expect(
          find.descendant(
            of: find.byKey(const Key('player_download_button')),
            matching: find.byIcon(Icons.download_rounded),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('player_download_button')));
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('player_download_button')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        dlCompleter.complete('/music/melody/song_a.m4a');
        await tester.pumpAndSettle();
        expect(downloadService.isDownloaded(song1.id), isTrue);
        expect(
          find.descendant(
            of: find.byKey(const Key('player_download_button')),
            matching: find.byIcon(Icons.download_done_rounded),
          ),
          findsOneWidget,
        );

        // 4. Queue bottom sheet
        await tester.tap(find.byKey(const Key('player_queue_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Up Next (1 track)'), findsOneWidget);
        expect(find.text('Raatan Lambiyan'), findsOneWidget);

        await tester.tap(find.text('Clear Queue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(playback.clearQueueCalls, 1);
        expect(find.text('Up Next'), findsOneWidget);
        expect(find.text('Raatan Lambiyan'), findsNothing);
      },
    );

    testWidgets(
      'navigates directly when artistId is present, resolves missing artistId, and offers multi-artist picker sheet',
      (tester) async {
        InnerTubeService.clientOverride = MockClient((request) async {
          if (request.url.path.contains('search')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final q = (body['query'] as String?) ?? 'Artist';
            return http.Response(
              jsonEncode(
                _artistSearchResponseJson(
                  artistName: q,
                  browseId: 'UC_${q.toLowerCase().replaceAll(' ', '_')}',
                ),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path.contains('browse')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final browseId = (body['browseId'] as String?) ?? '';
            final artistName = browseId.contains('irshad')
                ? 'Irshad Kamil'
                : 'Shreya Ghoshal';
            return http.Response(
              jsonEncode(_artistBrowseResponseJson(artistName)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 200);
        });

        final playback = _TestPlaybackProvider()
          ..seed(
            const Song(
              id: 'song_direct',
              title: 'Sunn Raha Hai',
              artist: 'Shreya Ghoshal',
              artistId: 'UC_shreya_direct',
              duration: 300,
              thumbnailUrl: '',
            ),
          );
        final library = LibraryProvider();
        final downloadService = DownloadService.forTesting();

        await tester.pumpWidget(
          buildPlayerHarness(
            playback: playback,
            library: library,
            downloadService: downloadService,
          ),
        );
        await tester.pump();

        // A. Single artist with artistId pushes ArtistDetailScreen directly
        await tester.tap(find.byKey(const Key('player_artist_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ArtistDetailScreen), findsOneWidget);
        final directDetail =
            tester.widget<ArtistDetailScreen>(find.byType(ArtistDetailScreen));
        expect(directDetail.browseId, equals('UC_shreya_direct'));
        expect(directDetail.name, equals('Shreya Ghoshal'));

        // Navigate back to PlayerScreen cleanly
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsOneWidget);

        // B. Single artist without artistId resolves via InnerTubeService
        playback.seed(
          const Song(
            id: 'song_resolve',
            title: 'Deewani Mastani',
            artist: 'Shreya Ghoshal, 90M plays',
            artistId: null,
            duration: 320,
            thumbnailUrl: '',
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('player_artist_button')));
        await tester.pumpAndSettle();
        expect(find.byType(ArtistDetailScreen), findsOneWidget);
        final resolvedDetail =
            tester.widget<ArtistDetailScreen>(find.byType(ArtistDetailScreen));
        expect(resolvedDetail.browseId, equals('UC_shreya_ghoshal'));

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        // C. Multi-artist opens picker bottom sheet and resolves selected artist
        playback.seed(
          const Song(
            id: 'song_multi',
            title: 'Agar Tum Saath Ho',
            artist: 'Shreya Ghoshal, Irshad Kamil',
            artistId: 'UC_shreya_direct',
            duration: 341,
            thumbnailUrl: '',
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('player_artist_button')));
        await tester.pumpAndSettle();
        expect(find.text('Artists'), findsOneWidget);
        expect(find.text('Irshad Kamil'), findsOneWidget);

        await tester.tap(find.text('Irshad Kamil'));
        await tester.pumpAndSettle();
        expect(find.byType(ArtistDetailScreen), findsOneWidget);
        final secondDetail =
            tester.widget<ArtistDetailScreen>(find.byType(ArtistDetailScreen));
        expect(secondDetail.browseId, equals('UC_irshad_kamil'));
        expect(secondDetail.name, equals('Irshad Kamil'));
      },
    );

    testWidgets(
      'shows floating snackbar fallback when artist cannot be resolved offline',
      (tester) async {
        InnerTubeService.clientOverride = MockClient(
          (_) async => http.Response('{}', 200),
        );

        final playback = _TestPlaybackProvider()
          ..seed(
            const Song(
              id: 'song_offline',
              title: 'Hidden Acoustic Track',
              artist: 'Unresolved Acoustic Artist',
              artistId: null,
              duration: 195,
              thumbnailUrl: '',
            ),
          );
        final library = LibraryProvider();
        final downloadService = DownloadService.forTesting();

        await tester.pumpWidget(
          buildPlayerHarness(
            playback: playback,
            library: library,
            downloadService: downloadService,
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('player_artist_button')));
        await tester.pumpAndSettle();

        expect(find.byType(ArtistDetailScreen), findsNothing);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(
          find.text('Could not load artist page for Unresolved Acoustic Artist.'),
          findsOneWidget,
        );
      },
    );
  });
}
