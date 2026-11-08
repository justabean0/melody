import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../models/song.dart';
import '../models/search_result.dart';
import 'anti_bot_service.dart';

class InnerTubeService {
  static const String _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static final http.Client _client = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

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
          final durationSec = item['lengthSeconds'] as int? ?? 0;
          if (vid == null || title == null) continue;

          final song = Song(
            id: vid,
            title: title,
            artist: author,
            duration: durationSec,
            thumbnailUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            isVideo: durationSec > 360,
          );
          if (song.isVideo) {
            videos.add(song);
          } else {
            songs.add(song);
          }
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
    return const SearchResult();
  }

  /// Search music, albums, artists, playlists
  static Future<SearchResult> search(String query, {SearchFilter filter = SearchFilter.all}) async {
    // Record search operation for anti-bot rate tracking
    AntiBotService.recordSearch(query: query);

    // If proactive anti-bot shield is active, route search directly through safe proxy
    if (AntiBotService.isSafeModeActive) {
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
          isVideo: item.duration != null && item.duration!.inSeconds > 360,
        );
        if (song.isVideo) {
          videos.add(song);
        } else {
          songs.add(song);
        }
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
      debugPrint('Direct search failed ($e). Tripping anti-bot shield & falling back to safe proxy...');
      AntiBotService.tripOnBotDetected('Search exception: $e');
      return _searchViaSafeProxy(query);
    }
  }

  /// Fetch Quick Picks / Home feed songs
  static Future<List<Song>> getQuickPicks() async {
    const trendingQueries = [
      'Top Music Hits 2026',
      'Trending Global Songs',
      'Lo-Fi Beats Chill',
    ];

    final songs = <Song>[];
    for (final q in trendingQueries) {
      try {
        final res = await _ytExplode.search.search(q);
        for (final item in res.take(6)) {
          songs.add(Song(
            id: item.id.value,
            title: item.title,
            artist: item.author,
            duration: item.duration?.inSeconds ?? 0,
            thumbnailUrl: 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
          ));
        }
      } catch (_) {}
    }

    if (songs.isNotEmpty) {
      final seen = <String>{};
      return songs.where((s) => seen.add(s.id)).toList();
    }

    return [
      const Song(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        duration: 213,
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      ),
      const Song(
        id: 'kJQP7kiw5Fk',
        title: 'Despacito',
        artist: 'Luis Fonsi ft. Daddy Yankee',
        duration: 282,
        thumbnailUrl: 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
      ),
      const Song(
        id: 'JGwWNGJdvx8',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        duration: 233,
        thumbnailUrl: 'https://i.ytimg.com/vi/JGwWNGJdvx8/hqdefault.jpg',
      ),
    ];
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
