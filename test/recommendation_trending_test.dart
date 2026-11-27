import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/browse_result.dart';
import 'package:melody/models/search_result.dart';
import 'package:melody/models/song.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/services/recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _mockJsonResponse(Map<String, dynamic> data, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.init();
    RecommendationService.clearCache();
    AntiBotService.reset();
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = 'test_visitor_data';
    InnerTubeService.setLocale(gl: 'IN', hl: 'en');
  });

  tearDown(() {
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = null;
    RecommendationService.clearCache();
    AntiBotService.reset();
  });

  group('RecommendationService Language & Locale Mapping Tests', () {
    test('Maps all 16 supported languages to proper gl/hl and keywords', () {
      final hindi = RecommendationService.getLanguageConfig('Hindi');
      expect(hindi.gl, equals('IN'));
      expect(hindi.hl, equals('en'));
      expect(hindi.keywords, contains('hindi'));
      expect(hindi.keywords, contains('bollywood'));

      final punjabi = RecommendationService.getLanguageConfig('Punjabi');
      expect(punjabi.gl, equals('IN'));
      expect(punjabi.hl, equals('en'));
      expect(punjabi.keywords, contains('punjabi'));

      final tamil = RecommendationService.getLanguageConfig('Tamil');
      expect(tamil.gl, equals('IN'));
      expect(tamil.hl, equals('en'));
      expect(tamil.keywords, contains('tamil'));

      final telugu = RecommendationService.getLanguageConfig('Telugu');
      expect(telugu.gl, equals('IN'));
      expect(telugu.hl, equals('en'));

      final bengali = RecommendationService.getLanguageConfig('Bengali');
      expect(bengali.gl, equals('IN'));
      expect(bengali.hl, equals('en'));

      final marathi = RecommendationService.getLanguageConfig('Marathi');
      expect(marathi.gl, equals('IN'));
      expect(marathi.hl, equals('en'));

      final kannada = RecommendationService.getLanguageConfig('Kannada');
      expect(kannada.gl, equals('IN'));
      expect(kannada.hl, equals('en'));

      final malayalam = RecommendationService.getLanguageConfig('Malayalam');
      expect(malayalam.gl, equals('IN'));
      expect(malayalam.hl, equals('en'));

      final bhojpuri = RecommendationService.getLanguageConfig('Bhojpuri');
      expect(bhojpuri.gl, equals('IN'));
      expect(bhojpuri.hl, equals('en'));

      final korean = RecommendationService.getLanguageConfig('Korean');
      expect(korean.gl, equals('KR'));
      expect(korean.hl, equals('en'));
      expect(korean.keywords, contains('k-pop'));

      final japanese = RecommendationService.getLanguageConfig('Japanese');
      expect(japanese.gl, equals('JP'));
      expect(japanese.hl, equals('en'));
      expect(japanese.keywords, contains('j-pop'));

      final spanish = RecommendationService.getLanguageConfig('Spanish');
      expect(spanish.gl, equals('MX'));
      expect(spanish.hl, equals('en'));
      expect(spanish.keywords, contains('latin'));

      final french = RecommendationService.getLanguageConfig('French');
      expect(french.gl, equals('FR'));
      expect(french.hl, equals('en'));

      final arabic = RecommendationService.getLanguageConfig('Arabic');
      expect(arabic.gl, equals('SA'));
      expect(arabic.hl, equals('en'));

      final urdu = RecommendationService.getLanguageConfig('Urdu');
      expect(urdu.gl, equals('PK'));
      expect(urdu.hl, equals('en'));
    });

    test('English consistently stays on gl: US and hl: en regardless of other selected languages', () {
      final englishWithHindiBengali = RecommendationService.getLanguageConfig(
        'English',
        allSelectedLanguages: ['Hindi', 'English', 'Bengali'],
      );
      expect(englishWithHindiBengali.gl, equals('US'));
      expect(englishWithHindiBengali.hl, equals('en'));

      final englishAlone = RecommendationService.getLanguageConfig(
        'English',
        allSelectedLanguages: ['English'],
      );
      expect(englishAlone.gl, equals('US'));
      expect(englishAlone.hl, equals('en'));

      final englishWithKorean = RecommendationService.getLanguageConfig(
        'English',
        allSelectedLanguages: ['Korean', 'English'],
      );
      expect(englishWithKorean.gl, equals('US'));
      expect(englishWithKorean.hl, equals('en'));
    });

    test('searchTrendingSinglesForLanguages synchronizes InnerTubeService locale with primary language', () async {
      InnerTubeService.clientOverride = MockClient((request) async {
        return _mockJsonResponse({});
      });

      await RecommendationService.searchTrendingSinglesForLanguages(['Korean', 'English']);
      expect(InnerTubeService.gl, equals('KR'));
      expect(InnerTubeService.hl, equals('en'));

      await RecommendationService.searchTrendingSinglesForLanguages(['Hindi', 'Punjabi']);
      expect(InnerTubeService.gl, equals('IN'));
      expect(InnerTubeService.hl, equals('en'));
    });
  });

  group('RecommendationService Duration & Blacklist Filtering Tests', () {
    test('isSingleSong strictly excludes compilations and songs > 12 minutes', () {
      const normalTrack = Song(
        id: 'norm_1',
        title: 'Kesariya',
        artist: 'Arijit Singh',
        duration: 268,
        thumbnailUrl: '',
      );
      expect(RecommendationService.isSingleSong(normalTrack), isTrue);

      const twelveMinTrack = Song(
        id: 'long_1',
        title: 'Extended Classical Symphony',
        artist: 'Symphony Orchestra',
        duration: 710, // ~11.8 mins (< 12 mins)
        thumbnailUrl: '',
      );
      expect(RecommendationService.isSingleSong(twelveMinTrack), isTrue);

      const excessiveJukebox = Song(
        id: 'jukebox_1',
        title: 'Bollywood Mega Hits',
        artist: 'Various',
        duration: 730, // > 12 mins
        thumbnailUrl: '',
      );
      expect(RecommendationService.isSingleSong(excessiveJukebox), isFalse);

      const blacklistJukebox = Song(
        id: 'juke_title',
        title: 'Romantic Hits Audio Jukebox 2026',
        artist: 'Music Label',
        duration: 300,
        thumbnailUrl: '',
      );
      expect(RecommendationService.isSingleSong(blacklistJukebox), isFalse);

      const blacklistNonStop = Song(
        id: 'nonstop_title',
        title: 'Non-Stop Party Dance Mix',
        artist: 'DJ',
        duration: 250,
        thumbnailUrl: '',
      );
      expect(RecommendationService.isSingleSong(blacklistNonStop), isFalse);
    });
  });

  group('RecommendationService Browse Hub & Playlist Unpacking Tests', () {
    test('Unpacks playlists automatically when hub songs are fewer than 10', () async {
      final visitedUrls = <String>[];
      final visitedBrowseIds = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        visitedUrls.add(request.url.toString());
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') {
          return _mockJsonResponse({});
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final browseId = body['browseId'] as String?;
        if (browseId != null) visitedBrowseIds.add(browseId);

        // 1. Moods and genres list
        if (browseId == 'FEmusic_moods_and_genres') {
          return _mockJsonResponse({
            'contents': {
              'singleColumnBrowseResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'gridRenderer': {
                                'items': [
                                  {
                                    'musicNavigationButtonRenderer': {
                                      'buttonText': {
                                        'runs': [{'text': 'Hindi & Bollywood'}]
                                      },
                                      'solid': {'leftStripeColor': 4283215696},
                                      'clickCommand': {
                                        'browseEndpoint': {
                                          'browseId': 'FEmusic_genre_hindi',
                                          'params': 'params_hindi_hub',
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
          });
        }

        // 2. Hub browse: return 0 direct songs, but 1 curated playlist
        if (browseId == 'FEmusic_genre_hindi') {
          return _mockJsonResponse({
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
                                      'runs': [{'text': 'Trending Playlists'}]
                                    }
                                  }
                                },
                                'contents': [
                                  {
                                    'musicTwoRowItemRenderer': {
                                      'navigationEndpoint': {
                                        'browseEndpoint': {'browseId': 'VLPL_hindi_hits'}
                                      },
                                      'title': {
                                        'runs': [{'text': 'Hindi Top 50 Hits'}]
                                      },
                                      'subtitle': {
                                        'runs': [{'text': 'YouTube Music'}]
                                      },
                                      'thumbnailRenderer': {
                                        'musicThumbnailRenderer': {
                                          'thumbnail': {
                                            'thumbnails': [{'url': 'https://i.ytimg.com/pl_thumb.jpg'}]
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
          });
        }

        // 3. Playlist browse: unpacked tracks
        if (browseId == 'VLPL_hindi_hits') {
          return _mockJsonResponse({
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
                                  'runs': [{'text': 'Hindi Top 50 Hits'}]
                                },
                                'straplineTextOne': {
                                  'runs': [{'text': 'YouTube Music'}]
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
                                'playlistItemData': {'videoId': 'hindi_unpacked_1'},
                                'flexColumns': [
                                  {
                                    'musicResponsiveListItemFlexColumnRenderer': {
                                      'text': {
                                        'runs': [{'text': 'Chaleya'}]
                                      }
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemFlexColumnRenderer': {
                                      'text': {
                                        'runs': [
                                          {
                                            'text': 'Arijit Singh, Shilpa Rao',
                                            'navigationEndpoint': {
                                              'browseEndpoint': {'browseId': 'UC_arijit'}
                                            }
                                          },
                                          {'text': ' • '},
                                          {'text': 'Jawan'},
                                          {'text': ' • '},
                                          {'text': '3:20'}
                                        ]
                                      }
                                    }
                                  }
                                ],
                                'thumbnail': {
                                  'musicThumbnailRenderer': {
                                    'thumbnail': {
                                      'thumbnails': [{'url': 'https://i.ytimg.com/chaleya.jpg'}]
                                    }
                                  }
                                }
                              }
                            },
                            {
                              'musicResponsiveListItemRenderer': {
                                'playlistItemData': {'videoId': 'hindi_unpacked_2'},
                                'flexColumns': [
                                  {
                                    'musicResponsiveListItemFlexColumnRenderer': {
                                      'text': {
                                        'runs': [{'text': 'Satranga'}]
                                      }
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemFlexColumnRenderer': {
                                      'text': {
                                        'runs': [
                                          {'text': 'Arijit Singh'},
                                          {'text': ' • '},
                                          {'text': 'Animal'},
                                          {'text': ' • '},
                                          {'text': '4:30'}
                                        ]
                                      }
                                    }
                                  }
                                ],
                                'thumbnail': {
                                  'musicThumbnailRenderer': {
                                    'thumbnail': {
                                      'thumbnails': [{'url': 'https://i.ytimg.com/satranga.jpg'}]
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
        }

        // Charts or others return empty
        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(['Hindi']);

      expect(visitedBrowseIds, contains('FEmusic_moods_and_genres'));
      expect(visitedBrowseIds, contains('FEmusic_genre_hindi'));
      expect(visitedBrowseIds, contains('VLPL_hindi_hits'));

      expect(songs.length, equals(2));
      expect(songs[0].id, equals('hindi_unpacked_1'));
      expect(songs[0].title, equals('Chaleya'));
      expect(songs[0].artist, equals('Arijit Singh, Shilpa Rao'));
      expect(songs[1].id, equals('hindi_unpacked_2'));
      expect(songs[1].title, equals('Satranga'));
    });
  });

  group('RecommendationService Multi-Language Slot Interleaving & Deduplication Tests', () {
    test('Interleaves tracks across multiple selected languages and deduplicates shared song IDs', () async {
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') {
          return _mockJsonResponse({});
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final browseId = body['browseId'] as String?;

        if (browseId == 'FEmusic_moods_and_genres') {
          return _mockJsonResponse({
            'contents': {
              'singleColumnBrowseResultsRenderer': {
                'tabs': [
                  {
                    'tabRenderer': {
                      'content': {
                        'sectionListRenderer': {
                          'contents': [
                            {
                              'gridRenderer': {
                                'items': [
                                  {
                                    'musicNavigationButtonRenderer': {
                                      'buttonText': {
                                        'runs': [{'text': 'Hindi & Bollywood'}]
                                      },
                                      'clickCommand': {
                                        'browseEndpoint': {'browseId': 'hub_hindi'}
                                      }
                                    }
                                  },
                                  {
                                    'musicNavigationButtonRenderer': {
                                      'buttonText': {
                                        'runs': [{'text': 'Punjabi'}]
                                      },
                                      'clickCommand': {
                                        'browseEndpoint': {'browseId': 'hub_punjabi'}
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

        if (browseId == 'hub_hindi') {
          return _mockJsonResponse({
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
                                'contents': [
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'h_track_1'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi 1'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Artist H'}]}}},
                                      ],
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'shared_track_cross_lang'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Shared Song'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Cross Artist'}]}}},
                                      ],
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'h_track_2'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi 2'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Artist H2'}]}}},
                                      ],
                                    }
                                  },
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

        if (browseId == 'hub_punjabi') {
          return _mockJsonResponse({
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
                                'contents': [
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'p_track_1'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Punjabi 1'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Artist P'}]}}},
                                      ],
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'shared_track_cross_lang'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Shared Song'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Cross Artist'}]}}},
                                      ],
                                    }
                                  },
                                  {
                                    'musicResponsiveListItemRenderer': {
                                      'playlistItemData': {'videoId': 'p_track_2'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Punjabi 2'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Artist P2'}]}}},
                                      ],
                                    }
                                  },
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

        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(['Hindi', 'Punjabi']);
      final songIds = songs.map((s) => s.id).toList();

      // Interleaving check: index 0 is from Hindi, index 1 is from Punjabi
      expect(songIds[0], equals('h_track_1'));
      expect(songIds[1], equals('p_track_1'));

      // Deduplication check: shared_track_cross_lang appears exactly once
      expect(songIds.where((id) => id == 'shared_track_cross_lang').length, equals(1));
    });
  });

  group('RecommendationService Featured Browse Items Tests', () {
    test('getFeaturedBrowseItems returns curated charts playlists, new releases, and hub media', () async {
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') {
          return _mockJsonResponse({});
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final browseId = body['browseId'] as String?;

        if (browseId == 'FEmusic_charts') {
          return _mockJsonResponse({
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
                                    'title': {'runs': [{'text': 'Top Music Videos'}]}
                                  }
                                },
                                'contents': [
                                  {
                                    'musicTwoRowItemRenderer': {
                                      'navigationEndpoint': {
                                        'browseEndpoint': {'browseId': 'VLPL_charts_top'}
                                      },
                                      'title': {'runs': [{'text': 'Top 100 India'}]},
                                      'subtitle': {'runs': [{'text': 'YouTube Music'}]},
                                      'thumbnailRenderer': {
                                        'musicThumbnailRenderer': {
                                          'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/chart.jpg'}]}
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
          });
        }

        if (browseId == 'FEmusic_explore') {
          return _mockJsonResponse({
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
                                    'title': {'runs': [{'text': 'New Releases'}]}
                                  }
                                },
                                'contents': [
                                  {
                                    'musicTwoRowItemRenderer': {
                                      'navigationEndpoint': {
                                        'browseEndpoint': {'browseId': 'MPREb_new_album'}
                                      },
                                      'title': {'runs': [{'text': 'New Album 2026'}]},
                                      'subtitle': {'runs': [{'text': 'Famous Artist'}]},
                                      'thumbnailRenderer': {
                                        'musicThumbnailRenderer': {
                                          'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/album.jpg'}]}
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
          });
        }

        return _mockJsonResponse({});
      });

      final items = await RecommendationService.getFeaturedBrowseItems(languages: ['Hindi']);

      expect(items, isNotEmpty);
      expect(items.any((item) => (item.browseId == 'PL_charts_top' || item.browseId == 'VLPL_charts_top') && item.type == 'playlist'), isTrue);
      expect(items.any((item) => item.browseId == 'MPREb_new_album' && item.type == 'album'), isTrue);
    });
  });

  group('Multi-Language Home Feed & Bengali/English/Hindi Fixes Tests', () {
    test('Hindi, English, Bengali: NEVER calls getCharts IN for Bengali/English, falls back to search for Bengali, and interleaves top slots', () async {
      AntiBotService.reset();
      final requestedEndpoints = <String>[];
      final requestedChartCountries = <String>[];
      final searchQueries = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;
          requestedEndpoints.add('browse:$browseId');

          if (browseId == 'FEmusic_charts') {
            final formData = body['formData'] as Map<String, dynamic>?;
            final selectedValues = formData?['selectedValues'] as List<dynamic>?;
            final country = selectedValues?.firstOrNull?.toString() ?? 'unknown';
            requestedChartCountries.add(country);
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'hindi_chart_1'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Song 1'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Artist'}]}}},
                                        ],
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

          if (browseId == 'FEmusic_moods_and_genres') {
            // Hindi matches Bollywood, English matches Pop, Bengali matches nothing
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Hindi & Bollywood'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_hindi'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_pop'}}
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

          if (browseId == 'hub_hindi') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'hindi_song_hub'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Hub Track'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Singer'}]}}},
                                        ],
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

          if (browseId == 'hub_pop') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'english_song_hub'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'English Pop Track'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'English Singer'}]}}},
                                        ],
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
        }

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          searchQueries.add(query);

          if (query.contains('Bengali')) {
            return _mockJsonResponse({
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
                                        'playlistItemData': {'videoId': 'bengali_search_song'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali Track'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali Artist'}]}}},
                                        ],
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
        }

        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(
        ['Hindi', 'English', 'Bengali'],
      );

      // Verify regional language Bengali NEVER called getCharts('IN')
      // Only Hindi ('IN') and English ('US') are allowed to call charts
      expect(requestedChartCountries.contains('IN'), isTrue); // from Hindi
      expect(requestedChartCountries.where((c) => c == 'IN').length, equals(1)); // NEVER duplicated for Bengali

      // Verify Bengali executed search fallback
      expect(searchQueries.any((q) => q.contains('Bengali top songs')), isTrue);

      // Verify strict round-robin interleaving: Hindi -> English -> Bengali
      final songIds = songs.map((s) => s.id).toList();
      expect(songIds.contains('hindi_song_hub'), isTrue);
      expect(songIds.contains('english_song_hub'), isTrue);
      expect(songIds.contains('bengali_search_song'), isTrue);

      expect(songIds[0], equals('hindi_song_hub'));
      expect(songIds[1], equals('english_song_hub'));
      expect(songIds[2], equals('bengali_search_song'));
    });

    test('getFeaturedBrowseItems round-robin interleaves across languages and includes search fallback for Bengali', () async {
      AntiBotService.reset();
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;
          if (browseId == 'FEmusic_charts') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicTwoRowItemRenderer': {
                                        'navigationEndpoint': {'browseEndpoint': {'browseId': 'VLPL_hindi_chart_pl'}},
                                        'title': {'runs': [{'text': 'Top 100 Hindi'}]},
                                        'subtitle': {'runs': [{'text': 'Hindi Charts'}]},
                                        'thumbnailRenderer': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/h.jpg'}]}}}
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

          if (browseId == 'FEmusic_moods_and_genres') {
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Bollywood'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_hindi_featured'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_english_featured'}}
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

          if (browseId == 'hub_hindi_featured') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicTwoRowItemRenderer': {
                                        'navigationEndpoint': {'browseEndpoint': {'browseId': 'VLPL_hindi_pl'}},
                                        'title': {'runs': [{'text': 'Bollywood Hits'}]},
                                        'subtitle': {'runs': [{'text': 'Hindi'}]},
                                        'thumbnailRenderer': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/hpl.jpg'}]}}}
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

          if (browseId == 'hub_english_featured') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicTwoRowItemRenderer': {
                                        'navigationEndpoint': {'browseEndpoint': {'browseId': 'VLPL_english_pl'}},
                                        'title': {'runs': [{'text': 'Global Pop Hits'}]},
                                        'subtitle': {'runs': [{'text': 'English'}]},
                                        'thumbnailRenderer': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/epl.jpg'}]}}}
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
        }

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          if (query.contains('Bengali')) {
            return _mockJsonResponse({
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
                                        'navigationEndpoint': {
                                          'browseEndpoint': {
                                            'browseId': 'VLPL_bengali_search_pl',
                                            'browseEndpointContextSupportedConfigs': {
                                              'browseEndpointContextMusicConfig': {
                                                'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                                              }
                                            }
                                          }
                                        },
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali Hits Playlist'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali'}]}}},
                                        ],
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
        }

        return _mockJsonResponse({});
      });

      final items = await RecommendationService.getFeaturedBrowseItems(
        languages: ['Hindi', 'English', 'Bengali'],
      );

      expect(items, isNotEmpty);
      final titles = items.map((i) => i.title).toList();
      // Verify Hindi, English, and Bengali are all present in featured items
      expect(titles.any((t) => t.contains('Hindi') || t.contains('Bollywood')), isTrue);
      expect(titles.any((t) => t.contains('English') || t.contains('Global Pop')), isTrue);
      expect(titles.any((t) => t.contains('Bengali')), isTrue);
    });

    test('getPersonalizedQuickPicks queries genre tracks across multiple languages', () async {
      AntiBotService.reset();
      final searchQueries = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          searchQueries.add(query);
          return _mockJsonResponse({
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
                                      'playlistItemData': {'videoId': 'song_$query'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Title $query'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Artist $query'}]}}},
                                      ],
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

        return _mockJsonResponse({});
      });

      // Add a song to history to trigger tasteProfile.hasHistory = true
      await DatabaseService.addToHistory(const Song(
        id: 'history_song_1',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        duration: 260,
        thumbnailUrl: 'https://i.ytimg.com/thumb.jpg',
      ));

      await RecommendationService.getPersonalizedQuickPicks(
        languages: ['Hindi', 'English', 'Bengali'],
      );

      // Verify that genre tracks were queried across multiple languages (not just Hindi)
      expect(searchQueries.any((q) => q.startsWith('Hindi ')), isTrue);
      expect(searchQueries.any((q) => q.startsWith('English ')), isTrue);
      expect(searchQueries.any((q) => q.startsWith('Bengali ')), isTrue);
    });

    test('Disk feed cache respects _cacheTtl expiration, enforces v4, and clears on language change', () async {
      AntiBotService.reset();
      final songs = [
        const Song(
          id: 's1',
          title: 'Song 1',
          artist: 'Artist 1',
          duration: 200,
          thumbnailUrl: 'https://i.ytimg.com/thumb.jpg',
        ),
      ];

      // Save feed cache in v4 format
      const cacheKey = 'All:Hindi,English';
      await DatabaseService.saveCachedFeed(cacheKey, songs);

      // Timestamp should be present
      final ts = DatabaseService.getCachedFeedTimestamp(cacheKey);
      expect(ts, isNotNull);

      // Fresh cache: getQuickPicks should return diskCached
      InnerTubeService.clearQuickPicksCache();
      final cachedPicks = await InnerTubeService.getQuickPicks(
        languages: ['Hindi', 'English'],
        mood: 'All',
      );
      expect(cachedPicks.length, equals(1));
      expect(cachedPicks.first.id, equals('s1'));

      // Simulate expired cache (set timestamp to 10 minutes ago)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'melody_feed_cache_ts_v4_$cacheKey',
        DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      InnerTubeService.clearQuickPicksCache();

      // Now expired: when getQuickPicks runs, it should bypass expired disk cache and attempt remote fetch
      var remoteFetchAttempted = false;
      InnerTubeService.clientOverride = MockClient((request) async {
        remoteFetchAttempted = true;
        return _mockJsonResponse({});
      });

      await InnerTubeService.getQuickPicks(
        languages: ['Hindi', 'English'],
        mood: 'All',
      );
      expect(remoteFetchAttempted, isTrue);

      // Test pre-v4 pruning
      await prefs.setString('melody_feed_cache_v3_old_key', 'old_hindi_data');
      await prefs.setString('melody_feed_cache_v2_legacy_key', 'legacy_data');
      await DatabaseService.pruneOldFeedCaches();

      expect(prefs.containsKey('melody_feed_cache_v3_old_key'), isFalse);
      expect(prefs.containsKey('melody_feed_cache_v2_legacy_key'), isFalse);
      expect(prefs.containsKey('melody_feed_cache_v4_$cacheKey'), isTrue);

      // Test language change clears quick picks cache and notifies
      var notified = false;
      void listener() {
        notified = true;
      }
      DatabaseService.musicLanguagesNotifier.addListener(listener);

      await DatabaseService.setMusicLanguages(['English', 'Japanese']);
      expect(notified, isTrue);
      expect(DatabaseService.musicLanguagesNotifier.value, equals(['English', 'Japanese']));

      DatabaseService.musicLanguagesNotifier.removeListener(listener);
    });

    test('getFeaturedBrowseItems for regional languages (Bengali, Tamil) skips getCharts and getExplore Part 1', () async {
      AntiBotService.reset();
      final requestedBrowseIds = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;
          if (browseId != null) requestedBrowseIds.add(browseId);

          if (browseId == 'FEmusic_moods_and_genres') {
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Tamil Hits'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_tamil'}}
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

          if (browseId == 'hub_tamil') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicTwoRowItemRenderer': {
                                        'navigationEndpoint': {'browseEndpoint': {'browseId': 'VLPL_tamil_1'}},
                                        'title': {'runs': [{'text': 'Kollywood Hits'}]},
                                        'subtitle': {'runs': [{'text': 'Tamil'}]},
                                        'thumbnailRenderer': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [{'url': 'https://i.ytimg.com/tamil.jpg'}]}}}
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
        }

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          if (query.contains('Bengali')) {
            return _mockJsonResponse({
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
                                        'navigationEndpoint': {
                                          'browseEndpoint': {
                                            'browseId': 'VLPL_bengali_pl',
                                            'browseEndpointContextSupportedConfigs': {
                                              'browseEndpointContextMusicConfig': {
                                                'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                                              }
                                            }
                                          }
                                        },
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali Featured Playlist'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali'}]}}},
                                        ],
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
        }

        return _mockJsonResponse({});
      });

      // 1. Bengali only (primaryConfig: Bengali, useCountryCharts: false)
      RecommendationService.clearCache();
      final bengaliItems = await RecommendationService.getFeaturedBrowseItems(languages: ['Bengali']);
      expect(bengaliItems, isNotEmpty);
      expect(bengaliItems.first.title, contains('Bengali'));
      // FEmusic_charts and FEmusic_explore must NOT be requested
      expect(requestedBrowseIds.contains('FEmusic_charts'), isFalse);
      expect(requestedBrowseIds.contains('FEmusic_explore'), isFalse);

      // 2. Tamil + English (primaryConfig: Tamil, useCountryCharts: false)
      requestedBrowseIds.clear();
      RecommendationService.clearCache();
      final tamilItems = await RecommendationService.getFeaturedBrowseItems(languages: ['Tamil', 'English']);
      expect(tamilItems, isNotEmpty);
      expect(requestedBrowseIds.contains('FEmusic_charts'), isFalse);
      expect(requestedBrowseIds.contains('FEmusic_explore'), isFalse);
    });

    test('Non-All mood chip (e.g. Chill) queries and round-robin interleaves across multiple selected languages', () async {
      AntiBotService.reset();
      final requestedMoodHubs = <String>[];
      final searchRequests = <Map<String, String?>>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;

          if (browseId == 'FEmusic_moods_and_genres') {
            final context = body['context'] as Map<String, dynamic>?;
            final clientGl = context?['client']?['gl']?.toString() ?? '';
            // Hindi & English provide Chill hub
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': clientGl == 'US' ? 'Chill (US)' : 'Chill (IN)'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': clientGl == 'US' ? 'hub_chill_us' : 'hub_chill_in'}}
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

          if (browseId == 'hub_chill_in') {
            requestedMoodHubs.add('hub_chill_in');
            // Return 12 valid Hindi songs so >= 10 threshold does not trigger search fallback
            final hindiChillContents = List.generate(12, (idx) => {
              'musicResponsiveListItemRenderer': {
                'playlistItemData': {'videoId': 'hindi_chill_${idx + 1}'},
                'flexColumns': [
                  {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Chill Song ${idx + 1}'}]}}},
                  {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Hindi Artist ${idx + 1}'}]}}},
                ],
              }
            });
            return _mockJsonResponse({
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
                                  'contents': hindiChillContents,
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

          if (browseId == 'hub_chill_us') {
            requestedMoodHubs.add('hub_chill_us');
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'english_chill_1'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'English Chill Song'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'English Artist'}]}}},
                                        ],
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
        }

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          final params = body['params'] as String?;
          final client = body['context']?['client'] as Map<String, dynamic>?;
          searchRequests.add({
            'query': query,
            'params': params,
            'gl': client?['gl']?.toString(),
            'hl': client?['hl']?.toString(),
          });
          return _mockJsonResponse({
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
                                      'playlistItemData': {'videoId': query.startsWith('Bengali') ? 'bengali_chill_1' : 'other_chill_1'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': '$query Track'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Mood Artist'}]}}},
                                      ],
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

        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(
        ['Hindi', 'English', 'Bengali'],
        mood: 'Chill',
      );

      expect(songs, isNotEmpty);
      final songIds = songs.map((s) => s.id).toList();

      // Verify Hindi chill, English chill, and Bengali chill songs are all present
      expect(songIds.contains('hindi_chill_1'), isTrue);
      expect(songIds.contains('english_chill_1'), isTrue);
      expect(songIds.contains('bengali_chill_1'), isTrue);

      // Verify strict round-robin interleaving order in top 3 slots
      expect(songIds[0], equals('hindi_chill_1'));
      expect(songIds[1], equals('english_chill_1'));
      expect(songIds[2], equals('bengali_chill_1'));

      // Verify India's generic Chill hub was ONLY queried once (for Hindi) and SKIPPED for Bengali
      expect(requestedMoodHubs.where((h) => h == 'hub_chill_in').length, equals(1));
      expect(requestedMoodHubs.where((h) => h == 'hub_chill_us').length, equals(1));

      // Verify Bengali directly triggered targeted songs search with gl: IN, hl: en
      expect(
        searchRequests.any((r) =>
            r['query'] == 'Bengali Chill songs' &&
            r['params'] == SearchFilter.songs.params &&
            r['gl'] == 'IN' &&
            r['hl'] == 'en'),
        isTrue,
      );
      // Verify Hindi did NOT fall back to search since hub returned 12 songs (>= 10)
      expect(searchRequests.any((r) => r['query'] == 'Hindi Chill songs'), isFalse);
    });

    test('English NEVER matches Indian Pop, K-Pop, or Punjabi Pop hubs when moodGenres returns India catalog', () async {
      AntiBotService.reset();
      final englishConfig = RecommendationService.getLanguageConfig('English');

      // Case A: India-only pop hubs without clean "Pop" -> must return null and fall back to search
      final indiaOnlyHubs = [
        const MoodGenreItem(title: 'Indian Pop', browseId: 'hub_indian_pop'),
        const MoodGenreItem(title: 'K-Pop', browseId: 'hub_kpop'),
        const MoodGenreItem(title: 'J-Pop', browseId: 'hub_jpop'),
        const MoodGenreItem(title: 'Punjabi Pop', browseId: 'hub_punjabi_pop'),
      ];
      expect(RecommendationService.matchMoodGenreHub(indiaOnlyHubs, englishConfig), isNull);

      // Case B: When "Indian Pop" precedes "Pop" in India catalog -> must match exact "Pop"
      final mixedHubs = [
        ...indiaOnlyHubs,
        const MoodGenreItem(title: 'Pop', browseId: 'hub_global_pop'),
      ];
      final matched = RecommendationService.matchMoodGenreHub(mixedHubs, englishConfig);
      expect(matched, isNotNull);
      expect(matched!.title, equals('Pop'));
      expect(matched.browseId, equals('hub_global_pop'));

      // Verify end-to-end searchTrendingSinglesForLanguages(['English']) skips hub_indian_pop
      final visitedBrowseIds = <String>[];
      final searchQueries = <String>[];
      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;
          if (browseId != null) visitedBrowseIds.add(browseId);

          if (browseId == 'FEmusic_moods_and_genres') {
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Indian Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_indian_pop'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'K-Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_kpop'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Punjabi Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_punjabi_pop'}}
                                      }
                                    },
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
        }

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          searchQueries.add(query);
          return _mockJsonResponse({
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
                                      'playlistItemData': {'videoId': 'eng_fallback_1'},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Blinding Lights'}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'The Weeknd'}]}}},
                                      ],
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
        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(['English']);
      expect(visitedBrowseIds, isNot(contains('hub_indian_pop')));
      expect(visitedBrowseIds, isNot(contains('hub_kpop')));
      expect(visitedBrowseIds, isNot(contains('hub_punjabi_pop')));
      expect(searchQueries, contains('top english pop songs'));
      expect(songs.map((s) => s.id), contains('eng_fallback_1'));
    });

    test('Selecting English and Bengali (without Hindi) never pulls Indian Pop hub or IN charts and omits visitorData on US requests', () async {
      AntiBotService.reset();
      InnerTubeService.visitorData = 'CgtJTkRJT1VTX1ZJRA%3D%3D';
      final visitedBrowseIds = <String>[];
      final chartCountries = <String>[];
      final usRequestsWithVisitorData = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"CgtJTkRJT1VTX1ZJRA\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = body['context']?['client'] as Map<String, dynamic>?;
        final gl = client?['gl']?.toString();
        if (gl == 'US' &&
            (client?.containsKey('visitorData') == true ||
                request.headers.containsKey('X-Goog-Visitor-Id'))) {
          usRequestsWithVisitorData.add(request.url.path);
        }

        final path = request.url.path;
        if (path.contains('browse')) {
          final browseId = body['browseId'] as String?;
          if (browseId != null) visitedBrowseIds.add(browseId);

          if (browseId == 'FEmusic_charts') {
            final selected = (body['formData']?['selectedValues'] as List?)?.firstOrNull?.toString() ?? gl ?? '';
            chartCountries.add(selected);
            return _mockJsonResponse({});
          }

          if (browseId == 'FEmusic_moods_and_genres') {
            return _mockJsonResponse({
              'contents': {
                'singleColumnBrowseResultsRenderer': {
                  'tabs': [
                    {
                      'tabRenderer': {
                        'content': {
                          'sectionListRenderer': {
                            'contents': [
                              {
                                'gridRenderer': {
                                  'items': [
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Indian Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_indian_pop'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Pop'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_pop_us'}}
                                      }
                                    },
                                    {
                                      'musicNavigationButtonRenderer': {
                                        'buttonText': {'runs': [{'text': 'Bengali'}]},
                                        'clickCommand': {'browseEndpoint': {'browseId': 'hub_bengali'}}
                                      }
                                    },
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

          if (browseId == 'hub_indian_pop') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'O0XXJLhZrzg'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Payal Ki Khanak'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Mohit Love'}]}}},
                                        ],
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

          if (browseId == 'hub_pop_us') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'eng_us_1'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Fortnight'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Taylor Swift'}]}}},
                                        ],
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

          if (browseId == 'hub_bengali') {
            return _mockJsonResponse({
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
                                  'contents': [
                                    {
                                      'musicResponsiveListItemRenderer': {
                                        'playlistItemData': {'videoId': 'ben_hub_1'},
                                        'flexColumns': [
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Mayabini'}]}}},
                                          {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': 'Bengali Artist'}]}}},
                                        ],
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
        }

        return _mockJsonResponse({});
      });

      final songs = await RecommendationService.searchTrendingSinglesForLanguages(
        ['English', 'Bengali'],
      );

      expect(visitedBrowseIds, isNot(contains('hub_indian_pop')));
      expect(chartCountries, isNot(contains('IN')));
      expect(usRequestsWithVisitorData, isEmpty);

      final songIds = songs.map((s) => s.id).toList();
      expect(songIds, isNot(contains('O0XXJLhZrzg')));
      expect(songIds[0], equals('eng_us_1'));
      expect(songIds[1], equals('ben_hub_1'));
    });

    test('getPersonalizedQuickPicks gates Hindi listening history when Hindi is not selected', () async {
      AntiBotService.reset();
      final searchQueries = <String>[];

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('search')) {
          final query = body['query'] as String? ?? '';
          searchQueries.add(query);
          final vid = query.startsWith('Bengali') ? 'ben_track_1' : 'eng_track_1';
          final title = query.startsWith('Bengali') ? 'Mayabini' : 'Blinding Lights';
          final artist = query.startsWith('Bengali') ? 'Bengali Singer' : 'The Weeknd';
          return _mockJsonResponse({
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
                                      'playlistItemData': {'videoId': vid},
                                      'flexColumns': [
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': title}]}}},
                                        {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': artist}]}}},
                                      ],
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
        return _mockJsonResponse({});
      });

      // Seed history with a Hindi track while user selects English + Bengali (no Hindi)
      await DatabaseService.addToHistory(const Song(
        id: 'ge4M2dVBgTw',
        title: 'Saiyaara',
        artist: 'Mohit Chauhan',
        duration: 250,
        thumbnailUrl: 'https://i.ytimg.com/saiyaara.jpg',
      ));

      final picks = await RecommendationService.getPersonalizedQuickPicks(
        languages: ['English', 'Bengali'],
      );

      expect(searchQueries.any((q) => q.contains('Saiyaara')), isFalse);
      expect(searchQueries.any((q) => q.startsWith('English ')), isTrue);
      expect(searchQueries.any((q) => q.startsWith('Bengali ')), isTrue);
      expect(picks.map((s) => s.id), isNot(contains('ge4M2dVBgTw')));
    });

    test('getPersonalizedQuickPicks backfills to at least 16 eligible tracks and strips play/view counts from artists', () async {
      AntiBotService.reset();

      InnerTubeService.clientOverride = MockClient((request) async {
        if (request.url.path.contains('sw.js_data')) {
          return http.Response(")]}'\n[[[\"test_visitor_id\"]]]", 200);
        }
        if (request.method != 'POST') return _mockJsonResponse({});

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;

        if (path.contains('browse') && body['browseId'] == 'FEmusic_charts') {
          final chartItems = List.generate(
            6,
            (i) => {
              'musicResponsiveListItemRenderer': {
                'playlistItemData': {'videoId': 'chart_$i'},
                'flexColumns': [
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'Chart Track $i'}
                        ]
                      }
                    }
                  },
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'Chart Artist $i'},
                          {'text': ' • '},
                          {'text': '${i + 1}.2B plays'},
                        ]
                      }
                    }
                  },
                ],
              }
            },
          );
          return _mockJsonResponse({
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
                                'contents': chartItems,
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
          final searchItems = List.generate(
            18,
            (i) => {
              'musicResponsiveListItemRenderer': {
                'playlistItemData': {'videoId': 'pop_song_$i'},
                'flexColumns': [
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'Pop Song $i'}
                        ]
                      }
                    }
                  },
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': 'Artist $i'}
                        ]
                      }
                    }
                  },
                  {
                    'musicResponsiveListItemFlexColumnRenderer': {
                      'text': {
                        'runs': [
                          {'text': '450M views'}
                        ]
                      }
                    }
                  },
                ],
              }
            },
          );
          return _mockJsonResponse({
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
                                'contents': searchItems,
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

        return _mockJsonResponse({});
      });

      final picks = await RecommendationService.getPersonalizedQuickPicks(
        languages: ['English'],
      );

      expect(picks.length, greaterThanOrEqualTo(16));
      for (final song in picks) {
        expect(song.artist.toLowerCase(), isNot(contains('plays')));
        expect(song.artist.toLowerCase(), isNot(contains('views')));
      }
      expect(picks.first.artist, equals('Chart Artist 0'));
    });
  });
}
