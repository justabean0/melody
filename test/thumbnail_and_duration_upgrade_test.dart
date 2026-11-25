import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody/models/song.dart';
import 'package:melody/services/database_service.dart';
import 'package:melody/services/innertube_service.dart';
import 'package:melody/utils/thumbnail_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ThumbnailUtils.upgradeUrl Tests', () {
    test('upgrades lh3 and yt3 googleusercontent thumbnail size parameters to 544 and 1080', () {
      const lowRes1 = 'https://lh3.googleusercontent.com/fife/ABX_sample=w60-h60-l90-rj';
      expect(
        ThumbnailUtils.upgradeUrl(lowRes1, size: 544),
        equals('https://lh3.googleusercontent.com/fife/ABX_sample=w544-h544-l90-rj'),
      );
      expect(
        ThumbnailUtils.upgradeUrl(lowRes1, size: 1080),
        equals('https://lh3.googleusercontent.com/fife/ABX_sample=w1080-h1080-l90-rj'),
      );

      const lowRes2 = 'https://lh3.googleusercontent.com/a-/ALV-UjVxyz=s120-c-k-c0x00ffffff-no-rj';
      expect(
        ThumbnailUtils.upgradeUrl(lowRes2, size: 544),
        equals('https://lh3.googleusercontent.com/a-/ALV-UjVxyz=w544-h544-l90-rj'),
      );

      const lowResYt3 = 'https://yt3.googleusercontent.com/xyz123=w120-h120-p-l90-rj';
      expect(
        ThumbnailUtils.upgradeUrl(lowResYt3, size: 544),
        equals('https://yt3.googleusercontent.com/xyz123=w544-h544-l90-rj'),
      );
    });

    test('upgrades yt3.ggpht.com thumbnail parameters to specified size', () {
      const ggphtUrl = 'https://yt3.ggpht.com/channel-art-xyz=s120-c-k-c0x00ffffff-no-rj';
      expect(
        ThumbnailUtils.upgradeUrl(ggphtUrl, size: 544),
        equals('https://yt3.ggpht.com/channel-art-xyz=w544-h544-l90-rj'),
      );
      expect(
        ThumbnailUtils.upgradeUrl(ggphtUrl, size: 1080),
        equals('https://yt3.ggpht.com/channel-art-xyz=w1080-h1080-l90-rj'),
      );
    });

    test('upgrades i.ytimg.com and i9.ytimg.com from default/mqdefault to hqdefault', () {
      const defaultYt = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg';
      expect(
        ThumbnailUtils.upgradeUrl(defaultYt),
        equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      );

      const mqdefaultYt = 'https://i9.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
      expect(
        ThumbnailUtils.upgradeUrl(mqdefaultYt),
        equals('https://i9.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      );
    });

    test('handles null and empty URLs gracefully', () {
      expect(ThumbnailUtils.upgradeUrl(null), equals(''));
      expect(ThumbnailUtils.upgradeUrl('   '), equals(''));
      expect(ThumbnailUtils.upgradeUrl('https://example.com/image.png'), equals('https://example.com/image.png'));
    });
  });

  group('Duration Parsing & Natural-Language Fallback Tests', () {
    test('parses standard digital timestamps', () {
      expect(InnerTubeService.parseDuration('3:42'), equals(222));
      expect(InnerTubeService.parseDuration('0:45'), equals(45));
      expect(InnerTubeService.parseDuration('1:02:05'), equals(3725));
    });

    test('parses natural language duration strings from accessibility labels', () {
      expect(InnerTubeService.parseNaturalLanguageDuration('3 minutes, 42 seconds'), equals(222));
      expect(InnerTubeService.parseNaturalLanguageDuration('1 hour, 2 minutes, 5 seconds'), equals(3725));
      expect(InnerTubeService.parseNaturalLanguageDuration('45 seconds'), equals(45));
      expect(InnerTubeService.parseNaturalLanguageDuration('58 seconds'), equals(58));
      expect(InnerTubeService.parseNaturalLanguageDuration('1 minute'), equals(60));
      expect(InnerTubeService.parseNaturalLanguageDuration('2 hours'), equals(7200));

      // Also tested via parseDuration fallback
      expect(InnerTubeService.parseDuration('3 minutes, 42 seconds'), equals(222));
      expect(InnerTubeService.parseDuration('45 seconds'), equals(45));
    });

    test('parses duration from fixedColumns in musicResponsiveListItemRenderer', () {
      final item = {
        'playlistItemData': {'videoId': 'vid123'},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Chill Song Title'}
                ]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Chill Artist', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UC123'}}}
                ]
              }
            }
          }
        ],
        'fixedColumns': [
          {
            'musicResponsiveListItemFixedColumnRenderer': {
              'text': {
                'runs': [
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
                {'url': 'https://lh3.googleusercontent.com/test=w120-h120'}
              ]
            }
          }
        }
      };

      final parsed = InnerTubeService.parseSearchResponse({
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
                              {'musicResponsiveListItemRenderer': item}
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

      expect(parsed.songs, hasLength(1));
      final song = parsed.songs.first;
      expect(song.title, equals('Chill Song Title'));
      expect(song.duration, equals(225)); // 3 * 60 + 45
      expect(song.thumbnailUrl, contains('=w544-h544-l90-rj'));
    });
  });

  group('Multi-Artist Formatting & TwoRowItem Parsing Tests', () {
    test('properly formats collaborating artists in formatArtistRuns', () {
      final runs = [
        {'text': 'Chris Grey', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UCchris'}}},
        {'text': ' & '},
        {'text': 'Allegra Jordyn', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UCallegra'}}}
      ];

      final formatted = InnerTubeService.formatArtistRuns(runs);
      expect(formatted, equals('Chris Grey, Allegra Jordyn'));
    });

    test('preserves second artist even if second artist lacks browseId', () {
      final runs = [
        {'text': 'Chris Grey', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UCchris'}}},
        {'text': ' feat. '},
        {'text': 'Allegra Jordyn'}
      ];

      final formatted = InnerTubeService.formatArtistRuns(runs);
      expect(formatted, equals('Chris Grey, Allegra Jordyn'));
    });
  });

  group('DatabaseService Feed Cache Versioning Tests', () {
    test('getCachedFeed and saveCachedFeed use v4 cache key', () async {
      SharedPreferences.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(db);
      await DatabaseService.init();

      final testSongs = [
        const Song(
          id: 'test_1',
          title: 'Cached Track',
          artist: 'Cached Artist',
          thumbnailUrl: 'https://lh3.googleusercontent.com/test=w60-h60',
          duration: 180,
        ),
      ];

      await DatabaseService.saveCachedFeed('Chill', testSongs);

      final loaded = DatabaseService.getCachedFeed('Chill');
      expect(loaded, hasLength(1));
      expect(loaded.first.id, equals('test_1'));
      expect(loaded.first.title, equals('Cached Track'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('melody_feed_cache_v4_Chill'), isTrue);
      expect(prefs.containsKey('melody_feed_cache_Chill'), isFalse);
    });

    test('DatabaseService.init purges older unversioned feed caches', () async {
      SharedPreferences.setMockInitialValues({
        'melody_feed_cache_Chill': jsonEncode([
          {'id': 'stale_1', 'title': 'Stale Track', 'artist': 'Stale', 'thumbnailUrl': '', 'duration': 0}
        ]),
        'melody_feed_cache_v2_Workout': jsonEncode([
          {'id': 'stale_2', 'title': 'Stale v2', 'artist': 'Stale', 'thumbnailUrl': '', 'duration': 0}
        ]),
        'melody_feed_cache_v3_Focus': jsonEncode([
          {'id': 'stale_3', 'title': 'Stale v3', 'artist': 'Stale', 'thumbnailUrl': '', 'duration': 200}
        ]),
        'melody_feed_cache_v4_Focus': jsonEncode([
          {'id': 'fresh_1', 'title': 'Fresh v4', 'artist': 'Fresh', 'thumbnailUrl': '', 'duration': 200}
        ]),
      });

      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      DatabaseService.setDatabaseForTesting(db);
      await DatabaseService.init();
      final prefs = await SharedPreferences.getInstance();

      // Older unversioned, v2, and v3 keys purged
      expect(prefs.containsKey('melody_feed_cache_Chill'), isFalse);
      expect(prefs.containsKey('melody_feed_cache_v2_Workout'), isFalse);
      expect(prefs.containsKey('melody_feed_cache_v3_Focus'), isFalse);

      // Current v4 key preserved
      expect(prefs.containsKey('melody_feed_cache_v4_Focus'), isTrue);
      final preserved = DatabaseService.getCachedFeed('Focus');
      expect(preserved, hasLength(1));
      expect(preserved.first.id, equals('fresh_1'));
    });
  });
}
