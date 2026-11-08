import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyrics.dart';

class LyricsService {
  static final http.Client _client = http.Client();

  /// Fetch lyrics from LrcLib
  static Future<LyricsData?> fetchLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    // Clean title (remove (Official Video), feat, etc.)
    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);

    try {
      // 1. Try exact match /api/get
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (durationSeconds != null && durationSeconds > 0)
          'duration': durationSeconds.toString(),
      });

      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final synced = data['syncedLyrics'] as String?;
        final plain = data['plainLyrics'] as String?;

        if (synced != null && synced.isNotEmpty) {
          return LyricsData(
            syncedLyrics: LyricsData.parseLrc(synced),
            plainLyrics: plain,
            provider: 'LrcLib (Synced)',
          );
        } else if (plain != null && plain.isNotEmpty) {
          return LyricsData(
            plainLyrics: plain,
            provider: 'LrcLib (Plain)',
          );
        }
      }

      // 2. Fallback to /api/search
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      });

      final searchResponse = await _client.get(searchUri);
      if (searchResponse.statusCode == 200) {
        final list = jsonDecode(searchResponse.body) as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          // Find first entry with syncedLyrics
          final withSynced = list.firstWhere(
            (item) => item['syncedLyrics'] != null && (item['syncedLyrics'] as String).isNotEmpty,
            orElse: () => list.first,
          );

          final synced = withSynced['syncedLyrics'] as String?;
          final plain = withSynced['plainLyrics'] as String?;

          if (synced != null && synced.isNotEmpty) {
            return LyricsData(
              syncedLyrics: LyricsData.parseLrc(synced),
              plainLyrics: plain,
              provider: 'LrcLib (Synced)',
            );
          } else if (plain != null && plain.isNotEmpty) {
            return LyricsData(
              plainLyrics: plain,
              provider: 'LrcLib (Plain)',
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static String _cleanTitle(String title) {
    var cleaned = title;
    // Remove brackets content like (Official Video), [Audio], (feat. ...), etc.
    cleaned = cleaned.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*(official|video|audio|lyrics|feat|ft|remix|hd|4k)[^\)\]]*[\)\]]', caseSensitive: false), '');
    return cleaned.trim();
  }

  static String _cleanArtist(String artist) {
    var cleaned = artist;
    // Remove " - Topic" from YouTube generated artist channels
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '');
    return cleaned.trim();
  }
}
