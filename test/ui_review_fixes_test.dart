import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:melody/services/download_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/local_audio_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:melody/services/stream_resolver_service.dart';
import 'package:melody/ui/components/language_selection_dialog.dart';
import 'package:melody/ui/components/lyrics_view.dart';
import 'package:melody/ui/components/mini_player.dart';
import 'package:melody/ui/components/song_tile.dart';
import 'package:melody/ui/screens/artist_detail_screen.dart';
import 'package:melody/ui/screens/collection_detail_screen.dart';
import 'package:melody/ui/screens/home_screen.dart';
import 'package:melody/ui/screens/library_screen.dart';
import 'package:melody/ui/screens/liked_songs_screen.dart';
import 'package:melody/ui/screens/player_screen.dart';
import 'package:melody/ui/screens/search_screen.dart';
import 'package:melody/ui/screens/settings_screen.dart';
import 'package:melody/widgets/skeleton_loaders.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ReviewPlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isShuffle = false;
  Duration _position = const Duration(seconds: 25);
  Duration _duration = const Duration(seconds: 200);
  LyricsData? _lyrics;
  double lastSpeed = 1.0;
  int playSongCalls = 0;
  Song? lastPlayedSong;
  List<Song>? lastContextQueue;

  void seed(
    Song song, {
    List<Song>? queue,
    LyricsData? lyrics,
    Duration position = const Duration(seconds: 25),
    Duration duration = const Duration(seconds: 200),
  }) {
    _currentSong = song;
    _queue = queue ?? [song];
    _currentIndex = 0;
    _isPlaying = true;
    _lyrics = lyrics;
    _position = position;
    _duration = duration;
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
  bool get isLoading => false;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  MelodyLoopMode get loopMode => MelodyLoopMode.off;
  @override
  bool get isShuffle => _isShuffle;
  @override
  LyricsData? get lyrics => _lyrics;
  @override
  bool get isLoadingLyrics => false;

  @override
  int get activeLyricIndex {
    if (_lyrics == null || !_lyrics!.isSynced) return -1;
    final ms = _position.inMilliseconds;
    final lines = _lyrics!.syncedLyrics;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (ms >= lines[i].timeMs) return i;
    }
    return 0;
  }

  @override
  Future<void> playSong(
    Song song, {
    List<Song>? contextQueue,
    int? startIndex,
  }) async {
    playSongCalls++;
    lastPlayedSong = song;
    lastContextQueue = contextQueue;
    _currentSong = song;
    _queue = contextQueue ?? [song];
    _currentIndex = startIndex ?? 0;
    _isPlaying = true;
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
  void cycleLoopMode() {}

  @override
  void setPlaybackSpeed(double speed) {
    lastSpeed = speed;
  }

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
            (_) async => {},
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
        if (call.method == 'isIgnoringBatteryOptimizations') return true;
        if (call.method == 'getBackgroundPlaybackEnabled') return false;
        return true;
      },
    );
  });

  setUp(() async {
    AntiBotService.reset();
    InnerTubeService.clientOverride =
        MockClient((_) async => http.Response('{}', 200));
    StreamResolverService.clientOverride =
        MockClient((_) async => http.Response('{}', 200));
    InnerTubeService.visitorData = 'test_visitor';
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
    InnerTubeService.visitorData = null;
    StreamResolverService.clientOverride = null;
  });

  Widget wrapViewport({
    required WidgetTester tester,
    required Widget child,
    ThemeProvider? themeProvider,
    LibraryProvider? libraryProvider,
    PlaybackProvider? playbackProvider,
    SearchProvider? searchProvider,
    ThemeMode themeMode = ThemeMode.dark,
    Size size = const Size(412, 915),
    double textScale = 1.0,
    bool disableAnimations = false,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tp = themeProvider ?? ThemeProvider()..setThemeMode(themeMode);
    final lp = libraryProvider ?? LibraryProvider();
    final pp = playbackProvider ?? _ReviewPlaybackProvider();
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
        themeMode: themeMode,
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

  group('UI-01 to UI-08 Fixes Verification', () {
    testWidgets(
      'UI-01: LanguageSelectionDialog scales cleanly at 360dp / 1.8x, enforces 48dp close button, uses onPrimary check, and shows inline hint',
      (tester) async {
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.8,
            child: const Scaffold(
              body: LanguageSelectionDialog(isDismissible: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final closeBtn = find.byTooltip('Close');
        expect(closeBtn, findsOneWidget);
        expect(tester.getSize(closeBtn).width, greaterThanOrEqualTo(48.0));
        expect(tester.getSize(closeBtn).height, greaterThanOrEqualTo(48.0));

        // Tapping the sole selected language shows inline hint instead of SnackBar
        final dialogScrollable = find.byType(Scrollable).first;
        final englishFinder = find.text('English');
        await tester.scrollUntilVisible(
          englishFinder,
          120,
          scrollable: dialogScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(englishFinder);
        await tester.pumpAndSettle();
        expect(find.text('Keep at least 1 language selected.'), findsOneWidget);

        // Selected check icon uses colorScheme.onPrimary in Dark Mode
        final scheme = Theme.of(tester.element(find.byType(LanguageSelectionDialog))).colorScheme;
        final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded).first);
        expect(checkIcon.color, equals(scheme.onPrimary));

        // Search clear button clears typed query
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Hin');
        await tester.pump();
        expect(find.byTooltip('Clear language search'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear language search'));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('Spanish'),
          120,
          scrollable: dialogScrollable,
        );
        expect(find.text('Spanish'), findsOneWidget);
      },
    );

    testWidgets(
      'UI-02 & UI-10: CollectionDetailScreen wraps Play/Shuffle at 360dp / 1.6x, opens artist via artistId, and renders About card',
      (tester) async {
        InnerTubeService.clientOverride = MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final browseId = (payload['browseId'] as String?) ?? '';
          if (browseId == 'UC_artist_nav') {
            return http.Response(
              jsonEncode({
                'header': {
                  'musicImmersiveHeaderRenderer': {
                    'title': {
                      'runs': [
                        {'text': 'Pritam'}
                      ]
                    },
                  },
                },
                'contents': {
                  'singleColumnBrowseResultsRenderer': {
                    'tabs': [
                      {
                        'tabRenderer': {
                          'content': {
                            'sectionListRenderer': {'contents': <dynamic>[]}
                          }
                        }
                      }
                    ]
                  }
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'contents': {
                'twoColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'musicResponsiveHeaderRenderer': {
                                  'title': {
                                    'runs': [
                                      {'text': 'Yeh Jawaani Hai Deewani'}
                                    ]
                                  },
                                  'straplineTextOne': {
                                    'runs': [
                                      {
                                        'text': 'Pritam',
                                        'navigationEndpoint': {
                                          'browseEndpoint': {
                                            'browseId': 'UC_artist_nav',
                                          }
                                        }
                                      }
                                    ]
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Album'},
                                      {'text': ' • '},
                                      {'text': '2013'},
                                    ]
                                  },
                                  'description': {
                                    'musicDescriptionShelfRenderer': {
                                      'description': {
                                        'runs': [
                                          {
                                            'text':
                                                'Iconic Bollywood soundtrack composed by Pritam.'
                                          }
                                        ]
                                      }
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ],
                  'secondaryContents': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'musicPlaylistShelfRenderer': {
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'playlistItemData': {'videoId': 'trk_1'},
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Badtameez Dil'}
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Pritam'}
                                          ]
                                        }
                                      }
                                    },
                                  ],
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  },
                }
              }
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.6,
            child: const CollectionDetailScreen(
              browseId: 'MPREb_yjhd',
              isAlbum: true,
              title: 'Yeh Jawaani Hai Deewani',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final descriptionFinder = find.text(
          'Iconic Bollywood soundtrack composed by Pritam.',
        );
        await tester.scrollUntilVisible(
          descriptionFinder,
          150,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('About'), findsOneWidget);
        expect(descriptionFinder, findsOneWidget);

        final artistButton = find.byKey(const Key('collection_artist_button'));
        expect(artistButton, findsOneWidget);
        expect(tester.getSize(artistButton).height, greaterThanOrEqualTo(48.0));

        await tester.tap(artistButton);
        await tester.pumpAndSettle();
        expect(find.byType(ArtistDetailScreen), findsOneWidget);
      },
    );

    testWidgets(
      'UI-03: SearchBar and Home/Search chip rows render without clipping at 360dp / 1.8x scale',
      (tester) async {
        await DatabaseService.saveCachedFeed('All:English', const [
          Song(id: 's1', title: 'Track One', artist: 'Artist', thumbnailUrl: ''),
        ]);

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.8,
            child: const HomeScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.8,
            child: const SearchScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'UI-04: SongTile Add-to-Playlist shows singular track count and validates Create Playlist input',
      (tester) async {
        await DatabaseService.createPlaylist('Focus Mix');
        final plId = DatabaseService.getPlaylists().first.id;
        await DatabaseService.addSongToPlaylist(
          plId,
          const Song(id: 'seed_1', title: 'Seed', artist: 'Art', thumbnailUrl: ''),
        );
        final library = LibraryProvider();
        const song = Song(
          id: 'target_1',
          title: 'Target Song',
          artist: 'Target Artist',
          thumbnailUrl: '',
        );

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            libraryProvider: library,
            child: const Scaffold(
              body: SongTile(song: song),
            ),
          ),
        );

        await tester.tap(find.byTooltip('Track options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to Playlist'));
        await tester.pumpAndSettle();

        expect(find.text('1 track'), findsOneWidget);
        expect(find.text('1 tracks'), findsNothing);

        await tester.tap(find.text('New Playlist'));
        await tester.pumpAndSettle();

        // Submitting empty field via keyboard shows validation error
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('Enter a playlist name'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Fresh List');
        await tester.pump();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(library.playlists.any((p) => p.title == 'Fresh List'), isTrue);
      },
    );

    testWidgets(
      'UI-05: SettingsScreen Light Mode battery and InnerTube status labels meet >= 4.5:1 contrast on white cards',
      (tester) async {
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            themeMode: ThemeMode.light,
            child: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        final batterySubtitle = tester.widget<Text>(
          find.text('Unrestricted — background audio will not be killed by OS'),
        );
        final batteryRatio = ThemeProvider.contrastRatio(
          batterySubtitle.style!.color!,
          Colors.white,
        );
        expect(batteryRatio, greaterThanOrEqualTo(4.5));

        await tester.scrollUntilVisible(
          find.text('Healthy'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final healthyText = tester.widget<Text>(find.text('Healthy'));
        final healthyRatio = ThemeProvider.contrastRatio(
          healthyText.style!.color!,
          Colors.white,
        );
        expect(healthyRatio, greaterThanOrEqualTo(4.5));
      },
    );

    testWidgets(
      'UI-07: PlayerScreen preserves speed across reopen, shows compact 1.5× label, and uses 48dp artist target',
      (tester) async {
        const song = Song(
          id: 'spd_1',
          title: 'Speed Track',
          artist: 'Arijit Singh',
          duration: 200,
          thumbnailUrl: '',
        );
        final playback = _ReviewPlaybackProvider()..seed(song);
        final library = LibraryProvider();
        final downloads = DownloadService.forTesting();

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.4,
            playbackProvider: playback,
            libraryProvider: library,
            child: PlayerScreen(downloadService: downloads),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(
          tester.getSize(find.byKey(const Key('player_artist_button'))).height,
          greaterThanOrEqualTo(48.0),
        );

        await tester.tap(find.byKey(const Key('player_speed_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1.5x'));
        await tester.pumpAndSettle();
        expect(playback.lastSpeed, equals(1.5));
        expect(find.text('1.5×'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Recreate PlayerScreen -> speed state persists via PlaybackProvider.speedOf
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.4,
            playbackProvider: playback,
            libraryProvider: library,
            child: const SizedBox.shrink(),
          ),
        );
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(360, 780),
            textScale: 1.4,
            playbackProvider: playback,
            libraryProvider: library,
            child: PlayerScreen(downloadService: downloads),
          ),
        );
        await tester.pump();
        expect(find.text('1.5×'), findsOneWidget);
      },
    );

    testWidgets(
      'UI-08: MiniPlayer upgrades low-res artwork URLs and LikedSongsScreen Play All is >= 48dp tall',
      (tester) async {
        await DatabaseService.toggleLike(
          const Song(
            id: 'liked_1',
            title: 'Liked Track',
            artist: 'Artist',
            thumbnailUrl: 'https://lh3.googleusercontent.com/art=w60-h60-l90-rj',
          ),
        );
        final library = LibraryProvider();
        final playback = _ReviewPlaybackProvider()
          ..seed(
            const Song(
              id: 'mini_up',
              title: 'Mini Song',
              artist: 'Mini Artist',
              thumbnailUrl:
                  'https://lh3.googleusercontent.com/cover=w60-h60-l90-rj',
            ),
          );

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            libraryProvider: library,
            playbackProvider: playback,
            child: const Scaffold(body: MiniPlayer()),
          ),
        );
        await tester.pump();
        final img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
        expect(img.imageUrl, contains('w544-h544'));

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            libraryProvider: library,
            playbackProvider: playback,
            child: const LikedSongsScreen(),
          ),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const Key('liked_songs_play_all_button'))).height,
          greaterThanOrEqualTo(48.0),
        );
      },
    );
  });

  group('UI-09 to UI-17 UX & Responsive Improvements Verification', () {
    testWidgets(
      'UI-09: HomeScreen keeps mood chips pinned above HomeFeedSkeleton during mood switch',
      (tester) async {
        await DatabaseService.saveCachedFeed('All:English', const [
          Song(id: 'hm_1', title: 'Initial Pick', artist: 'Artist', thumbnailUrl: ''),
        ]);
        final pendingFeed = Completer<http.Response>();
        InnerTubeService.clientOverride = MockClient((_) => pendingFeed.future);

        await tester.pumpWidget(
          wrapViewport(tester: tester, child: const HomeScreen()),
        );
        await tester.pump();

        await tester.tap(find.text('Chill'));
        await tester.pump();

        expect(find.byType(HomeFeedSkeleton), findsOneWidget);
        expect(find.byType(FilterChip), findsWidgets);
        final skeleton = tester.widget<HomeFeedSkeleton>(find.byType(HomeFeedSkeleton));
        expect(skeleton.showMoodChips, isFalse);

        pendingFeed.complete(http.Response('{}', 200));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'UI-10: SearchScreen empty filtered results offer Search in All recovery button',
      (tester) async {
        final search = SearchProvider()
          ..setFilter(SearchFilter.albums)
          ..setResultsForTesting(const SearchResult());

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            searchProvider: search,
            child: const SearchScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Search in All'), findsOneWidget);
        await tester.tap(find.text('Search in All'));
        await tester.pumpAndSettle();
        expect(search.filter, equals(SearchFilter.all));
      },
    );

    testWidgets(
      'UI-11: History Clear and Delete Playlist require dialog confirmation, and Local tab shows Play All / Shuffle',
      (tester) async {
        await DatabaseService.addToHistory(
          const Song(id: 'hist_c1', title: 'History Track', artist: 'Artist', thumbnailUrl: ''),
        );
        await DatabaseService.createPlaylist('Gym Jams');
        final library = LibraryProvider();

        final channel = const MethodChannel(LocalAudioService.channelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAudioPermissionStatus') {
            return {'granted': true, 'permanentlyDenied': false};
          }
          if (call.method == 'scanLocalAudio') {
            return [
              {
                'id': '91',
                'contentUri': 'content://media/external/audio/media/91',
                'title': 'Offline Beat',
                'artist': 'Local Artist',
                'durationMs': 180000,
                'dateAdded': 1700000000,
                'relativePath': 'Music/Melody/',
                'displayName': 'Offline Beat.m4a',
                'isMelodyDownload': true,
              }
            ];
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final localAudio = LocalAudioService.forTesting(channel: channel);
        final downloads = DownloadService.forTesting(localAudioService: localAudio);

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            libraryProvider: library,
            child: LibraryScreen(
              localAudioService: localAudio,
              downloadService: downloads,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Cancel Clear history -> keeps history
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('Clear playback history?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(library.history.length, equals(1));

        // Confirm Clear history -> clears history
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
        await tester.pumpAndSettle();
        expect(library.history, isEmpty);

        // Playlists delete confirmation
        await tester.tap(find.byKey(const Key('library_tab_playlists')));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Playlist'));
        await tester.pumpAndSettle();
        expect(find.text('Delete "Gym Jams"?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(library.playlists, isEmpty);

        // Local tab Play All / Shuffle
        await tester.tap(find.byKey(const Key('library_tab_local')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('local_play_all_button')), findsOneWidget);
        expect(find.byKey(const Key('local_shuffle_button')), findsOneWidget);
      },
    );

    testWidgets(
      'UI-12: LyricsView uses non-lazy SingleChildScrollView so large seek jumps resolve line context accurately',
      (tester) async {
        final lines = List.generate(
          45,
          (i) => LyricLine(timeMs: i * 3000, text: 'Lyric line number $i'),
        );
        final playback = _ReviewPlaybackProvider()
          ..seed(
            const Song(id: 'lyr_1', title: 'Lyrics Track', artist: 'Artist', thumbnailUrl: ''),
            lyrics: LyricsData(syncedLyrics: lines),
            position: const Duration(milliseconds: 1000),
            duration: const Duration(seconds: 200),
          );

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            playbackProvider: playback,
            child: const Scaffold(body: LyricsView()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(find.text('Tap any line to seek'), findsOneWidget);

        // Jump directly to line 40 (well off initial viewport)
        await playback.seek(const Duration(milliseconds: 40 * 3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Lyric line number 40'), findsOneWidget);
      },
    );

    testWidgets(
      'UI-13: Playtime card shows inline top-5 play logs without nested ListView and tapping a log starts playback',
      (tester) async {
        final now = DateTime.now();
        await tester.runAsync(() async {
          for (int i = 1; i <= 7; i++) {
            await DatabaseService.recordListeningSeconds(
              60 + i,
              date: now,
              song: Song(
                id: 'log_$i',
                title: 'Logged Track $i',
                artist: 'Artist $i',
                thumbnailUrl: '',
              ),
              sessionKey: 'sess_$i',
            );
          }
        });

        final library = LibraryProvider();
        final playback = _ReviewPlaybackProvider();

        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            libraryProvider: library,
            playbackProvider: playback,
            child: const LibraryScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('playtime_hero_toggle')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('playtime_logs_list')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('playtime_logs_list')),
            matching: find.byType(ListView),
          ),
          findsNothing,
        );
        expect(find.text('Show all (7)'), findsOneWidget);

        await tester.tap(find.text('Logged Track 7'));
        await tester.pump();
        expect(playback.playSongCalls, equals(1));
        expect(playback.lastPlayedSong?.id, equals('log_7'));
      },
    );

    testWidgets(
      'UI-14 & UI-17: Landscape PlayerScreen switches to two-pane layout, dock caps width at 560dp, and Back returns to Home tab',
      (tester) async {
        await DatabaseService.saveCachedFeed('All:English', const [
          Song(id: 'tab_s1', title: 'Tab Song', artist: 'Artist', thumbnailUrl: ''),
        ]);

        final playback = _ReviewPlaybackProvider()
          ..seed(
            const Song(
              id: 'land_1',
              title: 'Landscape Anthem',
              artist: 'Arijit Singh',
              duration: 220,
              thumbnailUrl: '',
            ),
          );
        final library = LibraryProvider();

        // 1. Landscape PlayerScreen (915 x 412)
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(915, 412),
            playbackProvider: playback,
            libraryProvider: library,
            child: PlayerScreen(downloadService: DownloadService.forTesting()),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('player_landscape_two_pane')), findsOneWidget);

        // 2. Wide tablet MainScaffold (1024 x 768) -> dock capped <= 560dp & Back returns to Home
        await tester.pumpWidget(
          wrapViewport(
            tester: tester,
            size: const Size(1024, 768),
            playbackProvider: playback,
            libraryProvider: library,
            child: const MainScaffold(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(MiniPlayer)).width, lessThanOrEqualTo(560.0));

        await tester.tap(find.byTooltip('Settings'));
        await tester.pump();
        expect(find.text('APPEARANCE'), findsOneWidget);

        // System Back from Settings switches back to Home tab instead of popping root
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Quick Picks'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 11));
      },
    );
  });
}
