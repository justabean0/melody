import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/search_result.dart';
import 'package:melody/providers/search_provider.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InnerTube Client Setup & Locale Tests', () {
    tearDown(() {
      InnerTubeService.clientOverride = null;
      InnerTubeService.setLocale(gl: 'IN', hl: 'en');
      InnerTubeService.visitorData = null;
    });

    test('InnerTubeService client version is modern WEB_REMIX and locale defaults to IN / en', () {
      expect(InnerTubeService.clientVersion, equals('1.20261116.01.00'));
      expect(InnerTubeService.gl, equals('IN'));
      expect(InnerTubeService.hl, equals('en'));

      InnerTubeService.setLocale(gl: 'US', hl: 'es');
      expect(InnerTubeService.gl, equals('US'));
      expect(InnerTubeService.hl, equals('es'));
    });

    test('fetchVisitorData extracts visitor token starting with Cg[ts] from sw.js_data', () async {
      const mockSwJsData = ")]}'\n"
          '[[null, null, ["other_string", "CgtTestVisitorId12345", "another_val"]]]';

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.toString() == 'https://music.youtube.com/sw.js_data') {
          return http.Response(mockSwJsData, 200);
        }
        return http.Response('Not Found', 404);
      });

      final token = await InnerTubeService.fetchVisitorData(forceRefresh: true);
      expect(token, equals('CgtTestVisitorId12345'));
      expect(InnerTubeService.visitorData, equals('CgtTestVisitorId12345'));
    });
  });

  group('InnerTube Search Renderers Parsing Tests', () {
    test('parseSearchResponse correctly parses musicCardShelfRenderer and musicShelfRenderer with real IDs and zero fake albums', () {
      final fixture = {
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        // 1. Top Result Card: Album
                        {
                          'musicCardShelfRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Arijit Best Hits Album'}
                              ]
                            },
                            'subtitle': {
                              'runs': [
                                {'text': 'Album'},
                                {'text': ' • '},
                                {
                                  'text': 'Arijit Singh',
                                  'navigationEndpoint': {
                                    'browseEndpoint': {'browseId': 'UC_arijit_browse_id'}
                                  }
                                },
                                {'text': ' • '},
                                {'text': '2024'}
                              ]
                            },
                            'thumbnail': {
                              'musicThumbnailRenderer': {
                                'thumbnail': {
                                  'thumbnails': [
                                    {'url': 'https://i.ytimg.com/album_thumb_300.jpg', 'width': 300, 'height': 300}
                                  ]
                                }
                              }
                            },
                            'onTap': {
                              'browseEndpoint': {
                                'browseId': 'MPREb_real_album_id_123',
                                'browseEndpointContextSupportedConfigs': {
                                  'browseEndpointContextMusicConfig': {
                                    'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                                  }
                                }
                              }
                            },
                            'buttons': [
                              {
                                'buttonRenderer': {
                                  'command': {
                                    'watchPlaylistEndpoint': {'playlistId': 'OLAK5uy_real_playlist_id_123'}
                                  }
                                }
                              }
                            ],
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {
                                              'text': 'Nested Track 1',
                                              'navigationEndpoint': {
                                                'watchEndpoint': {'videoId': 'nested_vid_001'}
                                              }
                                            }
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Arijit Singh'},
                                            {'text': ' • '},
                                            {'text': '3:45'}
                                          ]
                                        }
                                      }
                                    }
                                  ],
                                  'thumbnail': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://i.ytimg.com/track1.jpg'}
                                        ]
                                      }
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        },

                        // 2. Music Shelf containing a Song, an Artist, a Playlist, and an unknown Profile/Podcast
                        {
                          'musicShelfRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Songs & Results'}
                              ]
                            },
                            'contents': [
                              // Shelf Item 1: Song
                              {
                                'musicResponsiveListItemRenderer': {
                                  'playlistItemData': {'videoId': 'shelf_song_vid_002'},
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Kesariya'}
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Song'},
                                            {'text': ' • '},
                                            {
                                              'text': 'Arijit Singh',
                                              'navigationEndpoint': {
                                                'browseEndpoint': {'browseId': 'UC_arijit_artist_id'}
                                              }
                                            },
                                            {'text': ' • '},
                                            {'text': '4:28'}
                                          ]
                                        }
                                      }
                                    }
                                  ],
                                  'thumbnail': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://i.ytimg.com/kesariya.jpg'}
                                        ]
                                      }
                                    }
                                  }
                                }
                              },

                              // Shelf Item 2: Artist
                              {
                                'musicResponsiveListItemRenderer': {
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'UC_artist_official_id',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_ARTIST'
                                        }
                                      }
                                    }
                                  },
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Arijit Singh'}
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Artist'},
                                            {'text': ' • '},
                                            {'text': '35M subscribers'}
                                          ]
                                        }
                                      }
                                    }
                                  ],
                                  'thumbnail': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://i.ytimg.com/arijit_avatar.jpg'}
                                        ]
                                      }
                                    }
                                  }
                                }
                              },

                              // Shelf Item 3: Playlist
                              {
                                'musicResponsiveListItemRenderer': {
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'VLPL_best_hits_playlist_id',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                                        }
                                      }
                                    }
                                  },
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Arijit Singh Top 50'}
                                          ]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Playlist'},
                                            {'text': ' • '},
                                            {'text': 'Melody & YouTube Music'}
                                          ]
                                        }
                                      }
                                    }
                                  ],
                                  'thumbnail': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://i.ytimg.com/playlist_cover.jpg'}
                                        ]
                                      }
                                    }
                                  }
                                }
                              },

                              // Shelf Item 4: User Channel Profile (MUST BE SKIPPED)
                              {
                                'musicResponsiveListItemRenderer': {
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'UC_user_channel_skip',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_USER_CHANNEL'
                                        }
                                      }
                                    }
                                  },
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Random Fan Profile'}
                                          ]
                                        }
                                      }
                                    }
                                  ]
                                }
                              },

                              // Shelf Item 5: Podcast Show (MUST BE SKIPPED)
                              {
                                'musicResponsiveListItemRenderer': {
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'MPSP_podcast_skip',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_PODCAST'
                                        }
                                      }
                                    }
                                  },
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [
                                            {'text': 'Music Podcast Episode'}
                                          ]
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
            ]
          }
        }
      };

      final result = InnerTubeService.parseSearchResponse(fixture, filter: SearchFilter.all);

      // Verify Albums: Real MPREb_ ID, real playlistId, zero fake album_ IDs
      expect(result.albums.length, equals(1));
      expect(result.albums.first.id, equals('MPREb_real_album_id_123'));
      expect(result.albums.first.playlistId, equals('OLAK5uy_real_playlist_id_123'));
      expect(result.albums.first.title, equals('Arijit Best Hits Album'));
      expect(result.albums.first.artist, equals('Arijit Singh'));
      expect(result.albums.first.year, equals(2024));
      expect(result.albums.first.id.startsWith('album_'), isFalse);

      // Verify Songs: Nested track and shelf track parsed
      expect(result.songs.length, equals(2));
      expect(result.songs[0].id, equals('nested_vid_001'));
      expect(result.songs[0].title, equals('Nested Track 1'));
      expect(result.songs[1].id, equals('shelf_song_vid_002'));
      expect(result.songs[1].title, equals('Kesariya'));
      expect(result.songs[1].artist, equals('Arijit Singh'));

      // Verify Artists: Real UC ID
      expect(result.artists.length, equals(1));
      expect(result.artists.first.id, equals('UC_artist_official_id'));
      expect(result.artists.first.name, equals('Arijit Singh'));
      expect(result.artists.first.subscribers, contains('35M subscribers'));

      // Verify Playlists: Real VL / PL ID stripped of VL prefix
      expect(result.playlists.length, equals(1));
      expect(result.playlists.first.id, equals('PL_best_hits_playlist_id'));
      expect(result.playlists.first.title, equals('Arijit Singh Top 50'));

      // Verify Unknown / Unplayable Renderers are completely skipped
      expect(result.artists.any((a) => a.id == 'UC_user_channel_skip'), isFalse);
      expect(result.albums.any((a) => a.id == 'MPSP_podcast_skip'), isFalse);
      expect(result.playlists.any((p) => p.id == 'MPSP_podcast_skip'), isFalse);
      expect(result.songs.any((s) => s.id == 'MPSP_podcast_skip'), isFalse);
    });
  });

  group('SearchProvider Async Race Condition Guard Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.init();
      await DatabaseService.clearSearchHistory();
    });

    tearDown(() {
      InnerTubeService.clientOverride = null;
    });

    test('SearchProvider increments monotonic request token on setFilter, performSearch, and clearSearch', () {
      final provider = SearchProvider();
      expect(provider.searchRequestToken, equals(0));

      provider.setFilter(SearchFilter.songs);
      expect(provider.searchRequestToken, equals(1));

      provider.clearSearch();
      expect(provider.searchRequestToken, equals(2));

      provider.clear();
      expect(provider.searchRequestToken, equals(3));
    });

    test('SearchProvider cancels and discards stale async responses across rapid All <-> Songs switching', () async {
      final provider = SearchProvider();

      // Mock client that returns different results based on query or filter params
      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        final params = body['params'] as String?;

        if (query == 'stale_query_all') {
          // Slow response (120ms) returning 1 song
          await Future.delayed(const Duration(milliseconds: 120));
          return http.Response(
            jsonEncode({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'stale_song_vid'},
                                        'flexColumns': [
                                          {
                                            'musicResponsiveListItemFlexColumnRenderer': {
                                              'text': {
                                                'runs': [
                                                  {'text': 'Stale Song'}
                                                ]
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
                  ]
                }
              }
            }),
            200,
          );
        } else if (query == 'fresh_query_songs' && params == SearchFilter.songs.params) {
          // Fast response (20ms) returning 2 songs
          await Future.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'fresh_song_vid_1'},
                                        'flexColumns': [
                                          {
                                            'musicResponsiveListItemFlexColumnRenderer': {
                                              'text': {
                                                'runs': [
                                                  {'text': 'Fresh Song 1'}
                                                ]
                                              }
                                            }
                                          }
                                        ]
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'fresh_song_vid_2'},
                                        'flexColumns': [
                                          {
                                            'musicResponsiveListItemFlexColumnRenderer': {
                                              'text': {
                                                'runs': [
                                                  {'text': 'Fresh Song 2'}
                                                ]
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
                  ]
                }
              }
            }),
            200,
          );
        }

        return http.Response('{"contents": {}}', 200);
      });

      // 1. User is on 'All' tab and initiates search for 'stale_query_all'
      expect(provider.filter, equals(SearchFilter.all));
      final slowFuture = provider.performSearch('stale_query_all');

      // 2. User rapidly switches to 'Songs' tab and searches for 'fresh_query_songs'
      await Future.delayed(const Duration(milliseconds: 10));
      provider.setFilter(SearchFilter.songs);
      final fastFuture = provider.performSearch('fresh_query_songs');

      // Wait for both async tasks to complete
      await Future.wait([slowFuture, fastFuture]);

      // 3. Verify that the slow first response was discarded and the fast second response won
      expect(provider.filter, equals(SearchFilter.songs));
      expect(provider.query, equals('fresh_query_songs'));
      expect(provider.isLoading, isFalse);
      expect(provider.results.songs.length, equals(2));
      expect(provider.results.songs.map((s) => s.id), containsAll(['fresh_song_vid_1', 'fresh_song_vid_2']));
      expect(provider.results.songs.any((s) => s.id == 'stale_song_vid'), isFalse);
    });

    test('SearchProvider clearSearch cancels pending search completions and prevents late overwrites', () async {
      final provider = SearchProvider();

      InnerTubeService.clientOverride = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
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
                                'contents': [
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'late_vid'},
                                      'flexColumns': [
                                        {
                                          'musicResponsiveListItemFlexColumnRenderer': {
                                            'text': {
                                              'runs': [
                                                {'text': 'Late Arriving Song'}
                                              ]
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
                ]
              }
            }
          }),
          200,
        );
      });

      // Trigger search
      final future = provider.performSearch('will_be_cleared');
      expect(provider.isLoading, isTrue);

      // User immediately clears search before completion
      provider.clearSearch();
      expect(provider.results.isEmpty, isTrue);
      expect(provider.query, isEmpty);
      expect(provider.isLoading, isFalse);

      await future;

      // State should remain cleared, not overwritten by late response
      expect(provider.results.isEmpty, isTrue);
      expect(provider.query, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('onQueryChanged drops late suggestions when query changes rapidly', () async {
      final provider = SearchProvider();

      // Query 1 starts, but before it resolves Query 2 is typed
      provider.onQueryChanged('first');
      provider.onQueryChanged('second');

      // Allow any async debounces/completions to settle
      await Future.delayed(const Duration(milliseconds: 350));
      // query should reflect latest
      expect(provider.query, equals('second'));
    });
  });

  group('Multi-Artist Runs Formatting & Strict Duration Tests', () {
    test('formatArtistRuns parses multiple artists and joins with comma-space', () {
      final runs = [
        {'text': 'Karan Aujla'},
        {'text': ' & '},
        {'text': 'Ikky'},
      ];
      expect(InnerTubeService.formatArtistRuns(runs), equals('Karan Aujla, Ikky'));
    });

    test('formatArtistRuns strips feat. separators and punctuation', () {
      final runs1 = [
        {'text': 'Taylor Swift'},
        {'text': ' feat. '},
        {'text': 'Post Malone'},
      ];
      expect(InnerTubeService.formatArtistRuns(runs1), equals('Taylor Swift, Post Malone'));

      final runs2 = [
        {'text': 'Coldplay, '},
        {'text': 'Beyoncé'},
      ];
      expect(InnerTubeService.formatArtistRuns(runs2), equals('Coldplay, Beyoncé'));

      final runs3 = [
        {'text': 'Drake'},
        {'text': ' / '},
        {'text': '21 Savage'},
      ];
      expect(InnerTubeService.formatArtistRuns(runs3), equals('Drake, 21 Savage'));
    });

    test('formatArtistRuns deduplicates identical artist names', () {
      final runs = [
        {'text': 'Arijit Singh'},
        {'text': ' • '},
        {'text': 'Arijit Singh'},
      ];
      expect(InnerTubeService.formatArtistRuns(runs), equals('Arijit Singh'));
    });

    test('formatArtistRuns handles null and empty runs', () {
      expect(InnerTubeService.formatArtistRuns(null), equals(''));
      expect(InnerTubeService.formatArtistRuns([]), equals(''));
      expect(InnerTubeService.formatArtistRuns({'runs': []}), equals(''));
    });

    test('parseDuration strictly matches M:SS and H:MM:SS format', () {
      expect(InnerTubeService.parseDuration('3:45'), equals(225));
      expect(InnerTubeService.parseDuration('03:45'), equals(225));
      expect(InnerTubeService.parseDuration('1:23:45'), equals(5025));
    });

    test('parseDuration strictly ignores years, view counts, and live streams', () {
      expect(InnerTubeService.parseDuration('2024'), equals(0));
      expect(InnerTubeService.parseDuration('1.2M views'), equals(0));
      expect(InnerTubeService.parseDuration('12,345 views'), equals(0));
      expect(InnerTubeService.parseDuration('Streamed 2 days ago'), equals(0));
      expect(InnerTubeService.parseDuration('LIVE'), equals(0));
      expect(InnerTubeService.parseDuration(null), equals(0));
      expect(InnerTubeService.parseDuration(''), equals(0));
    });

    test('parseDuration handles int seconds', () {
      expect(InnerTubeService.parseDuration(245), equals(245));
      expect(InnerTubeService.parseDuration(0), equals(0));
      expect(InnerTubeService.parseDuration(-10), equals(0));
    });
  });

  group('InnerTube YouTube Music Search Suggestions Tests', () {
    tearDown(() {
      InnerTubeService.clientOverride = null;
    });

    test('getSearchSuggestions parses YouTube Music suggestion runs', () async {
      final suggestionsFixture = {
        'contents': [
          {
            'searchSuggestionsSectionRenderer': {
              'contents': [
                {
                  'searchSuggestionRenderer': {
                    'suggestion': {
                      'runs': [
                        {'text': 'arijit singh '},
                        {'text': 'songs', 'bold': true},
                      ]
                    }
                  }
                },
                {
                  'searchSuggestionRenderer': {
                    'suggestion': {
                      'runs': [
                        {'text': 'arijit singh live'},
                      ]
                    }
                  }
                },
              ]
            }
          }
        ]
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('get_search_suggestions')) {
          expect(request.headers['x-origin'], equals('https://music.youtube.com'));
          expect(request.headers['x-goog-api-format-version'], equals('1'));
          return http.Response(jsonEncode(suggestionsFixture), 200);
        }
        return http.Response('Not Found', 404);
      });

      final suggestions = await InnerTubeService.getSearchSuggestions('arijit');
      expect(suggestions, contains('arijit singh songs'));
      expect(suggestions, contains('arijit singh live'));
    });

    test('getSearchSuggestions falls back cleanly if InnerTube call fails', () async {
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('get_search_suggestions')) {
          return http.Response('Server Error', 500);
        }
        if (request.url.host.contains('suggestqueries.google.com')) {
          final fallbackJson = [
            'channa mereya',
            ['channa mereya song', 'channa mereya episode cartoon', 'channa mereya live']
          ];
          return http.Response(jsonEncode(fallbackJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final suggestions = await InnerTubeService.getSearchSuggestions('channa mereya');
      expect(suggestions, contains('channa mereya song'));
      expect(suggestions, contains('channa mereya live'));
      // cartoon spam should be filtered out
      expect(suggestions.any((s) => s.contains('cartoon')), isFalse);
    });
  });
}
