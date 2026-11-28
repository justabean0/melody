import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:melody/models/browse_result.dart';
import 'package:melody/models/lyrics.dart';
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
import 'package:melody/services/recommendation_service.dart';
import 'package:melody/ui/screens/collection_detail_screen.dart';
import 'package:melody/ui/screens/home_screen.dart';
import 'package:melody/ui/screens/player_screen.dart';
import 'package:melody/widgets/skeleton_loaders.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _jsonResponse(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class _QueueTestPlaybackProvider extends ChangeNotifier implements PlaybackProvider {
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  int clearQueueCalls = 0;

  void seed(
    Song song, {
    required List<Song> queue,
    int currentIndex = 0,
    Set<String> userQueuedIds = const {},
    Set<String> autoplayQueuedIds = const {},
  }) {
    _currentSong = song;
    _queue = List.of(queue);
    _currentIndex = currentIndex;
    _isPlaying = true;
    PlaybackProvider.userQueuedIdsByProvider[this] = Set<String>.from(userQueuedIds);
    PlaybackProvider.autoplayQueuedIdsByProvider[this] = Set<String>.from(autoplayQueuedIds);
    PlaybackProvider.reorderHandlerByProvider[this] = reorder;
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex <= _currentIndex || oldIndex >= _queue.length) return;
    if (newIndex <= _currentIndex || newIndex >= _queue.length) return;
    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);
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
  Duration get position => const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(seconds: 210);
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
  Future<void> playSong(
    Song song, {
    List<Song>? contextQueue,
    int? startIndex,
  }) async {
    _currentSong = song;
    _queue = contextQueue != null ? List.of(contextQueue) : [song];
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
  Future<void> playNext() async {
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      _currentSong = _queue[_currentIndex];
      notifyListeners();
    }
  }

  @override
  Future<void> playPrevious() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  void toggleShuffle() {}
  @override
  void cycleLoopMode() {}
  @override
  void setPlaybackSpeed(double speed) {}

  @override
  void addToQueue(Song song) {
    final idx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue = List.of(_queue)..insert(idx, song);
    PlaybackProvider.userQueuedIdsByProvider[this]?.add(song.id);
    notifyListeners();
  }

  @override
  void playNextInQueue(Song song) => addToQueue(song);

  @override
  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length && index != _currentIndex) {
      final removed = _queue[index];
      _queue = List.of(_queue)..removeAt(index);
      if (index < _currentIndex) _currentIndex--;
      PlaybackProvider.userQueuedIdsByProvider[this]?.remove(removed.id);
      PlaybackProvider.autoplayQueuedIdsByProvider[this]?.remove(removed.id);
      notifyListeners();
    }
  }

  @override
  void clearQueue() {
    clearQueueCalls++;
    PlaybackProvider.userQueuedIdsByProvider[this]?.clear();
    PlaybackProvider.autoplayQueuedIdsByProvider[this]?.clear();
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

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  final List<AudioSource> loadedSources = [];
  Future<void> Function()? onStop;
  Duration _currentPosition = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  bool _playing = false;

  void emitPosition(Duration pos) {
    _currentPosition = pos;
    _positionController.add(pos);
  }

  void emitState(bool playing, ProcessingState state) {
    _playing = playing;
    _processingState = state;
    _stateController.add(PlayerState(playing, state));
  }

  Future<void> closeStreams() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Duration get position => _currentPosition;
  @override
  Duration? get duration => const Duration(seconds: 210);
  @override
  ProcessingState get processingState => _processingState;
  @override
  bool get playing => _playing;
  @override
  double get speed => 1.0;
  @override
  bool get skipSilenceEnabled => false;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loadedSources.add(source);
    _currentPosition = initialPosition ?? Duration.zero;
    _processingState = ProcessingState.ready;
    _durationController.add(const Duration(seconds: 210));
    _stateController.add(PlayerState(_playing, ProcessingState.ready));
    return const Duration(seconds: 210);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _stateController.add(PlayerState(true, _processingState));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _stateController.add(PlayerState(false, _processingState));
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
    _playing = false;
    _processingState = ProcessingState.idle;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _currentPosition = position ?? Duration.zero;
    _positionController.add(_currentPosition);
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _drainHomeTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 11));
}

Widget _wrapHomeHarness({
  required WidgetTester tester,
  required Widget child,
  PlaybackProvider? playback,
  Size size = const Size(360, 780),
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final scheme = ThemeProvider.buildColorScheme(
    seed: const Color(0xFF8E24AA),
    brightness: brightness,
    pureBlack: brightness == Brightness.dark,
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackProvider>.value(
        value: playback ?? _QueueTestPlaybackProvider(),
      ),
      ChangeNotifierProvider<LibraryProvider>(create: (_) => LibraryProvider()),
      ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        home: child,
      ),
    ),
  );
}

List<Song> _sampleSongs(int count, {String prefix = 'track', String artistPrefix = 'Artist'}) {
  return List.generate(
    count,
    (i) => Song(
      id: '${prefix}_$i',
      title: 'Song $prefix $i',
      artist: '$artistPrefix $i',
      duration: 200,
      thumbnailUrl: '',
    ),
  );
}

Map<String, dynamic> _searchSongsJson(List<Song> songs) {
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
                        'contents': songs
                            .map(
                              (s) => {
                                'musicResponsiveListItemRenderer': {
                                  'playlistItemData': {'videoId': s.id},
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': s.title}
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': '${s.artist} • 3:20'}
                                          ]
                                        }
                                      }
                                    },
                                  ],
                                }
                              },
                            )
                            .toList(),
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
  };
}

Map<String, dynamic> _nextAndRelatedResponseJson({
  required List<Song> queueSongs,
  String? relatedBrowseId,
}) {
  return {
    'contents': {
      'singleColumnMusicWatchNextResultsRenderer': {
        'tabbedRenderer': {
          'watchNextTabbedResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'musicQueueRenderer': {
                      'content': {
                        'playlistPanelRenderer': {
                          'contents': queueSongs
                              .map(
                                (s) => {
                                  'playlistPanelVideoRenderer': {
                                    'videoId': s.id,
                                    'title': {
                                      'runs': [
                                        {'text': s.title}
                                      ]
                                    },
                                    'longBylineText': {
                                      'runs': [
                                        {'text': s.artist}
                                      ]
                                    },
                                  }
                                },
                              )
                              .toList(),
                        }
                      }
                    }
                  }
                }
              },
              if (relatedBrowseId != null)
                {
                  'tabRenderer': {
                    'endpoint': {
                      'browseEndpoint': {
                        'browseId': relatedBrowseId,
                        'browseEndpointContextSupportedConfigs': {
                          'browseEndpointContextMusicConfig': {
                            'pageType': 'MUSIC_PAGE_TYPE_TRACK_RELATED',
                          }
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
  };
}

Map<String, dynamic> _podcastBrowseResponseJson() {
  return {
    'contents': {
      'singleColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'musicCarouselShelfRenderer': {
                        'header': {
                          'musicCarouselShelfBasicHeaderRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Popular Shows'}
                              ]
                            }
                          }
                        },
                        'contents': [
                          {
                            'musicTwoRowItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Tech Talk Weekly'}
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Jane Host'}
                                ]
                              },
                              'navigationEndpoint': {
                                'browseEndpoint': {
                                  'browseId': 'MPSP_tech_talk',
                                  'browseEndpointContextSupportedConfigs': {
                                    'browseEndpointContextMusicConfig': {
                                      'pageType': 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE',
                                    }
                                  }
                                }
                              }
                            }
                          },
                          // Non-podcast music album/playlist must be strictly excluded
                          {
                            'musicTwoRowItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Summer Pop Album'}
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Pop Star'}
                                ]
                              },
                              'navigationEndpoint': {
                                'browseEndpoint': {
                                  'browseId': 'MPREb_pop_album',
                                  'browseEndpointContextSupportedConfigs': {
                                    'browseEndpointContextMusicConfig': {
                                      'pageType': 'MUSIC_PAGE_TYPE_ALBUM',
                                    }
                                  }
                                }
                              }
                            }
                          },
                        ]
                      }
                    },
                    {
                      'musicCarouselShelfRenderer': {
                        'header': {
                          'musicCarouselShelfBasicHeaderRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Popular Episodes'}
                              ]
                            }
                          }
                        },
                        'contents': [
                          {
                            'musicMultiRowListItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Deep Work Neuroscience'}
                                ]
                              },
                              'secondTitle': {
                                'runs': [
                                  {'text': 'Tech Talk Weekly'}
                                ]
                              },
                              'onTap': {
                                'watchEndpoint': {
                                  'videoId': 'pod_ep_1',
                                  'watchEndpointMusicSupportedConfigs': {
                                    'watchEndpointMusicConfig': {
                                      'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
                                    }
                                  }
                                }
                              },
                              'playbackProgress': {
                                'musicPlaybackProgressRenderer': {
                                  'durationText': {
                                    'runs': [
                                      {'text': ' • 2 hr 44 min'}
                                    ]
                                  }
                                }
                              }
                            }
                          },
                          // Music track inside shelf must be excluded
                          {
                            'musicMultiRowListItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Pop Song Trespasser'}
                                ]
                              },
                              'secondTitle': {
                                'runs': [
                                  {'text': 'Pop Band'}
                                ]
                              },
                              'onTap': {
                                'watchEndpoint': {
                                  'videoId': 'music_atv_99',
                                  'watchEndpointMusicSupportedConfigs': {
                                    'watchEndpointMusicConfig': {
                                      'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
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
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.melody.music/playback'),
      (_) async => true,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.init();
    await DatabaseService.clearHistory();
    await DatabaseService.setMusicLanguages(['English']);
    RecommendationService.clearCache();
    AntiBotService.reset();
    InnerTubeService.clientOverride = null;
  });

  tearDown(() {
    InnerTubeService.clientOverride = null;
  });

  group('1. Atomic Home Feed Caching & Parallel Load', () {
    test('DatabaseService persists and restores Quick Picks + Browse shelves atomically', () async {
      final songs = _sampleSongs(16, prefix: 'warm');
      const browse = [
        BrowseMediaItem(
          id: 'VL_feat',
          title: 'Top English Picks',
          subtitle: 'Chartbusters',
          thumbnailUrl: '',
          browseId: 'VL_feat',
          type: 'playlist',
        ),
        BrowseMediaItem(
          id: 'MPRE_alb',
          title: 'Midnights Album',
          subtitle: 'Taylor Swift',
          thumbnailUrl: '',
          browseId: 'MPRE_alb',
          type: 'album',
        ),
      ];

      await DatabaseService.saveCachedHomeFeed(
        'All:English',
        songs: songs,
        browseItems: browse,
        browseFallbackKey: 'lang:English',
      );

      final restored = DatabaseService.getCachedHomeFeed(
        'All:English',
        browseFallbackKey: 'lang:English',
      );
      expect(restored.songs.length, 16);
      expect(restored.browseItems.length, 2);
      expect(restored.browseItems.map((b) => b.title), ['Top English Picks', 'Midnights Album']);
      expect(restored.timestamp, isNotNull);
    });

    testWidgets('HomeScreen warm start renders Quick Picks, Featured & Trending, Albums, and More For You on first frame without late pop-in', (tester) async {
      final songs = _sampleSongs(18, prefix: 'atomic');
      const browse = [
        BrowseMediaItem(
          id: 'VL_pop',
          title: 'Global Hits Mix',
          subtitle: 'Featured Mix',
          thumbnailUrl: '',
          browseId: 'VL_pop',
          type: 'playlist',
        ),
        BrowseMediaItem(
          id: 'MPRE_pop',
          title: 'Neon Nights',
          subtitle: 'Synth Band',
          thumbnailUrl: '',
          browseId: 'MPRE_pop',
          type: 'album',
        ),
      ];

      await DatabaseService.saveCachedHomeFeed(
        'All:English',
        songs: songs,
        browseItems: browse,
        browseFallbackKey: 'lang:English',
      );

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          size: const Size(360, 1250),
          child: const HomeScreen(),
        ),
      );
      // Very first frame after initState restores all 4 sections atomically
      await tester.pump();

      expect(find.text('Quick Picks'), findsOneWidget);
      expect(find.text('Featured & Trending'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Global Hits Mix'), findsOneWidget);
      expect(find.text('Neon Nights'), findsOneWidget);
      expect(find.text('More For You'), findsOneWidget);

      final featuredRect = tester.getRect(find.text('Featured & Trending'));
      final albumsRect = tester.getRect(find.text('Albums'));
      final moreRect = tester.getRect(find.text('More For You'));
      expect(featuredRect.top, lessThan(albumsRect.top));
      expect(albumsRect.top, lessThan(moreRect.top));

      await _drainHomeTimers(tester);
    });

    testWidgets('HomeScreen cold start fetches Quick Picks and Browse concurrently before committing layout', (tester) async {
      final searchGate = Completer<void>();
      final browseGate = Completer<void>();
      bool browseStartedBeforeSearchCompleted = false;
      bool searchFinished = false;

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_1\"]]]", 200);
        }
        if (request.method != 'POST') return _jsonResponse({});
        final path = request.url.path;

        if (path.contains('browse')) {
          if (!searchFinished) {
            browseStartedBeforeSearchCompleted = true;
          }
          await browseGate.future;
          return _jsonResponse({
            'contents': {
              'singleColumnBrowseResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'musicCarouselShelfRenderer': {
                                'header': {
                                  'musicCarouselShelfBasicHeaderRenderer': {
                                    'title': {
                                      'runs': [
                                        {'text': 'Featured Playlists'}
                                      ]
                                    }
                                  }
                                },
                                'contents': [
                                  {
                                    'musicTwoRowItemRenderer': {
                                      'title': {
                                        'runs': [
                                          {'text': 'English Acoustic Gold'}
                                        ]
                                      },
                                      'subtitle': {
                                        'runs': [
                                          {'text': 'Playlist'}
                                        ]
                                      },
                                      'navigationEndpoint': {
                                        'browseEndpoint': {'browseId': 'VL_cold_feat'}
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
          });
        }

        if (path.contains('search')) {
          await searchGate.future;
          searchFinished = true;
          return _jsonResponse(_searchSongsJson(_sampleSongs(18, prefix: 'cold')));
        }
        return _jsonResponse({});
      });

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          size: const Size(360, 1250),
          child: const HomeScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      searchGate.complete();
      browseGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(browseStartedBeforeSearchCompleted, isTrue);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.text('Quick Picks'), findsOneWidget);
      expect(find.text('Featured & Trending'), findsOneWidget);
      expect(find.text('More For You'), findsOneWidget);

      await _drainHomeTimers(tester);
    });
  });

  group('2. Removed Play All, Skeleton Bone & Stray Reload Spinner', () {
    testWidgets('HomeScreen pull-to-refresh shows HomeFeedSkeleton without Play all or overlapping CircularProgressIndicator', (tester) async {
      await DatabaseService.saveCachedHomeFeed(
        'All:English',
        songs: _sampleSongs(18, prefix: 'pull'),
        browseItems: const [
          BrowseMediaItem(
            id: 'VL_1',
            title: 'Pop Replay',
            subtitle: 'Mix',
            thumbnailUrl: '',
            browseId: 'VL_1',
            type: 'playlist',
          ),
        ],
        browseFallbackKey: 'lang:English',
      );

      final refreshGate = Completer<void>();
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_1\"]]]", 200);
        }
        await refreshGate.future;
        if (request.url.path.contains('search')) {
          return _jsonResponse(_searchSongsJson(_sampleSongs(18, prefix: 'refreshed')));
        }
        return _jsonResponse({});
      });

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          child: const HomeScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Play all'), findsNothing);

      // Drag down past RefreshIndicator displacement threshold and let the 200ms snap trigger onRefresh
      await tester.drag(find.byKey(const ValueKey('home_content')), const Offset(0, 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      // Zero stray RefreshIndicator / spinner floating over the skeleton
      expect(find.byType(CircularProgressIndicator), findsNothing);

      refreshGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.text('Song refreshed 0'), findsOneWidget);

      await _drainHomeTimers(tester);
    });
  });

  group('3. Dedicated Podcasts Mode', () {
    test('InnerTubeService parses podcast shows/episodes strictly and parses abbreviated durations', () async {
      expect(InnerTubeService.parseNaturalLanguageDuration('2 hr 44 min'), 9840);
      expect(InnerTubeService.parseDuration(' • 2 hr 44 min'), 9840);

      final parsed = InnerTubeService.parsePodcastsBrowseResponse(_podcastBrowseResponseJson());
      expect(parsed.shows.length, 1);
      expect(parsed.shows.first.browseId, 'MPSP_tech_talk');
      expect(parsed.shows.first.type, 'podcast');

      expect(parsed.episodes.length, 1);
      expect(parsed.episodes.first.id, 'pod_ep_1');
      expect(parsed.episodes.first.isPodcast, isTrue);
      expect(parsed.episodes.first.duration, 9840);
      expect(parsed.episodes.any((e) => e.id == 'music_atv_99'), isFalse);

      // Podcast show browse + playback flag
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_pod\"]]]", 200);
        }
        return _jsonResponse({
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
                                  {'text': 'Tech Talk Weekly'}
                                ]
                              },
                              'straplineTextOne': {
                                'runs': [
                                  {'text': 'Jane Host'}
                                ]
                              },
                              'description': {
                                'musicDescriptionShelfRenderer': {
                                  'description': {
                                    'runs': [
                                      {'text': 'Engineering conversations'}
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
                      'musicShelfRenderer': {
                        'contents': [
                          {
                            'musicMultiRowListItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Episode 101: Compilers'}
                                ]
                              },
                              'secondTitle': {
                                'runs': [
                                  {'text': 'Tech Talk Weekly'}
                                ]
                              },
                              'onTap': {
                                'watchEndpoint': {
                                  'videoId': 'ep_101',
                                  'watchEndpointMusicSupportedConfigs': {
                                    'watchEndpointMusicConfig': {
                                      'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
                                    }
                                  }
                                }
                              },
                              'playbackProgress': {
                                'musicPlaybackProgressRenderer': {
                                  'durationText': {
                                    'runs': [
                                      {'text': '45 min'}
                                    ]
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
        });
      });

      final show = await InnerTubeService.browsePodcastShow('MPSP_tech_talk');
      expect(show, isNotNull);
      expect(show!.browseId, 'MPSP_tech_talk');
      expect(show.title, 'Tech Talk Weekly');
      expect(show.songs.length, 1);
      expect(show.songs.first.isPodcast, isTrue);
      expect(show.songs.first.duration, 2700);
    });

    testWidgets('HomeScreen Podcasts chip fits 360dp / 1.4x & 1.8x cleanly, hides music sections, shows PodcastsFeedSkeleton, and retries offline', (tester) async {
      await DatabaseService.saveCachedHomeFeed(
        'All:English',
        songs: _sampleSongs(16, prefix: 'music'),
        browseItems: const [
          BrowseMediaItem(
            id: 'VL_m',
            title: 'Music Mix',
            subtitle: 'Mix',
            thumbnailUrl: '',
            browseId: 'VL_m',
            type: 'playlist',
          ),
        ],
        browseFallbackKey: 'lang:English',
      );

      final podGate = Completer<void>();
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_pod\"]]]", 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['browseId'] as String?) == 'FEmusic_podcasts') {
          await podGate.future;
          return _jsonResponse(_podcastBrowseResponseJson());
        }
        return _jsonResponse({});
      });

      // Verify chip layout at 1.8x accessibility scale with zero overflow
      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          textScale: 1.8,
          child: const HomeScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Podcasts'), findsOneWidget);

      // Re-test at 1.4x and tap Podcasts
      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          textScale: 1.4,
          child: const HomeScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final allRect = tester.getRect(find.text('All'));
      final podcastsRect = tester.getRect(find.text('Podcasts'));
      expect(podcastsRect.left, greaterThan(allRect.right));
      expect(podcastsRect.right, lessThanOrEqualTo(360.0));
      final podcastsChip = find.ancestor(
        of: find.text('Podcasts'),
        matching: find.byType(FilterChip),
      );
      expect(
        find.descendant(of: podcastsChip, matching: find.byType(Icon)),
        findsNothing,
      );

      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PodcastsFeedSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      podGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(PodcastsFeedSkeleton), findsNothing);
      expect(find.text('Podcast Shows'), findsOneWidget);
      expect(find.text('Tech Talk Weekly'), findsWidgets);
      expect(find.text('Podcast Episodes'), findsOneWidget);
      expect(find.text('Deep Work Neuroscience'), findsOneWidget);
      // Music sections strictly hidden
      expect(find.text('Quick Picks'), findsNothing);
      expect(find.text('Featured & Trending'), findsNothing);
      expect(find.text('Albums'), findsNothing);
      expect(find.text('More For You'), findsNothing);
      expect(find.text('Music Mix'), findsNothing);

      await _drainHomeTimers(tester);
    });

    testWidgets('HomeScreen Podcasts mode shows Retry offline (>= 48dp touch target) and recovers when retried', (tester) async {
      await DatabaseService.saveCachedHomeFeed(
        'All:English',
        songs: _sampleSongs(16, prefix: 'music'),
        browseItems: const [],
        browseFallbackKey: 'lang:English',
      );

      bool failPodcast = true;
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_pod\"]]]", 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['browseId'] as String?) == 'FEmusic_podcasts') {
          if (failPodcast) return _jsonResponse({}, 500);
          return _jsonResponse(_podcastBrowseResponseJson());
        }
        return _jsonResponse({});
      });

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          textScale: 1.4,
          child: const HomeScreen(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Unable to load podcasts'), findsOneWidget);
      final retryBtn = find.text('Retry');
      expect(retryBtn, findsOneWidget);
      final retryControl = find.ancestor(
        of: retryBtn,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(retryControl).height, greaterThanOrEqualTo(48));

      failPodcast = false;
      await tester.tap(retryBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Podcast Shows'), findsOneWidget);

      await _drainHomeTimers(tester);
    });

    testWidgets('CollectionDetailScreen opens podcast show and plays episode with isPodcast = true', (tester) async {
      final playback = _QueueTestPlaybackProvider();
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_pod\"]]]", 200);
        }
        return _jsonResponse({
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
                                  {'text': 'Science Dispatch'}
                                ]
                              },
                              'straplineTextOne': {
                                'runs': [
                                  {'text': 'Dr. Alex'}
                                ]
                              },
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
                      'musicShelfRenderer': {
                        'contents': [
                          {
                            'musicMultiRowListItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Episode 1: Memory'}
                                ]
                              },
                              'secondTitle': {
                                'runs': [
                                  {'text': 'Science Dispatch'}
                                ]
                              },
                              'onTap': {
                                'watchEndpoint': {
                                  'videoId': 'pod_ep_mem',
                                  'watchEndpointMusicSupportedConfigs': {
                                    'watchEndpointMusicConfig': {
                                      'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
                                    }
                                  }
                                }
                              },
                              'playbackProgress': {
                                'musicPlaybackProgressRenderer': {
                                  'durationText': {
                                    'runs': [
                                      {'text': '32 min'}
                                    ]
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
        });
      });

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          playback: playback,
          child: const CollectionDetailScreen(
            browseId: 'MPSP_science',
            isAlbum: false,
            isPodcast: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Podcast'), findsOneWidget);
      expect(find.text('Episodes'), findsOneWidget);
      expect(find.text('1 episode'), findsOneWidget);
      expect(find.text('Episode 1: Memory'), findsOneWidget);

      await tester.tap(find.text('Episode 1: Memory'));
      await tester.pump();
      expect(playback.currentSong?.id, 'pod_ep_mem');
      expect(playback.currentSong?.isPodcast, isTrue);
    });
  });

  group('4 & 5. Reworked Quick Picks & Entry-Gate Language Behavior', () {
    test('diversifyAndCapQuickPicks suppresses active song versions, deduplicates remixes, and caps 2 per artist', () {
      const active = Song(
        id: 'active_1',
        title: 'Midnight Rain',
        artist: 'Taylor Swift',
        thumbnailUrl: '',
      );

      final candidates = [
        active,
        const Song(id: 'active_remix', title: 'Midnight Rain (Remix)', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'active_live', title: 'Midnight Rain - Live', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'ts_1', title: 'Cruel Summer', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'ts_1_dupe', title: 'Cruel Summer (Acoustic)', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'ts_2', title: 'Anti-Hero', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'ts_3', title: 'Blank Space', artist: 'Taylor Swift', thumbnailUrl: ''),
        const Song(id: 'other_1', title: 'Vampire', artist: 'Olivia Rodrigo', thumbnailUrl: ''),
        const Song(id: 'other_2', title: 'Bad Idea Right?', artist: 'Olivia Rodrigo', thumbnailUrl: ''),
        const Song(id: 'other_3', title: 'Drivers License', artist: 'Olivia Rodrigo', thumbnailUrl: ''),
      ];

      final diversified = RecommendationService.diversifyAndCapQuickPicks(
        candidates,
        activeSong: active,
        maxPerArtist: 2,
      );

      expect(diversified.any((s) => s.title.toLowerCase().contains('midnight rain')), isFalse);
      expect(diversified.where((s) => s.artist == 'Taylor Swift').length, 2);
      expect(diversified.where((s) => s.artist == 'Olivia Rodrigo').length, 2);
      expect(diversified.map((s) => s.id), containsAll(['ts_1', 'ts_2', 'other_1', 'other_2']));
      expect(diversified.map((s) => s.id), isNot(contains('ts_3')));
      expect(diversified.map((s) => s.id), isNot(contains('ts_1_dupe')));
    });

    test('Quick Picks re-seeds via RDAMVM + MPTRt_ when liked track is added and permits French earned taste while blocking unseeded bleed', () async {
      await DatabaseService.setMusicLanguages(['English']);

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"visitor_taste\"]]]", 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('next')) {
          return _jsonResponse(
            _nextAndRelatedResponseJson(
              queueSongs: const [
                Song(id: 'fr_sim_1', title: 'Formidable', artist: 'Stromae', thumbnailUrl: ''),
                Song(id: 'fr_sim_2', title: 'Je Veux', artist: 'Zaz', thumbnailUrl: ''),
              ],
              relatedBrowseId: 'MPTRt_french_rel',
            ),
          );
        }

        if (path.contains('browse') && body['browseId'] == 'MPTRt_french_rel') {
          return _jsonResponse({
            'contents': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicCarouselShelfRenderer': {
                      'header': {
                        'musicCarouselShelfBasicHeaderRenderer': {
                          'title': {
                            'runs': [
                              {'text': 'You might also like'}
                            ]
                          }
                        }
                      },
                      'contents': [
                        {
                          'musicTwoRowItemRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Tourner Dans Le Vide'}
                              ]
                            },
                            'subtitle': {
                              'runs': [
                                {'text': 'Indila'}
                              ]
                            },
                            'navigationEndpoint': {
                              'watchEndpoint': {'videoId': 'fr_rel_indila'}
                            }
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          });
        }

        if (path.contains('search')) {
          return _jsonResponse(_searchSongsJson([
            const Song(id: 'eng_1', title: 'Levitating', artist: 'Dua Lipa', thumbnailUrl: ''),
            // Unseeded French & Spanish tracks in generic chart/search bleed
            const Song(id: 'fr_bleed', title: 'Dernière Danse', artist: 'Indila', thumbnailUrl: ''),
            const Song(id: 'es_bleed', title: 'Ella Quiere Beber', artist: 'Anuel AA', thumbnailUrl: ''),
          ]));
        }
        return _jsonResponse({});
      });

      // 1. Cold start: French & Spanish bleed blocked
      final initialPicks = await InnerTubeService.getQuickPicks(languages: ['English']);
      expect(initialPicks.map((s) => s.id), contains('eng_1'));
      expect(initialPicks.map((s) => s.id), isNot(contains('fr_bleed')));
      expect(initialPicks.map((s) => s.id), isNot(contains('es_bleed')));

      // 2. User explicitly likes a French song -> tasteVersion increments, cache invalidates, and French recommendations appear!
      const frenchLiked = Song(
        id: 'fr_seed_1',
        title: 'Dernière Danse',
        artist: 'Indila',
        duration: 213,
        thumbnailUrl: '',
      );
      await DatabaseService.toggleLike(frenchLiked);

      final earnedPicks = await InnerTubeService.getQuickPicks(
        languages: ['English'],
        activeSong: frenchLiked,
      );
      expect(earnedPicks.map((s) => s.id), containsAll(['fr_rel_indila', 'fr_sim_1', 'fr_sim_2']));
      expect(earnedPicks.map((s) => s.id), isNot(contains('fr_seed_1')));
    });
  });

  group('6. Smart Autoplay Mix & Queue-at-Top Behavior', () {
    test('RecommendationService.buildAutoplayMix balances related & same artist, prevents back-to-back repeats, and keeps unselected-language seeds', () {
      const frenchSeed = Song(
        id: 'fr_0',
        title: 'Dernière Danse',
        artist: 'Indila',
        thumbnailUrl: '',
      );

      final candidates = [
        // Duplicates / excluded session track
        frenchSeed,
        const Song(id: 'fr_0_remix', title: 'Dernière Danse (Slowed & Reverb)', artist: 'Indila', thumbnailUrl: ''),
        const Song(id: 'fr_played', title: 'Papaoutai', artist: 'Stromae', thumbnailUrl: ''),
        // Same artist tracks
        const Song(id: 'ind_2', title: 'Tourner Dans Le Vide', artist: 'Indila', thumbnailUrl: ''),
        const Song(id: 'ind_3', title: 'Love Story', artist: 'Indila', thumbnailUrl: ''),
        // Related French artists
        const Song(id: 'rel_1', title: 'Alors On Danse', artist: 'Stromae', thumbnailUrl: ''),
        const Song(id: 'rel_2', title: 'Je Veux', artist: 'Zaz', thumbnailUrl: ''),
        const Song(id: 'rel_3', title: 'Bruxelles je t aime', artist: 'Angèle', thumbnailUrl: ''),
      ];

      final mix = RecommendationService.buildAutoplayMix(
        seedSong: frenchSeed,
        candidates: candidates,
        excludeIds: {'fr_played'},
        limit: 6,
      );

      expect(mix.map((s) => s.id), isNot(contains('fr_0')));
      expect(mix.map((s) => s.id), isNot(contains('fr_0_remix')));
      expect(mix.map((s) => s.id), isNot(contains('fr_played')));
      // Must mix both related artists and same-artist tracks
      expect(mix.any((s) => s.artist == 'Indila'), isTrue);
      expect(mix.any((s) => s.artist == 'Stromae' || s.artist == 'Zaz'), isTrue);
      // First autoplay track should NOT repeat the just-played artist
      expect(mix.first.artist, isNot('Indila'));
      // No back-to-back same artist when other artists are available
      for (int i = 1; i < mix.length; i++) {
        if (i < 4) {
          expect(mix[i].artist, isNot(mix[i - 1].artist));
        }
      }
    });

    test('MelodyAudioService.addToQueue inserts at currentIndex + 1 ahead of autoplay, prefetches, and advances queued -> autoplay on track end', () async {
      final tempFile = File('${Directory.systemTemp.path}/melody_test_silent.m4a');
      await tempFile.writeAsBytes(const [0, 1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      });

      final fakePlayer = _FakeAudioPlayer();
      final audio = MelodyAudioService.forTesting(player: fakePlayer);
      addTearDown(() async {
        audio.dispose();
        await fakePlayer.closeStreams();
      });

      final s0 = Song(id: 's0', title: 'Current Track', artist: 'Artist A', duration: 200, thumbnailUrl: '', localUri: tempFile.path);
      final q1 = Song(id: 'q1', title: 'User Queued Track', artist: 'Artist Q', duration: 190, thumbnailUrl: '', localUri: tempFile.path);
      final a1 = Song(id: 'a1', title: 'Similar Autoplay 1', artist: 'Artist B', duration: 210, thumbnailUrl: '', localUri: tempFile.path);
      final a2 = Song(id: 'a2', title: 'Same Artist Autoplay 2', artist: 'Artist A', duration: 205, thumbnailUrl: '', localUri: tempFile.path);

      int prefetchCalls = 0;
      audio.autoplayFetcherOverride = (
        seed, {
        excludeIds = const {},
        excludeNormalizedKeys = const {},
      }) async {
        prefetchCalls++;
        return [a1, a2];
      };

      // 1. Seed current track and transition via playNext/seed so autoplay prefetches cleanly
      audio.seedQueueForTesting([s0]);
      expect(audio.currentSong?.id, 's0');

      // Track finishes -> auto-populates autoplay mix [a1, a2] and advances to a1
      await audio.handleTrackEndedForTesting();
      expect(prefetchCalls, greaterThanOrEqualTo(1));
      expect(audio.currentSong?.id, 'a1');
      expect(audio.queue.map((s) => s.id), ['s0', 'a1', 'a2']);
      expect(audio.isAutoplayQueued('a2'), isTrue);

      // 2. Add to Queue inserts Q1 at currentIndex + 1 ahead of autoplay track a2!
      audio.addToQueue(q1);
      expect(audio.queue.map((s) => s.id), ['s0', 'a1', 'q1', 'a2']);
      expect(audio.isUserQueued('q1'), isTrue);
      expect(audio.isAutoplayQueued('a2'), isTrue);

      // 3. Reorder queue updates order cleanly
      audio.reorderQueue(3, 2);
      expect(audio.queue.map((s) => s.id), ['s0', 'a1', 'a2', 'q1']);
      audio.reorderQueue(3, 2);
      expect(audio.queue.map((s) => s.id), ['s0', 'a1', 'q1', 'a2']);

      // 4. When current track finishes, user-queued q1 plays FIRST, then autoplay a2
      await audio.handleTrackEndedForTesting();
      expect(audio.currentSong?.id, 'q1');
      expect(audio.isUserQueued('q1'), isFalse);

      await audio.handleTrackEndedForTesting();
      expect(audio.currentSong?.id, 'a2');
    });

    test('duplicate ProcessingState.completed during player.stop() teardown never skips the next queued track', () async {
      final tempFile = File('${Directory.systemTemp.path}/melody_test_race.m4a');
      await tempFile.writeAsBytes(const [0, 1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      });

      final fakePlayer = _FakeAudioPlayer();
      final audio = MelodyAudioService.forTesting(player: fakePlayer);
      audio.init();
      addTearDown(() async {
        audio.dispose();
        await fakePlayer.closeStreams();
      });

      final s0 = Song(id: 's0', title: 'Track Zero', artist: 'Artist 0', duration: 200, thumbnailUrl: '', localUri: tempFile.path);
      final q1 = Song(id: 'q1', title: 'Queued First', artist: 'Artist Q', duration: 190, thumbnailUrl: '', localUri: tempFile.path);
      final a1 = Song(id: 'a1', title: 'Autoplay Second', artist: 'Artist A', duration: 210, thumbnailUrl: '', localUri: tempFile.path);

      audio.seedQueueForTesting([s0, a1]);
      audio.addToQueue(q1);
      expect(audio.queue.map((s) => s.id), ['s0', 'q1', 'a1']);

      // Simulate ExoPlayer near track end and emitting a trailing (false, completed) during stop()
      fakePlayer.emitPosition(const Duration(seconds: 200));
      fakePlayer.onStop = () async {
        fakePlayer.emitState(false, ProcessingState.completed);
        await Future<void>.delayed(Duration.zero);
      };

      fakePlayer.emitState(true, ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(audio.currentSong?.id, 'q1');
      expect(audio.currentIndex, 1);
    });

    testWidgets('PlayerScreen Queue sheet renders Queued badge at top ahead of Autoplay, updates on swipe-remove, and Clear Queue clears upcoming', (tester) async {
      const s0 = Song(id: 'p_now', title: 'Now Track', artist: 'Artist One', duration: 180, thumbnailUrl: '');
      const qTop = Song(id: 'p_q', title: 'Queued Top Track', artist: 'Artist Two', duration: 190, thumbnailUrl: '');
      const aNext = Song(id: 'p_auto', title: 'Autoplay Similar Track', artist: 'Artist Three', duration: 200, thumbnailUrl: '');

      final playback = _QueueTestPlaybackProvider()
        ..seed(
          s0,
          queue: const [s0, qTop, aNext],
          currentIndex: 0,
          userQueuedIds: const {'p_q'},
          autoplayQueuedIds: const {'p_auto'},
        );

      await tester.pumpWidget(
        _wrapHomeHarness(
          tester: tester,
          playback: playback,
          child: PlayerScreen(downloadService: DownloadService.forTesting()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('player_queue_button')));
      await tester.pumpAndSettle();

      expect(find.text('Up Next (2 tracks)'), findsOneWidget);
      expect(find.text('Now Playing'), findsWidgets);
      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Autoplay'), findsOneWidget);

      final queuedRect = tester.getRect(find.text('Queued Top Track'));
      final autoplayRect = tester.getRect(find.text('Autoplay Similar Track'));
      expect(queuedRect.top, lessThan(autoplayRect.top));

      // Swipe-remove queued item
      await tester.drag(find.byKey(const ValueKey('queue_p_q_1')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Queued Top Track'), findsNothing);
      expect(find.text('Autoplay Similar Track'), findsOneWidget);

      // Clear Queue removes remaining upcoming tracks
      await tester.tap(find.text('Clear Queue'));
      await tester.pumpAndSettle();
      expect(playback.clearQueueCalls, 1);
      expect(find.text('Autoplay Similar Track'), findsNothing);
      expect(find.text('Up Next'), findsOneWidget);
    });
  });
}
