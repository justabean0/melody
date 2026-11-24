import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/services/innertube_service.dart';

http.Response _mockJsonResponse(Map<String, dynamic> data, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    InnerTubeService.clientOverride = null;
    InnerTubeService.visitorData = null;
  });

  group('InnerTube Browse Endpoints Tests', () {
    test('browseAlbum parses metadata, ordered songs, and other versions from primary response', () async {
      final requestedBrowseIds = <String>[];

      final albumFixture = {
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
                              'runs': [{'text': 'Abbey Road'}]
                            },
                            'straplineTextOne': {
                              'runs': [
                                {
                                  'text': 'The Beatles',
                                  'navigationEndpoint': {
                                    'browseEndpoint': {'browseId': 'UCthebeatles'}
                                  }
                                }
                              ]
                            },
                            'subtitle': {
                              'runs': [
                                {'text': 'Album'},
                                {'text': ' • '},
                                {'text': '1969'}
                              ]
                            },
                            'thumbnail': {
                              'musicThumbnailRenderer': {
                                'thumbnail': {
                                  'thumbnails': [
                                    {'url': 'https://example.com/abbey_road.jpg'}
                                  ]
                                }
                              }
                            },
                            'description': {
                              'runs': [{'text': 'Iconic 1969 studio album'}]
                            },
                            'buttons': [
                              {
                                'buttonRenderer': {
                                  'navigationEndpoint': {
                                    'watchPlaylistEndpoint': {
                                      'playlistId': 'OLAK5uy_abbey_road_pid'
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
            ],
            'secondaryContents': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicPlaylistShelfRenderer': {
                      'contents': [
                        {
                          'musicResponsiveListItemRenderer': {
                            'playlistItemData': {'videoId': 'vid_come_together'},
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'Come Together'}]
                                  }
                                }
                              },
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'The Beatles'}]
                                  }
                                }
                              }
                            ],
                            'fixedColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': '4:19'}]
                                  }
                                }
                              }
                            ],
                            'thumbnail': {
                              'musicThumbnailRenderer': {
                                'thumbnail': {
                                  'thumbnails': [
                                    {'url': 'https://example.com/track1.jpg'}
                                  ]
                                }
                              }
                            }
                          }
                        },
                        {
                          'musicResponsiveListItemRenderer': {
                            'playlistItemData': {'videoId': 'vid_something'},
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'Something'}]
                                  }
                                }
                              }
                            ],
                            'fixedColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': '3:03'}]
                                  }
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                  },
                  {
                    'musicCarouselShelfRenderer': {
                      'contents': [
                        {
                          'musicTwoRowItemRenderer': {
                            'title': {
                              'runs': [{'text': 'Abbey Road (Super Deluxe)'}]
                            },
                            'navigationEndpoint': {
                              'browseEndpoint': {
                                'browseId': 'MPREb_super_deluxe',
                                'browseEndpointContextSupportedConfigs': {
                                  'browseEndpointContextMusicConfig': {
                                    'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                                  }
                                }
                              }
                            },
                            'thumbnailRenderer': {
                              'musicThumbnailRenderer': {
                                'thumbnail': {
                                  'thumbnails': [
                                    {'url': 'https://example.com/super_deluxe.jpg'}
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
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestedBrowseIds.add(body['browseId'] as String);
        return _mockJsonResponse(albumFixture);
      });

      final result = await InnerTubeService.browseAlbum('MPREb_abbey_road');
      expect(result, isNotNull);
      expect(result!.browseId, equals('MPREb_abbey_road'));
      expect(result.id, equals('MPREb_abbey_road'));
      expect(result.playlistId, equals('OLAK5uy_abbey_road_pid'));
      expect(result.title, equals('Abbey Road'));
      expect(result.artist, equals('The Beatles'));
      expect(result.artistId, equals('UCthebeatles'));
      expect(result.year, equals(1969));
      expect(result.thumbnailUrl, equals('https://example.com/abbey_road.jpg'));
      expect(result.thumbnail, equals('https://example.com/abbey_road.jpg'));
      expect(result.description, equals('Iconic 1969 studio album'));

      // Check ordered songs
      expect(result.songs.length, equals(2));
      expect(result.songs[0].id, equals('vid_come_together'));
      expect(result.songs[0].title, equals('Come Together'));
      expect(result.songs[0].artist, equals('The Beatles'));
      expect(result.songs[0].duration, equals(259)); // 4:19
      expect(result.songs[0].thumbnailUrl, equals('https://example.com/track1.jpg'));
      expect(result.songs[0].album, equals('Abbey Road'));
      expect(result.songs[0].albumId, equals('MPREb_abbey_road'));

      expect(result.songs[1].id, equals('vid_something'));
      expect(result.songs[1].title, equals('Something'));
      expect(result.songs[1].artist, equals('The Beatles')); // Inherited from album
      expect(result.songs[1].duration, equals(183)); // 3:03
      expect(result.songs[1].thumbnailUrl, equals('https://example.com/abbey_road.jpg')); // Inherited from album

      // Check other versions
      expect(result.otherVersions.length, equals(1));
      expect(result.otherVersions[0].browseId, equals('MPREb_super_deluxe'));
      expect(result.otherVersions[0].title, equals('Abbey Road (Super Deluxe)'));

      // Verify toAlbum() conversion
      final albumModel = result.toAlbum();
      expect(albumModel.browseId, equals('MPREb_abbey_road'));
      expect(albumModel.songs.length, equals(2));
      expect(albumModel.songCount, equals(2));

      expect(requestedBrowseIds, equals(['MPREb_abbey_road']));
    });

    test('browseAlbum performs secondary VL browse when primary response lacks tracks', () async {
      final requestedBrowseIds = <String>[];

      final primaryFixture = {
        'microformat': {
          'microformatDataRenderer': {
            'urlCanonical': 'https://music.youtube.com/playlist?list=OLAK5uy_secondary_pid'
          }
        },
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
                              'runs': [{'text': 'Secondary Album'}]
                            },
                            'straplineTextOne': {
                              'runs': [{'text': 'Solo Artist'}]
                            }
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

      final secondaryPlaylistFixture = {
        'contents': {
          'twoColumnBrowseResultsRenderer': {
            'secondaryContents': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicPlaylistShelfRenderer': {
                      'contents': [
                        {
                          'musicResponsiveListItemRenderer': {
                            'playlistItemData': {'videoId': 'secondary_track_1'},
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'Intro'}]
                                  }
                                }
                              }
                            ],
                            'fixedColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': '1:30'}]
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
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final bId = body['browseId'] as String;
        requestedBrowseIds.add(bId);
        if (bId == 'MPREb_needs_secondary') {
          return _mockJsonResponse(primaryFixture);
        } else if (bId == 'VLOLAK5uy_secondary_pid') {
          return _mockJsonResponse(secondaryPlaylistFixture);
        }
        return http.Response('Not Found', 404);
      });

      final result = await InnerTubeService.browseAlbum('MPREb_needs_secondary');
      expect(result, isNotNull);
      expect(result!.title, equals('Secondary Album'));
      expect(result.playlistId, equals('OLAK5uy_secondary_pid'));
      expect(result.songs.length, equals(1));
      expect(result.songs[0].id, equals('secondary_track_1'));
      expect(result.songs[0].title, equals('Intro'));
      expect(result.songs[0].duration, equals(90));

      expect(requestedBrowseIds, equals(['MPREb_needs_secondary', 'VLOLAK5uy_secondary_pid']));
    });

    test('browsePlaylist normalizes PL... and RDCLAK5uy_... by prepending VL and parses metadata + songs', () async {
      final requestedBrowseIds = <String>[];

      final playlistFixture = {
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
                              'runs': [{'text': 'Today Hits'}]
                            },
                            'straplineTextOne': {
                              'runs': [
                                {
                                  'text': 'YouTube Music',
                                  'navigationEndpoint': {
                                    'browseEndpoint': {'browseId': 'UCytmusic'}
                                  }
                                }
                              ]
                            },
                            'thumbnail': {
                              'musicThumbnailRenderer': {
                                'thumbnail': {
                                  'thumbnails': [
                                    {'url': 'https://example.com/today_hits.jpg'}
                                  ]
                                }
                              }
                            },
                            'description': {
                              'runs': [{'text': 'The hottest tracks right now.'}]
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
                            'playlistItemData': {'videoId': 'hit_vid_1'},
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'Hit Track One'}]
                                  }
                                }
                              },
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [
                                      {
                                        'text': 'Pop Star',
                                        'navigationEndpoint': {
                                          'browseEndpoint': {'browseId': 'UCpopstar'}
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            ],
                            'fixedColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': '3:45'}]
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
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestedBrowseIds.add(body['browseId'] as String);
        return _mockJsonResponse(playlistFixture);
      });

      // 1. PL prefix test -> should prepend VL
      final plResult = await InnerTubeService.browsePlaylist('PL1234567890');
      expect(plResult, isNotNull);
      expect(plResult!.browseId, equals('VLPL1234567890'));
      expect(plResult.playlistId, equals('PL1234567890'));
      expect(plResult.title, equals('Today Hits'));
      expect(plResult.author, equals('YouTube Music'));
      expect(plResult.authorId, equals('UCytmusic'));
      expect(plResult.description, equals('The hottest tracks right now.'));
      expect(plResult.thumbnailUrl, equals('https://example.com/today_hits.jpg'));
      expect(plResult.songs.length, equals(1));
      expect(plResult.songs[0].id, equals('hit_vid_1'));
      expect(plResult.songs[0].title, equals('Hit Track One'));
      expect(plResult.songs[0].artist, equals('Pop Star'));
      expect(plResult.songs[0].artistId, equals('UCpopstar'));
      expect(plResult.songs[0].duration, equals(225));

      // 2. RDCLAK5uy_ prefix test -> should prepend VL
      await InnerTubeService.browsePlaylist('RDCLAK5uy_abcdef');

      // 3. Already starts with VL -> should not prepend another VL
      await InnerTubeService.browsePlaylist('VLPLalready_has_vl');

      expect(requestedBrowseIds, equals([
        'VLPL1234567890',
        'VLRDCLAK5uy_abcdef',
        'VLPLalready_has_vl',
      ]));
    });

    test('browseArtist parses profile, top songs, and albums with real MPREb_ IDs', () async {
      final requestedBrowseIds = <String>[];

      final artistFixture = {
        'header': {
          'musicImmersiveHeaderRenderer': {
            'title': {
              'runs': [{'text': 'Dua Lipa'}]
            },
            'thumbnail': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [
                    {'url': 'https://example.com/dualipa.jpg'}
                  ]
                }
              }
            },
            'subscriptionButton2': {
              'subscribeButtonRenderer': {
                'subscriberCountWithSubscribeText': {
                  'runs': [{'text': '23.4M subscribers'}]
                }
              }
            },
            'monthlyListenerCount': {
              'runs': [{'text': '75,000,000 monthly listeners'}]
            },
            'description': {
              'runs': [{'text': 'English and Albanian singer and songwriter.'}]
            }
          }
        },
        'background': {
          'thumbnail': {
            'thumbnails': [
              {'url': 'https://example.com/dualipa_banner.jpg'}
            ]
          }
        },
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        // Shelf 1: Top Songs
                        {
                          'musicShelfRenderer': {
                            'title': {
                              'runs': [{'text': 'Top songs'}]
                            },
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'playlistItemData': {'videoId': 'vid_levitating'},
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [{'text': 'Levitating'}]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [{'text': 'Dua Lipa'}]
                                        }
                                      }
                                    }
                                  ],
                                  'fixedColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [{'text': '3:23'}]
                                        }
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        },
                        // Shelf 2: Albums
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Albums'}]
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Future Nostalgia'}]
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Album'},
                                      {'text': ' • '},
                                      {'text': '2020'}
                                    ]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'MPREb_future_nostalgia',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                                        }
                                      }
                                    }
                                  },
                                  'thumbnailRenderer': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://example.com/future_nostalgia.jpg'}
                                        ]
                                      }
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        },
                        // Shelf 3: Singles & EPs
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Singles & EPs'}]
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Houdini'}]
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Single'},
                                      {'text': ' • '},
                                      {'text': '2023'}
                                    ]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'MPREb_houdini_single',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                                        }
                                      }
                                    }
                                  },
                                  'thumbnailRenderer': {
                                    'musicThumbnailRenderer': {
                                      'thumbnail': {
                                        'thumbnails': [
                                          {'url': 'https://example.com/houdini.jpg'}
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
            ]
          }
        }
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestedBrowseIds.add(body['browseId'] as String);
        return _mockJsonResponse(artistFixture);
      });

      final result = await InnerTubeService.browseArtist('UCdualipa123');
      expect(result, isNotNull);
      expect(result!.browseId, equals('UCdualipa123'));
      expect(result.name, equals('Dua Lipa'));
      expect(result.thumbnailUrl, equals('https://example.com/dualipa.jpg'));
      expect(result.bannerUrl, equals('https://example.com/dualipa_banner.jpg'));
      expect(result.subscribers, equals('23.4M subscribers'));
      expect(result.monthlyListeners, equals('75,000,000 monthly listeners'));
      expect(result.description, contains('English and Albanian singer'));

      // Top songs
      expect(result.topSongs.length, equals(1));
      expect(result.topSongs[0].id, equals('vid_levitating'));
      expect(result.topSongs[0].title, equals('Levitating'));

      // Albums (real MPREb_ browseId)
      expect(result.albums.length, equals(1));
      expect(result.albums[0].browseId, equals('MPREb_future_nostalgia'));
      expect(result.albums[0].title, equals('Future Nostalgia'));
      expect(result.albums[0].year, equals(2020));

      // Singles
      expect(result.singles.length, equals(1));
      expect(result.singles[0].browseId, equals('MPREb_houdini_single'));
      expect(result.singles[0].title, equals('Houdini'));
      expect(result.singles[0].year, equals(2023));

      expect(requestedBrowseIds, equals(['UCdualipa123']));
    });

    test('getCharts sends FEmusic_charts with formData selectedValues and parses top songs, videos, and playlists', () async {
      Map<String, dynamic>? sentBody;

      final chartsFixture = {
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        // Shelf 1: Top Songs
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Top songs'}]
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicResponsiveListItemRenderer': {
                                  'playlistItemData': {'videoId': 'chart_song_1'},
                                  'flexColumns': [
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [{'text': 'Trending Track'}]
                                        }
                                      }
                                    },
                                    {
                                      'musicResponsiveListItemFlexColumnRenderer': {
                                        'text': {
                                          'runs': [{'text': 'Chart Artist'}]
                                        }
                                      }
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        },
                        // Shelf 2: Trending Music Videos
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Trending music videos'}]
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Hit Video'}]
                                  },
                                  'subtitle': {
                                    'runs': [{'text': 'Video Artist'}]
                                  },
                                  'navigationEndpoint': {
                                    'watchEndpoint': {'videoId': 'chart_video_1'}
                                  },
                                  'musicVideoType': 'MUSIC_VIDEO_TYPE_OMV'
                                }
                              }
                            ]
                          }
                        },
                        // Shelf 3: Chart Playlists
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Top playlists'}]
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Top 50 India'}]
                                  },
                                  'subtitle': {
                                    'runs': [{'text': 'YouTube Music'}]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'VLPL_top_50_in',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
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

      InnerTubeService.clientOverride = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _mockJsonResponse(chartsFixture);
      });

      final result = await InnerTubeService.getCharts(countryCode: 'IN');
      expect(sentBody?['browseId'], equals('FEmusic_charts'));
      expect(sentBody?['formData']?['selectedValues'], equals(['IN']));

      expect(result.countryCode, equals('IN'));
      expect(result.topSongs.length, equals(1));
      expect(result.topSongs[0].id, equals('chart_song_1'));
      expect(result.topSongs[0].title, equals('Trending Track'));

      expect(result.trendingVideos.length, equals(1));
      expect(result.trendingVideos[0].id, equals('chart_video_1'));
      expect(result.trendingVideos[0].title, equals('Hit Video'));

      expect(result.playlists.length, equals(1));
      expect(result.playlists[0].id, equals('PL_top_50_in'));
      expect(result.playlists[0].title, equals('Top 50 India'));
    });

    test('getExplore parses new release albums, trending videos, and mood categories', () async {
      final exploreFixture = {
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        // New releases
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'New release albums'}]
                                },
                                'moreContentButton': {
                                  'buttonRenderer': {
                                    'navigationEndpoint': {
                                      'browseEndpoint': {'browseId': 'FEmusic_new_releases_albums'}
                                    }
                                  }
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Brand New Album'}]
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Fresh Artist'},
                                      {'text': ' • '},
                                      {'text': '2024'}
                                    ]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'MPREb_brand_new',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        },
                        // Moods and genres buttons
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [{'text': 'Moods & genres'}]
                                },
                                'moreContentButton': {
                                  'buttonRenderer': {
                                    'navigationEndpoint': {
                                      'browseEndpoint': {'browseId': 'FEmusic_moods_and_genres'}
                                    }
                                  }
                                }
                              }
                            },
                            'contents': [
                              {
                                'musicNavigationButtonRenderer': {
                                  'buttonText': {
                                    'runs': [{'text': 'Chill'}]
                                  },
                                  'solid': {'leftStripeColor': 4284572001},
                                  'clickCommand': {
                                    'browseEndpoint': {
                                      'browseId': 'FEmusic_genre_chill',
                                      'params': 'chill_params_xyz'
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

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['browseId'], equals('FEmusic_explore'));
        return _mockJsonResponse(exploreFixture);
      });

      final result = await InnerTubeService.getExplore();
      expect(result.newReleaseAlbums.length, equals(1));
      expect(result.newReleaseAlbums[0].browseId, equals('MPREb_brand_new'));
      expect(result.newReleaseAlbums[0].title, equals('Brand New Album'));

      expect(result.moodAndGenres.length, equals(1));
      expect(result.moodAndGenres[0].title, equals('Chill'));
      expect(result.moodAndGenres[0].browseId, equals('FEmusic_genre_chill'));
      expect(result.moodAndGenres[0].params, equals('chill_params_xyz'));
      expect(result.moodAndGenres[0].stripeColor, equals(4284572001));
    });

    test('getMoodsAndGenres parses categories with browseId, params, and stripeColor', () async {
      final moodsFixture = {
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
                                    'runs': [{'text': 'Workout'}]
                                  },
                                  'solid': {'leftStripeColor': 4294901760},
                                  'clickCommand': {
                                    'browseEndpoint': {
                                      'browseId': 'FEmusic_genre_workout',
                                      'params': 'workout_params_123'
                                    }
                                  }
                                }
                              },
                              {
                                'musicNavigationButtonRenderer': {
                                  'buttonText': {
                                    'runs': [{'text': 'Focus'}]
                                  },
                                  'solid': {'leftStripeColor': 4278255360},
                                  'clickCommand': {
                                    'browseEndpoint': {
                                      'browseId': 'FEmusic_genre_focus',
                                      'params': 'focus_params_456'
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

      InnerTubeService.clientOverride = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['browseId'], equals('FEmusic_moods_and_genres'));
        return _mockJsonResponse(moodsFixture);
      });

      final items = await InnerTubeService.getMoodsAndGenres();
      expect(items.length, equals(2));
      expect(items[0].title, equals('Workout'));
      expect(items[0].browseId, equals('FEmusic_genre_workout'));
      expect(items[0].params, equals('workout_params_123'));
      expect(items[0].stripeColor, equals(4294901760));

      expect(items[1].title, equals('Focus'));
      expect(items[1].browseId, equals('FEmusic_genre_focus'));
      expect(items[1].params, equals('focus_params_456'));
      expect(items[1].stripeColor, equals(4278255360));
    });

    test('browseMoodOrGenre parses hub with songs, playlists, and albums', () async {
      Map<String, dynamic>? sentBody;

      final hubFixture = {
        'header': {
          'musicHeaderRenderer': {
            'title': {
              'runs': [{'text': 'Rock Classics'}]
            }
          }
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
                          'gridRenderer': {
                            'items': [
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Rock Playlist 1'}]
                                  },
                                  'subtitle': {
                                    'runs': [{'text': 'Curated Rock'}]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'VLPL_rock_classics_pid',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                                        }
                                      }
                                    }
                                  }
                                }
                              },
                              {
                                'musicTwoRowItemRenderer': {
                                  'title': {
                                    'runs': [{'text': 'Great Rock Album'}]
                                  },
                                  'subtitle': {
                                    'runs': [
                                      {'text': 'Rock Band'},
                                      {'text': ' • '},
                                      {'text': '1975'}
                                    ]
                                  },
                                  'navigationEndpoint': {
                                    'browseEndpoint': {
                                      'browseId': 'MPREb_rock_album',
                                      'browseEndpointContextSupportedConfigs': {
                                        'browseEndpointContextMusicConfig': {
                                          'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
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

      InnerTubeService.clientOverride = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _mockJsonResponse(hubFixture);
      });

      final hubResult = await InnerTubeService.browseMoodOrGenre(
        'FEmusic_genre_rock',
        params: 'rock_params_abc',
      );

      expect(sentBody?['browseId'], equals('FEmusic_genre_rock'));
      expect(sentBody?['params'], equals('rock_params_abc'));

      expect(hubResult.title, equals('Rock Classics'));
      expect(hubResult.playlists.length, equals(1));
      expect(hubResult.playlists[0].id, equals('PL_rock_classics_pid'));
      expect(hubResult.playlists[0].title, equals('Rock Playlist 1'));

      expect(hubResult.albums.length, equals(1));
      expect(hubResult.albums[0].browseId, equals('MPREb_rock_album'));
      expect(hubResult.albums[0].title, equals('Great Rock Album'));
      expect(hubResult.albums[0].year, equals(1975));
    });
  });

  group('InnerTube Browse Missing Fields Resilience Tests', () {
    test('browseAlbum handles missing year, missing thumbnail, missing artist run safely without throwing', () async {
      final sparseAlbumFixture = {
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
                              'runs': [{'text': 'Minimal Album'}]
                            }
                            // Missing straplineTextOne, subtitle, thumbnail, description, buttons
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
                            'playlistItemData': {'videoId': 'sparse_song_1'},
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': {
                                    'runs': [{'text': 'Minimal Song'}]
                                  }
                                }
                              }
                            ]
                            // Missing fixedColumns, thumbnail, artist flex column
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
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        return _mockJsonResponse(sparseAlbumFixture);
      });

      final result = await InnerTubeService.browseAlbum('MPREb_sparse');
      expect(result, isNotNull);
      expect(result!.title, equals('Minimal Album'));
      expect(result.artist, equals('Unknown Artist'));
      expect(result.artistId, isNull);
      expect(result.year, isNull);
      expect(result.thumbnailUrl, isEmpty);
      expect(result.description, isNull);

      expect(result.songs.length, equals(1));
      expect(result.songs[0].id, equals('sparse_song_1'));
      expect(result.songs[0].title, equals('Minimal Song'));
      expect(result.songs[0].artist, equals('Unknown Artist'));
      expect(result.songs[0].duration, equals(0));
      expect(result.songs[0].thumbnailUrl, isEmpty);
    });

    test('browsePlaylist handles missing author and missing thumbnail safely without throwing', () async {
      final sparsePlaylistFixture = {
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
                              'runs': [{'text': 'Sparse Playlist'}]
                            }
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

      InnerTubeService.clientOverride = MockClient((request) async {
        return _mockJsonResponse(sparsePlaylistFixture);
      });

      final result = await InnerTubeService.browsePlaylist('PL_sparse');
      expect(result, isNotNull);
      expect(result!.browseId, equals('VLPL_sparse'));
      expect(result.title, equals('Sparse Playlist'));
      expect(result.author, isNull);
      expect(result.thumbnailUrl, isEmpty);
      expect(result.songs, isEmpty);
    });

    test('browseArtist handles missing subscribers, missing banner, missing description safely', () async {
      final sparseArtistFixture = {
        'header': {
          'musicVisualHeaderRenderer': {
            'title': {
              'runs': [{'text': 'Indie Musician'}]
            }
          }
        },
        'contents': {
          'sectionListRenderer': {
            'contents': <dynamic>[]
          }
        }
      };

      InnerTubeService.clientOverride = MockClient((request) async {
        return _mockJsonResponse(sparseArtistFixture);
      });

      final result = await InnerTubeService.browseArtist('UC_sparse_indie');
      expect(result, isNotNull);
      expect(result!.name, equals('Indie Musician'));
      expect(result.thumbnailUrl, isNull);
      expect(result.bannerUrl, isNull);
      expect(result.subscribers, isNull);
      expect(result.monthlyListeners, isNull);
      expect(result.description, isNull);
      expect(result.topSongs, isEmpty);
      expect(result.albums, isEmpty);
      expect(result.singles, isEmpty);
    });

    test('All browse endpoints handle empty response safely without throwing', () async {
      InnerTubeService.clientOverride = MockClient((request) async {
        return http.Response('{}', 200);
      });

      final album = await InnerTubeService.browseAlbum('MPREb_empty');
      expect(album, isNull);

      final playlist = await InnerTubeService.browsePlaylist('PL_empty');
      expect(playlist, isNull);

      final artist = await InnerTubeService.browseArtist('UC_empty');
      expect(artist, isNull);

      final charts = await InnerTubeService.getCharts();
      expect(charts.topSongs, isEmpty);
      expect(charts.trendingVideos, isEmpty);

      final explore = await InnerTubeService.getExplore();
      expect(explore.newReleaseAlbums, isEmpty);
      expect(explore.moodAndGenres, isEmpty);

      final moods = await InnerTubeService.getMoodsAndGenres();
      expect(moods, isEmpty);

      final hub = await InnerTubeService.browseMoodOrGenre('FEmusic_empty');
      expect(hub.songs, isEmpty);
      expect(hub.playlists, isEmpty);
      expect(hub.albums, isEmpty);
    });
  });
}
