import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../models/song.dart';
import '../models/search_result.dart';
import 'anti_bot_service.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'recommendation_service.dart';

class InnerTubeService {
  static const String _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static final http.Client _client = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();
  static final Map<String, List<Song>> _quickPicksMemoryCache = {};
  static final Map<String, DateTime> _quickPicksCacheTimestamp = {};
  static const Duration _cacheTtl = Duration(minutes: 3);

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': '1.20240101.01.00',
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  static Map<String, dynamic> _clientContext() => {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        }
      };

  /// Fetch search suggestions from InnerTube
  static Future<List<String>> getSearchSuggestions(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/music/get_search_suggestions'),
        headers: _headers,
        body: jsonEncode({
          ..._clientContext(),
          'input': query,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final contents = data['contents'] as List<dynamic>?;
        if (contents != null && contents.isNotEmpty) {
          final section = contents[0]['searchSuggestionsSectionRenderer'];
          final items = section?['contents'] as List<dynamic>?;
          if (items != null) {
            final suggestions = <String>[];
            for (final item in items) {
              final runs = item['searchSuggestionRenderer']?['suggestion']?['runs'] as List<dynamic>?;
              if (runs != null) {
                final text = runs.map((r) => r['text'] ?? '').join();
                if (text.isNotEmpty) suggestions.add(text);
              }
            }
            if (suggestions.isNotEmpty) return suggestions;
          }
        }
      }
    } catch (_) {}

    // Fallback to Google suggest API
    try {
      final fallbackUri = Uri.parse(
          'https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=${Uri.encodeComponent(query)}');
      final res = await _client.get(fallbackUri);
      if (res.statusCode == 200) {
        final body = res.body;
        final start = body.indexOf('(');
        final end = body.lastIndexOf(')');
        if (start != -1 && end != -1) {
          final jsonStr = body.substring(start + 1, end);
          final parsed = jsonDecode(jsonStr);
          final list = parsed[1] as List<dynamic>?;
          if (list != null) {
            return list.map((e) => e[0].toString()).take(8).toList();
          }
        }
      }
    } catch (_) {}

    return [];
  }

  /// Safely parses duration from numeric values, colon formats ("3:45", "1:23:45"), or strings.
  /// Skips non-numeric labels (e.g. "Streamed ...", "LIVE") and returns 0 instead of throwing.
  static int parseDuration(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw >= 0 ? raw : 0;
    final str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase().contains('streamed') || str.toLowerCase().contains('live')) {
      return 0;
    }
    if (str.contains(':')) {
      final parts = str.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
        final s = int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
        return (m * 60) + s;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
        final m = int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
        final s = int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) ?? 0;
        return (h * 3600) + (m * 60) + s;
      }
    }
    final digits = str.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }

  /// Safely parses view count text or dynamic value (e.g. "1,234,567 views", "Streamed", 1234).
  /// Strips non-digits and uses [int.tryParse]. Returns 0 on non-numeric labels.
  static int parseViewCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw >= 0 ? raw : 0;
    final str = raw.toString().trim();
    if (str.toLowerCase().startsWith('streamed')) return 0;
    final digits = str.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 0;
  }

  /// Safely parses published text (e.g. "Streamed 2 days ago", "Streamed live 3 hours ago", "5 years ago").
  /// Strips non-numeric prefixes like "Streamed" or "Streamed live" and uses safe integer parsing.
  /// Never throws [FormatException].
  static DateTime? parsePublishedDate(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    var cleaned = text.trim();
    if (cleaned.toLowerCase().startsWith('streamed')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^streamed(\s+live)?\s*', caseSensitive: false), '').trim();
    }
    final parts = cleaned.split(' ');
    if (parts.length < 3) return null;
    final qty = int.tryParse(parts.first.replaceAll(RegExp(r'\D'), ''));
    if (qty == null) return null;

    final unit = parts[1].toLowerCase();
    final now = DateTime.now();
    if (unit.startsWith('second')) return now.subtract(Duration(seconds: qty));
    if (unit.startsWith('minute')) return now.subtract(Duration(minutes: qty));
    if (unit.startsWith('hour')) return now.subtract(Duration(hours: qty));
    if (unit.startsWith('day')) return now.subtract(Duration(days: qty));
    if (unit.startsWith('week')) return now.subtract(Duration(days: qty * 7));
    if (unit.startsWith('month')) return now.subtract(Duration(days: qty * 30));
    if (unit.startsWith('year')) return now.subtract(Duration(days: qty * 365));
    return null;
  }

  /// Safely parses search result metadata (duration, views, published date).
  /// Returns a map with guaranteed non-null safe parsed values without throwing [FormatException].
  static Map<String, dynamic> parseSearchMetadata({
    dynamic duration,
    dynamic views,
    String? publishedText,
  }) {
    return {
      'duration': parseDuration(duration),
      'views': parseViewCount(views),
      'publishedDate': parsePublishedDate(publishedText),
    };
  }

  /// Safe fallback search using Invidious companion proxy when rate-limited or in safe mode
  static Future<SearchResult> _searchViaSafeProxy(String query) async {
    try {
      final uri = Uri.parse(
          'https://yt.chocolatemoo53.com/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final items = jsonDecode(res.body) as List<dynamic>;
        final songs = <Song>[];
        final videos = <Song>[];

        for (final item in items.take(25)) {
          final vid = item['videoId'] as String?;
          final title = item['title'] as String?;
          final author = item['author'] as String? ?? 'Unknown';
          final durationSec = parseDuration(item['lengthSeconds']);
          if (vid == null || title == null) continue;

          final song = Song(
            id: vid,
            title: title,
            artist: author,
            duration: durationSec,
            thumbnailUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            isVideo: false,
          );
          songs.add(song);
        }

        final albums = <Album>[
          Album(
            id: 'album_$query',
            title: '$query - Top Album',
            artist: songs.isNotEmpty ? songs.first.artist : 'Featured Artist',
            year: DateTime.now().year,
            thumbnailUrl: songs.isNotEmpty
                ? songs.first.thumbnailUrl
                : 'https://picsum.photos/300/300',
            songCount: songs.take(6).length,
            songs: songs.take(6).toList(),
          )
        ];

        final artists = <Artist>[
          if (songs.isNotEmpty)
            Artist(
              id: 'artist_${songs.first.artist}',
              name: songs.first.artist,
              thumbnailUrl: songs.first.thumbnailUrl,
              subscribers: '1.2M subscribers',
            )
        ];

        final playlists = <Playlist>[
          Playlist(
            id: 'playlist_$query',
            title: 'Best of $query',
            author: 'YouTube Music & Melody',
            thumbnailUrl: songs.isNotEmpty
                ? songs.first.thumbnailUrl
                : 'https://picsum.photos/300/300',
            songCount: songs.length,
            songs: songs,
          )
        ];

        return SearchResult(
          songs: songs,
          videos: videos,
          albums: albums,
          artists: artists,
          playlists: playlists,
        );
      }
    } catch (e) {
      debugPrint('InnerTubeService safe proxy search error: $e');
    }

    // Resilient fallback to YoutubeExplode if safe proxy times out or encounters network error
    try {
      final ytResults = await _ytExplode.search.search(query).timeout(const Duration(seconds: 4));
      final songs = <Song>[];
      for (final item in ytResults.take(25)) {
        final song = Song(
          id: item.id.value,
          title: item.title,
          artist: item.author,
          duration: item.duration?.inSeconds ?? 0,
          thumbnailUrl: 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
          isVideo: false,
        );
        songs.add(song);
      }
      return SearchResult(
        songs: songs,
        videos: const [],
        albums: const [],
        artists: const [],
        playlists: const [],
      );
    } catch (_) {}

    return const SearchResult();
  }

  /// Search music, albums, artists, playlists
  static Future<SearchResult> search(String query, {SearchFilter filter = SearchFilter.all}) async {
    // Record search operation for anti-bot rate tracking
    AntiBotService.recordSearch(query: query);

    // If proactive anti-bot shield is active, route search directly through safe proxy
    if (AntiBotService.isSafeModeActive) {
      LogService.info(
        'Anti-bot shield active (${AntiBotService.activeReason}). Routing search via safe proxy...',
        tag: 'InnerTubeService',
      );
      debugPrint('🛡️ InnerTubeService: Anti-bot shield active (${AntiBotService.activeReason}). Routing search via safe proxy...');
      return _searchViaSafeProxy(query);
    }

    try {
      final ytResults = await _ytExplode.search.search(query);
      final songs = <Song>[];
      final videos = <Song>[];

      for (final item in ytResults.take(25)) {
        final song = Song(
          id: item.id.value,
          title: item.title,
          artist: item.author,
          duration: item.duration?.inSeconds ?? 0,
          thumbnailUrl: 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
          isVideo: false,
        );
        songs.add(song);
      }

      final albums = <Album>[
        Album(
          id: 'album_$query',
          title: '$query - Top Album',
          artist: songs.isNotEmpty ? songs.first.artist : 'Featured Artist',
          year: DateTime.now().year,
          thumbnailUrl: songs.isNotEmpty
              ? songs.first.thumbnailUrl
              : 'https://picsum.photos/300/300',
          songCount: songs.take(6).length,
          songs: songs.take(6).toList(),
        )
      ];

      final artists = <Artist>[
        if (songs.isNotEmpty)
          Artist(
            id: 'artist_${songs.first.artist}',
            name: songs.first.artist,
            thumbnailUrl: songs.first.thumbnailUrl,
            subscribers: '1.2M subscribers',
          )
      ];

      final playlists = <Playlist>[
        Playlist(
          id: 'playlist_$query',
          title: 'Best of $query',
          author: 'YouTube Music & Melody',
          thumbnailUrl: songs.isNotEmpty
              ? songs.first.thumbnailUrl
              : 'https://picsum.photos/300/300',
          songCount: songs.length,
          songs: songs,
        )
      ];

      return SearchResult(
        songs: songs,
        videos: videos,
        albums: albums,
        artists: artists,
        playlists: playlists,
      );
    } catch (e) {
      final errStr = e.toString().toUpperCase();
      final isBotCheck = errStr.contains('403') ||
          errStr.contains('429') ||
          errStr.contains('UNPLAYABLE') ||
          errStr.contains('LOGIN_REQUIRED') ||
          errStr.contains('BOT');

      if (e is! FormatException && isBotCheck) {
        debugPrint('Direct search encountered bot check ($e). Tripping anti-bot shield & falling back to safe proxy...');
        AntiBotService.tripOnBotDetected('Search bot check: $e');
      } else {
        debugPrint('Direct search failed ($e). Falling back to safe proxy without tripping anti-bot shield...');
      }
      return _searchViaSafeProxy(query);
    }
  }

  /// Fetch Quick Picks / Home feed songs personalized by chosen music languages and listened genre algorithm.
  /// Strictly filters for single songs and leverages collaborative + content-based recommendations.
  static Future<List<Song>> getQuickPicks({
    List<String>? languages,
    String mood = 'All',
    bool forceRefresh = false,
  }) async {
    final activeLanguages = (languages != null && languages.isNotEmpty)
        ? languages
        : DatabaseService.getMusicLanguages();

    final cacheKey = '$mood:${activeLanguages.join(",")}';

    // 1. Fast cache hit: return immediately if available and within 3-minute TTL
    if (!forceRefresh) {
      final cachedAt = _quickPicksCacheTimestamp[cacheKey];
      final isFresh = cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl;

      if (isFresh &&
          _quickPicksMemoryCache.containsKey(cacheKey) &&
          _quickPicksMemoryCache[cacheKey]!.isNotEmpty) {
        return _quickPicksMemoryCache[cacheKey]!;
      }
      final diskCached = DatabaseService.getCachedFeed(cacheKey);
      if (diskCached.isNotEmpty) {
        _quickPicksMemoryCache[cacheKey] = diskCached;
        _quickPicksCacheTimestamp[cacheKey] = DateTime.now();
        return diskCached;
      }
    }

    // 2. Fetch personalized single songs based on chosen languages & listened genre algorithm
    final songs = await RecommendationService.getPersonalizedQuickPicks(
      languages: activeLanguages,
      mood: mood,
    );

    if (songs.isNotEmpty) {
      _quickPicksMemoryCache[cacheKey] = songs;
      _quickPicksCacheTimestamp[cacheKey] = DateTime.now();
      await DatabaseService.saveCachedFeed(cacheKey, songs);
      return songs;
    }

    // 3. Fallback to cached feed if present
    final diskFallback = DatabaseService.getCachedFeed(cacheKey);
    if (diskFallback.isNotEmpty) {
      return diskFallback;
    }

    return [];
  }

  /// Get related songs for Radio / Auto-mix queue
  static Future<List<Song>> getRelatedSongs(String videoId) async {
    try {
      final video = await _ytExplode.videos.get(yt.VideoId(videoId));
      final related = await _ytExplode.videos.getRelatedVideos(video);
      if (related != null) {
        return related.take(15).map((v) => Song(
              id: v.id.value,
              title: v.title,
              artist: v.author,
              duration: v.duration?.inSeconds ?? 0,
              thumbnailUrl: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
            )).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Fetch playlist songs
  static Future<List<Song>> getPlaylistSongs(String playlistId) async {
    try {
      final playlist = await _ytExplode.playlists.get(playlistId);
      final videos = await _ytExplode.playlists.getVideos(playlist.id).toList();
      return videos.map((v) => Song(
            id: v.id.value,
            title: v.title,
            artist: v.author,
            duration: v.duration?.inSeconds ?? 0,
            thumbnailUrl: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
          )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Clean up
  static void dispose() {
    _ytExplode.close();
    _client.close();
  }
}
