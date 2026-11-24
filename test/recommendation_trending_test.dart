import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/models/song.dart';
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
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = 'test_visitor_data';
    InnerTubeService.setLocale(gl: 'IN', hl: 'en');
  });

  tearDown(() {
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = null;
    RecommendationService.clearCache();
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

    test('English dynamically adapts gl between IN and US based on other selected languages', () {
      final englishWithHindi = RecommendationService.getLanguageConfig(
        'English',
        allSelectedLanguages: ['Hindi', 'English'],
      );
      expect(englishWithHindi.gl, equals('IN'));
      expect(englishWithHindi.hl, equals('en'));

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

      final items = await RecommendationService.getFeaturedBrowseItems(languages: ['English']);

      expect(items, isNotEmpty);
      expect(items.any((item) => (item.browseId == 'PL_charts_top' || item.browseId == 'VLPL_charts_top') && item.type == 'playlist'), isTrue);
      expect(items.any((item) => item.browseId == 'MPREb_new_album' && item.type == 'album'), isTrue);
    });
  });
}
