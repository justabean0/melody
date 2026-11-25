import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../models/song.dart';
import '../models/search_result.dart';
import '../models/browse_result.dart';
import '../utils/thumbnail_utils.dart';
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

  @visibleForTesting
  static http.Client? clientOverride;
  static http.Client get _httpClient => clientOverride ?? _client;

  static const String originYouTubeMusic = 'https://music.youtube.com';
  static const String refererYouTubeMusic = 'https://music.youtube.com/';
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';

  static String clientVersion = '1.20261116.01.00';
  static String _gl = 'IN';
  static String _hl = 'en';
  static String? visitorData;
  static final RegExp _visitorDataRegex = RegExp(r'^Cg[ts]');

  /// Configures client locale parameters
  static void setLocale({String? gl, String? hl}) {
    if (gl != null && gl.isNotEmpty) _gl = gl;
    if (hl != null && hl.isNotEmpty) _hl = hl;
  }

  static String get gl => _gl;
  static String get hl => _hl;

  static Map<String, String> _headers({String? gl}) {
    final effectiveGl = (gl != null && gl.isNotEmpty) ? gl : _gl;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': defaultUserAgent,
      'X-Goog-Api-Format-Version': '1',
      'X-YouTube-Client-Name': '67',
      'X-YouTube-Client-Version': clientVersion,
      'X-Origin': originYouTubeMusic,
      'Origin': originYouTubeMusic,
      'Referer': refererYouTubeMusic,
    };
    if (effectiveGl == 'IN' && visitorData != null && visitorData!.isNotEmpty) {
      headers['X-Goog-Visitor-Id'] = visitorData!;
    }
    return headers;
  }

  static Map<String, dynamic> _clientContext({String? gl, String? hl}) {
    final effectiveGl = (gl != null && gl.isNotEmpty) ? gl : _gl;
    final effectiveHl = (hl != null && hl.isNotEmpty) ? hl : _hl;
    return {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': clientVersion,
          'hl': effectiveHl,
          'gl': effectiveGl,
          if (effectiveGl == 'IN' && visitorData != null && visitorData!.isNotEmpty)
            'visitorData': visitorData,
        }
      }
    };
  }

  /// Fetch and cache visitorData from https://music.youtube.com/sw.js_data
  static Future<String?> fetchVisitorData({bool forceRefresh = false}) async {
    if (!forceRefresh && visitorData != null && visitorData!.isNotEmpty) {
      return visitorData;
    }
    try {
      final res = await _httpClient.get(
        Uri.parse('https://music.youtube.com/sw.js_data'),
        headers: {
          'User-Agent': defaultUserAgent,
          'Referer': refererYouTubeMusic,
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        String body = res.body.trim();
        if (body.startsWith(")]}'")) {
          body = body.substring(4).trim();
        }
        final parsed = jsonDecode(body);
        if (parsed is List && parsed.isNotEmpty) {
          final first = parsed[0];
          if (first is List && first.length > 2) {
            final third = first[2];
            if (third is List) {
              for (final item in third) {
                if (item is String && _visitorDataRegex.hasMatch(item)) {
                  visitorData = item;
                  return item;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('InnerTubeService: Failed to fetch visitorData: $e');
    }
    return visitorData;
  }

  /// Shared browse endpoint caller
  static Future<Map<String, dynamic>?> _browse({
    required String browseId,
    String? params,
    Map<String, dynamic>? formData,
    String? gl,
    String? hl,
  }) async {
    final effectiveGl = (gl != null && gl.isNotEmpty) ? gl : _gl;
    final effectiveHl = (hl != null && hl.isNotEmpty) ? hl : _hl;

    try {
      if (effectiveGl == 'IN' && visitorData == null) {
        await fetchVisitorData();
      }
    } catch (_) {}

    final body = <String, dynamic>{
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': clientVersion,
          'hl': effectiveHl,
          'gl': effectiveGl,
          if (effectiveGl == 'IN' && visitorData != null && visitorData!.isNotEmpty)
            'visitorData': visitorData,
        }
      },
      'browseId': browseId,
      if (params != null && params.isNotEmpty) 'params': params,
      if (formData != null && formData.isNotEmpty) 'formData': formData,
    };

    try {
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/browse'),
        headers: _headers(gl: effectiveGl),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('InnerTubeService._browse failed for $browseId: $e');
    }
    return null;
  }

  /// Fetch search suggestions from InnerTube YouTube Music
  static Future<List<String>> getSearchSuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    try {
      if (visitorData == null) {
        await fetchVisitorData();
      }

      final body = <String, dynamic>{
        ..._clientContext(),
        'input': clean,
      };

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/music/get_search_suggestions'),
        headers: _headers(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final contents = data['contents'] as List<dynamic>?;
        if (contents != null && contents.isNotEmpty) {
          final suggestions = <String>[];
          final seen = <String>{};
          for (final section in contents) {
            if (section is! Map<String, dynamic>) continue;
            final sectionRenderer = section['searchSuggestionsSectionRenderer'] as Map<String, dynamic>?;
            final items = sectionRenderer?['contents'] as List<dynamic>?;
            if (items != null) {
              for (final item in items) {
                if (item is! Map<String, dynamic>) continue;
                final runs = item['searchSuggestionRenderer']?['suggestion']?['runs'] as List<dynamic>?;
                if (runs != null) {
                  final text = runs.map((r) => r['text']?.toString() ?? '').join('').trim();
                  if (text.isNotEmpty && seen.add(text.toLowerCase())) {
                    suggestions.add(text);
                  }
                }
              }
            }
          }
          if (suggestions.isNotEmpty) return suggestions;
        }
      }
    } catch (_) {}

    // Clean music-focused fallback only if InnerTube search suggestions fail
    try {
      final fallbackUri = Uri.parse(
          'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=${Uri.encodeComponent('$clean song')}');
      final res = await _httpClient.get(fallbackUri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        if (parsed is List && parsed.length > 1) {
          final list = parsed[1] as List<dynamic>?;
          if (list != null) {
            final filtered = <String>[];
            for (final entry in list) {
              final str = entry.toString().trim();
              if (str.isEmpty) continue;
              final lower = str.toLowerCase();
              if (lower.contains('cartoon') ||
                  lower.contains('episode') ||
                  lower.contains('gameplay') ||
                  lower.contains('full movie') ||
                  lower.contains('season')) {
                continue;
              }
              filtered.add(str);
            }
            if (filtered.isNotEmpty) {
              return filtered.take(8).toList();
            }
          }
        }
      }
    } catch (_) {}

    return [];
  }

  static final RegExp _durationPattern = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');

  /// Parses natural-language duration labels like "3 minutes, 42 seconds", "1 hour, 2 minutes, 5 seconds", "45 seconds".
  @visibleForTesting
  static int parseNaturalLanguageDuration(String? text) {
    if (text == null || text.trim().isEmpty) return 0;
    final lower = text.toLowerCase().trim();
    if (!lower.contains('second') && !lower.contains('minute') && !lower.contains('hour')) {
      return 0;
    }
    int totalSec = 0;
    final hourMatch = RegExp(r'(\d+)\s+hour').firstMatch(lower);
    if (hourMatch != null) {
      totalSec += (int.tryParse(hourMatch.group(1)!) ?? 0) * 3600;
    }
    final minMatch = RegExp(r'(\d+)\s+minute').firstMatch(lower);
    if (minMatch != null) {
      totalSec += (int.tryParse(minMatch.group(1)!) ?? 0) * 60;
    }
    final secMatch = RegExp(r'(\d+)\s+second').firstMatch(lower);
    if (secMatch != null) {
      totalSec += int.tryParse(secMatch.group(1)!) ?? 0;
    }
    return totalSec;
  }

  /// Safely parses duration from numeric seconds (int), colon formats ("3:45", "1:23:45"),
  /// or natural-language labels ("3 minutes, 42 seconds").
  /// Skips years, view counts, and non-numeric labels, returning 0 instead of throwing.
  @visibleForTesting
  static int parseDuration(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw >= 0 ? raw : 0;
    final str = raw.toString().trim();
    if (str.isEmpty ||
        str.toLowerCase().contains('streamed') ||
        str.toLowerCase().contains('live') ||
        str.toLowerCase().contains('view') ||
        str.toLowerCase().contains('play')) {
      return 0;
    }

    // 1. Strict colon pattern: M:SS, MM:SS, H:MM:SS, or HH:MM:SS
    if (_durationPattern.hasMatch(str)) {
      final parts = str.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        return (m * 60) + s;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        return (h * 3600) + (m * 60) + s;
      }
    }

    // 2. Natural language fallback: "3 minutes, 42 seconds"
    final nat = parseNaturalLanguageDuration(str);
    if (nat > 0) return nat;

    return 0;
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

  // --- Parsing Helpers for InnerTube Renderers ---

  static String _extractThumbnailUrl(dynamic renderer) {
    if (renderer == null) return '';
    List<dynamic>? thumbnails;
    if (renderer is Map<String, dynamic>) {
      if (renderer['musicThumbnailRenderer'] != null) {
        thumbnails = renderer['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List<dynamic>?;
      } else if (renderer['thumbnail'] != null) {
        thumbnails = renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
      } else if (renderer['thumbnails'] != null) {
        thumbnails = renderer['thumbnails'] as List<dynamic>?;
      }
    }
    if (thumbnails != null && thumbnails.isNotEmpty) {
      final last = thumbnails.last;
      if (last is Map<String, dynamic> && last['url'] != null) {
        return ThumbnailUtils.upgradeUrl(last['url'].toString(), size: 544);
      }
    }
    return '';
  }

  /// Upgraded duration extractor across all InnerTube song renderers.
  /// Checks in strict priority:
  /// 1) fixedColumns (both Fixed and Flex column renderers)
  /// 2) flexColumns (all columns' text runs and accessibilityData labels)
  /// 3) lengthText / thumbnailOverlayTimeStatusRenderer
  /// 4) accessibility.accessibilityData.label (natural-language duration parsing)
  static int _extractDurationFromRenderer(Map<String, dynamic> item) {
    // 1. Check fixedColumns (both Fixed and Flex column renderers)
    final fixedCols = item['fixedColumns'] as List<dynamic>?;
    if (fixedCols != null && fixedCols.isNotEmpty) {
      for (final col in fixedCols) {
        if (col is! Map<String, dynamic>) continue;
        final renderer = col['musicResponsiveListItemFixedColumnRenderer'] ??
            col['musicResponsiveListItemFlexColumnRenderer'] ??
            col;
        if (renderer is! Map<String, dynamic>) continue;
        final textObj = renderer['text'];
        final runs = _extractRuns(textObj);
        for (final r in runs) {
          final d = parseDuration(r['text']?.toString());
          if (d > 0) return d;
        }
        final a11y = textObj?['accessibility']?['accessibilityData']?['label']?.toString();
        final a11yDur = parseDuration(a11y);
        if (a11yDur > 0) return a11yDur;
      }
    }

    // 2. Check all flexColumns
    final flexCols = item['flexColumns'] as List<dynamic>?;
    if (flexCols != null && flexCols.isNotEmpty) {
      for (final col in flexCols) {
        if (col is! Map<String, dynamic>) continue;
        final renderer = col['musicResponsiveListItemFlexColumnRenderer'] ??
            col['musicResponsiveListItemFixedColumnRenderer'] ??
            col;
        if (renderer is! Map<String, dynamic>) continue;
        final textObj = renderer['text'];
        final runs = _extractRuns(textObj);
        for (final r in runs.reversed) {
          final d = parseDuration(r['text']?.toString());
          if (d > 0) return d;
        }
        final a11y = textObj?['accessibility']?['accessibilityData']?['label']?.toString();
        final a11yDur = parseDuration(a11y);
        if (a11yDur > 0) return a11yDur;
      }
    }

    // 3. Check lengthText
    if (item['lengthText'] != null) {
      final lt = parseDuration(_runsToText(item['lengthText']));
      if (lt > 0) return lt;
      final a11y = item['lengthText']?['accessibility']?['accessibilityData']?['label']?.toString();
      final a11yDur = parseDuration(a11y);
      if (a11yDur > 0) return a11yDur;
    }

    // Thumbnail overlays (time status renderer)
    final overlays = <dynamic>[
      item['thumbnailOverlay'],
      item['overlay'],
      if (item['thumbnailOverlays'] is List) ...item['thumbnailOverlays'],
    ];
    for (final ov in overlays) {
      if (ov is! Map<String, dynamic>) continue;
      final content = ov['musicItemThumbnailOverlayRenderer']?['content'] ??
          ov['content'] ??
          ov;
      if (content is! Map<String, dynamic>) continue;
      final timeRenderer = content['musicThumbnailOverlayTimeStatusRenderer'] ??
          content['thumbnailOverlayTimeStatusRenderer'];
      if (timeRenderer is Map<String, dynamic>) {
        final d = parseDuration(_runsToText(timeRenderer['text']));
        if (d > 0) return d;
      }
    }

    // Subtitle runs (common in musicTwoRowItemRenderer and musicCardShelfRenderer)
    final subtitleRuns = _extractRuns(item['subtitle']);
    for (final r in subtitleRuns.reversed) {
      final d = parseDuration(r['text']?.toString());
      if (d > 0) return d;
    }

    // 4. Fallback: item-level accessibility label
    final itemA11y = item['accessibility']?['accessibilityData']?['label']?.toString();
    final itemDur = parseDuration(itemA11y);
    if (itemDur > 0) return itemDur;

    return 0;
  }

  static List<Map<String, dynamic>> _extractRuns(dynamic runsObj) {
    if (runsObj == null) return [];
    if (runsObj is Map<String, dynamic> && runsObj['runs'] is List) {
      return (runsObj['runs'] as List).whereType<Map<String, dynamic>>().toList();
    }
    if (runsObj is List) {
      return runsObj.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  static String _runsToText(dynamic runsObj) {
    final runs = _extractRuns(runsObj);
    return runs.map((r) => r['text']?.toString() ?? '').join();
  }

  static List<List<Map<String, dynamic>>> _splitRunsBySeparator(List<Map<String, dynamic>> runs) {
    final result = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    for (final run in runs) {
      final text = run['text']?.toString() ?? '';
      if (text.trim() == '•' || text.contains('•')) {
        if (current.isNotEmpty) {
          result.add(current);
          current = <Map<String, dynamic>>[];
        }
      } else {
        current.add(run);
      }
    }
    if (current.isNotEmpty) {
      result.add(current);
    }
    return result;
  }

  static final Set<String> _artistSeparators = {
    ',',
    '&',
    '•',
    '·',
    '/',
    'and',
    'feat',
    'feat.',
    'ft',
    'ft.',
  };

  /// Cleanly formats artist runs, filtering out separators, trimming whitespace,
  /// deduplicating preserving order, and joining with ', '.
  /// Example: [{"text": "Karan Aujla"}, {"text": " & "}, {"text": "Ikky"}] -> "Karan Aujla, Ikky"
  @visibleForTesting
  static String formatArtistRuns(dynamic runsObj) {
    final runs = _extractRuns(runsObj);
    if (runs.isEmpty) return '';

    final artists = <String>[];
    for (final r in runs) {
      final rawText = r['text']?.toString().trim() ?? '';
      if (rawText.isEmpty) continue;
      if (_artistSeparators.contains(rawText.toLowerCase())) continue;

      var clean = rawText;
      for (final sep in [',', '&', '•', '·', '/']) {
        if (clean.startsWith(sep)) {
          clean = clean.substring(sep.length).trim();
        }
        if (clean.endsWith(sep)) {
          clean = clean.substring(0, clean.length - sep.length).trim();
        }
      }
      if (clean.isEmpty || _artistSeparators.contains(clean.toLowerCase())) continue;
      if (!artists.contains(clean)) {
        artists.add(clean);
      }
    }

    return artists.join(', ');
  }

  static dynamic _parseMusicCardShelfRenderer(Map<String, dynamic> card) {
    final onTap = card['onTap'] as Map<String, dynamic>? ?? {};
    final title = _runsToText(card['title']);
    final subtitleRuns = _extractRuns(card['subtitle']);
    final separatedSubtitle = _splitRunsBySeparator(subtitleRuns);
    final thumbUrl = _extractThumbnailUrl(card['thumbnail']);

    final watchEndpoint = onTap['watchEndpoint'] as Map<String, dynamic>?;
    final browseEndpoint = onTap['browseEndpoint'] as Map<String, dynamic>?;

    // 1. Song Top Result
    if (watchEndpoint != null && watchEndpoint['videoId'] != null) {
      final videoId = watchEndpoint['videoId'].toString();
      String artist = 'Unknown Artist';
      String? artistId;
      String? albumName;
      String? albumId;

      final cleaned = separatedSubtitle.where((part) => part.isNotEmpty).toList();
      if (cleaned.isNotEmpty) {
        int artistIdx = 0;
        if (cleaned.length > 1 && cleaned[0].length == 1 && cleaned[0][0]['navigationEndpoint'] == null) {
          artistIdx = 1;
        }
        if (artistIdx < cleaned.length) {
          final artistPart = cleaned[artistIdx];
          final formatted = formatArtistRuns(artistPart);
          if (formatted.isNotEmpty) {
            artist = formatted;
          }
          final firstNav = artistPart.firstWhere(
            (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
            orElse: () => {},
          );
          artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        }

        for (int i = artistIdx + 1; i < cleaned.length; i++) {
          final part = cleaned[i];
          for (final r in part) {
            final bId = r['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
            if (bId != null && bId.startsWith('MPREb_')) {
              albumName = r['text']?.toString();
              albumId = bId;
            }
          }
        }
      }

      final dur = _extractDurationFromRenderer(card);

      return Song(
        id: videoId,
        title: title,
        artist: artist.isNotEmpty ? artist : 'Unknown Artist',
        artistId: artistId,
        album: albumName,
        albumId: albumId,
        duration: dur,
        thumbnailUrl: thumbUrl,
        isVideo: false,
      );
    }

    // 2. Browse Endpoint Top Result (Artist, Album, Playlist)
    if (browseEndpoint != null && browseEndpoint['browseId'] != null) {
      final browseId = browseEndpoint['browseId'].toString();
      final config = browseEndpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig'] as Map<String, dynamic>?;
      final pageType = config?['pageType']?.toString();

      if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
        String? subscribers;
        if (subtitleRuns.isNotEmpty) {
          for (final r in subtitleRuns) {
            final t = r['text']?.toString() ?? '';
            if (t.toLowerCase().contains('subscriber')) {
              subscribers = t.trim();
            }
          }
        }
        return Artist(
          id: browseId,
          name: title,
          thumbnailUrl: thumbUrl,
          subscribers: subscribers,
        );
      }

      if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || pageType == 'MUSIC_PAGE_TYPE_AUDIOBOOK') {
        String artist = 'Unknown Artist';
        String? artistId;
        int? year;

        final cleaned = separatedSubtitle.where((part) => part.isNotEmpty).toList();
        if (cleaned.isNotEmpty) {
          int artistIdx = 0;
          if (cleaned.length > 1 && cleaned[0].length == 1 && cleaned[0][0]['navigationEndpoint'] == null) {
            artistIdx = 1;
          }
          if (artistIdx < cleaned.length) {
            final artistPart = cleaned[artistIdx];
            final formatted = formatArtistRuns(artistPart);
            if (formatted.isNotEmpty) {
              artist = formatted;
            }
            final firstNav = artistPart.firstWhere(
              (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
              orElse: () => {},
            );
            artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
          }
          for (final part in cleaned) {
            for (final r in part) {
              final y = int.tryParse(r['text']?.toString().trim() ?? '');
              if (y != null && y > 1900 && y < 2100) {
                year = y;
              }
            }
          }
        }

        String? playlistId;
        final buttons = card['buttons'] as List<dynamic>?;
        if (buttons != null && buttons.isNotEmpty) {
          for (final b in buttons) {
            final cmd = b['buttonRenderer']?['command'] as Map<String, dynamic>?;
            final pId = cmd?['watchPlaylistEndpoint']?['playlistId']?.toString() ??
                cmd?['watchEndpoint']?['playlistId']?.toString();
            if (pId != null) {
              playlistId = pId;
              break;
            }
          }
        }

        return Album(
          id: browseId,
          playlistId: playlistId,
          title: title,
          artist: artist.isNotEmpty ? artist : 'Unknown Artist',
          artistId: artistId,
          year: year,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
        final pid = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
        String? author;
        if (subtitleRuns.isNotEmpty) {
          final formatted = formatArtistRuns(subtitleRuns);
          author = formatted.isNotEmpty ? formatted : null;
        }
        return Playlist(
          id: pid,
          playlistId: pid,
          title: title,
          author: author,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      // Skip unknown / unplayable (e.g. MUSIC_PAGE_TYPE_USER_CHANNEL, podcasts, episodes)
      return null;
    }

    return null;
  }

  static dynamic _parseMusicResponsiveListItemRenderer(Map<String, dynamic> item) {
    final flexCols = item['flexColumns'] as List<dynamic>? ?? [];
    if (flexCols.isEmpty) return null;

    final col0 = flexCols[0]['musicResponsiveListItemFlexColumnRenderer'] as Map<String, dynamic>?;
    final titleRuns = _extractRuns(col0?['text']);
    if (titleRuns.isEmpty) return null;
    final title = _runsToText(titleRuns);

    final col1 = flexCols.length > 1 ? flexCols[1]['musicResponsiveListItemFlexColumnRenderer'] as Map<String, dynamic>? : null;
    final secondaryRuns = _extractRuns(col1?['text']);
    final separated = _splitRunsBySeparator(secondaryRuns);

    final col2 = flexCols.length > 2 ? flexCols[2]['musicResponsiveListItemFlexColumnRenderer'] as Map<String, dynamic>? : null;
    final thirdRuns = _extractRuns(col2?['text']);

    final thumbUrl = _extractThumbnailUrl(item['thumbnail']);

    final navEndpoint = item['navigationEndpoint'] as Map<String, dynamic>?;
    final browseEndpoint = navEndpoint?['browseEndpoint'] as Map<String, dynamic>?;

    // Check browseEndpoint types
    if (browseEndpoint != null && browseEndpoint['browseId'] != null) {
      final browseId = browseEndpoint['browseId'].toString();
      final config = browseEndpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig'] as Map<String, dynamic>?;
      final pageType = config?['pageType']?.toString();

      if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || pageType == 'MUSIC_PAGE_TYPE_AUDIOBOOK') {
        String artist = 'Unknown Artist';
        String? artistId;
        int? year;

        if (separated.isNotEmpty) {
          int artistIdx = 0;
          if (separated.length > 1 && separated[0].length == 1 && separated[0][0]['navigationEndpoint'] == null) {
            artistIdx = 1;
          }
          if (artistIdx < separated.length) {
            final artistPart = separated[artistIdx];
            final formatted = formatArtistRuns(artistPart);
            if (formatted.isNotEmpty) {
              artist = formatted;
            }
            final firstNav = artistPart.firstWhere(
              (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
              orElse: () => {},
            );
            artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
          }
          for (final part in separated) {
            for (final r in part) {
              final y = int.tryParse(r['text']?.toString().trim() ?? '');
              if (y != null && y > 1900 && y < 2100) {
                year = y;
              }
            }
          }
        }

        final playlistId = item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
            ?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchPlaylistEndpoint']?['playlistId']?.toString();

        return Album(
          id: browseId,
          playlistId: playlistId,
          title: title,
          artist: artist.isNotEmpty ? artist : 'Unknown Artist',
          artistId: artistId,
          year: year,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
        String? subscribers;
        if (secondaryRuns.isNotEmpty) {
          for (final r in secondaryRuns) {
            final t = r['text']?.toString() ?? '';
            if (t.toLowerCase().contains('subscriber')) {
              subscribers = t.trim();
            }
          }
        }
        return Artist(
          id: browseId,
          name: title,
          thumbnailUrl: thumbUrl,
          subscribers: subscribers,
        );
      }

      if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
        final pid = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
        String? author;
        if (separated.isNotEmpty) {
          final formatted = formatArtistRuns(separated[0]);
          author = formatted.isNotEmpty ? formatted : null;
        }
        return Playlist(
          id: pid,
          playlistId: pid,
          title: title,
          author: author,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      // Skip unknown / unplayable (user channel / profile, podcast, episode)
      return null;
    }

    // Check Song watchEndpoint
    final playlistItemData = item['playlistItemData'] as Map<String, dynamic>?;
    final overlayPlayNav = item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
        ?['musicPlayButtonRenderer']?['playNavigationEndpoint'] as Map<String, dynamic>?;
    final col0Nav = titleRuns.isNotEmpty ? titleRuns[0]['navigationEndpoint'] as Map<String, dynamic>? : null;

    final videoId = playlistItemData?['videoId']?.toString() ??
        navEndpoint?['watchEndpoint']?['videoId']?.toString() ??
        overlayPlayNav?['watchEndpoint']?['videoId']?.toString() ??
        col0Nav?['watchEndpoint']?['videoId']?.toString();

    if (videoId != null && videoId.isNotEmpty) {
      String artist = 'Unknown Artist';
      String? artistId;
      String? albumName;
      String? albumId;

      final allRuns = [...secondaryRuns, ...thirdRuns];
      final allSeparated = _splitRunsBySeparator(allRuns);

      if (allSeparated.isNotEmpty) {
        int artistIdx = 0;
        if (allSeparated.length > 1 && allSeparated[0].length == 1 && allSeparated[0][0]['navigationEndpoint'] == null) {
          artistIdx = 1;
        }
        if (artistIdx < allSeparated.length) {
          final artistPart = allSeparated[artistIdx];
          final formatted = formatArtistRuns(artistPart);
          if (formatted.isNotEmpty) {
            artist = formatted;
          }
          final firstNav = artistPart.firstWhere(
            (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
            orElse: () => {},
          );
          artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        }

        for (int i = artistIdx + 1; i < allSeparated.length; i++) {
          final part = allSeparated[i];
          for (final r in part) {
            final bId = r['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
            if (bId != null && bId.startsWith('MPREb_')) {
              albumName = r['text']?.toString();
              albumId = bId;
            }
          }
        }
      }

      final dur = _extractDurationFromRenderer(item);

      final musicVideoType = overlayPlayNav?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']?.toString() ??
          navEndpoint?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']?.toString();
      final isVideo = musicVideoType != null && musicVideoType != 'MUSIC_VIDEO_TYPE_ATV';

      return Song(
        id: videoId,
        title: title,
        artist: artist.isNotEmpty ? artist : 'Unknown Artist',
        artistId: artistId,
        album: albumName,
        albumId: albumId,
        duration: dur,
        thumbnailUrl: thumbUrl,
        isVideo: isVideo,
      );
    }

    return null;
  }

  @visibleForTesting
  static MoodGenreItem? parseMusicNavigationButtonRenderer(Map<String, dynamic> renderer) {
    return _parseMusicNavigationButtonRenderer(renderer);
  }

  static MoodGenreItem? _parseMusicNavigationButtonRenderer(Map<String, dynamic> renderer) {
    final title = _runsToText(renderer['buttonText']);
    if (title.isEmpty) return null;

    final clickCommand = renderer['clickCommand'] as Map<String, dynamic>?;
    final browseEndpoint = clickCommand?['browseEndpoint'] as Map<String, dynamic>?;
    final browseId = browseEndpoint?['browseId']?.toString() ?? '';
    final params = browseEndpoint?['params']?.toString();

    final solid = renderer['solid'] as Map<String, dynamic>?;
    final stripeRaw = solid?['leftStripeColor'] ?? solid?['color'];
    int? stripeColor;
    if (stripeRaw is int) {
      stripeColor = stripeRaw;
    } else if (stripeRaw != null) {
      stripeColor = int.tryParse(stripeRaw.toString());
    }

    return MoodGenreItem(
      title: title,
      browseId: browseId,
      params: params,
      stripeColor: stripeColor,
    );
  }

  @visibleForTesting
  static dynamic parseMusicTwoRowItemRenderer(Map<String, dynamic> item) {
    return _parseMusicTwoRowItemRenderer(item);
  }

  static dynamic _parseMusicTwoRowItemRenderer(Map<String, dynamic> item) {
    final title = _runsToText(item['title']);
    if (title.isEmpty) return null;

    final subtitleRuns = _extractRuns(item['subtitle']);
    final separated = _splitRunsBySeparator(subtitleRuns);
    final thumbUrl = _extractThumbnailUrl(item['thumbnailRenderer'] ?? item['thumbnail']);

    final navEndpoint = item['navigationEndpoint'] as Map<String, dynamic>?;
    final browseEndpoint = navEndpoint?['browseEndpoint'] as Map<String, dynamic>?;
    final watchEndpoint = navEndpoint?['watchEndpoint'] as Map<String, dynamic>?;

    final thumbOverlay = item['thumbnailOverlay'] as Map<String, dynamic>?;
    final playNav = thumbOverlay?['musicItemThumbnailOverlayRenderer']?['content']
        ?['musicPlayButtonRenderer']?['playNavigationEndpoint'] as Map<String, dynamic>?;

    // 1. BrowseEndpoint (Album, Playlist, Artist)
    if (browseEndpoint != null && browseEndpoint['browseId'] != null) {
      final browseId = browseEndpoint['browseId'].toString();
      final config = browseEndpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig'] as Map<String, dynamic>?;
      final pageType = config?['pageType']?.toString();

      // Album
      if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' ||
          pageType == 'MUSIC_PAGE_TYPE_AUDIOBOOK' ||
          browseId.startsWith('MPREb_')) {
        String artist = 'Unknown Artist';
        String? artistId;
        int? year;

        if (separated.isNotEmpty) {
          final firstPart = separated[0];
          final formatted = formatArtistRuns(firstPart);
          if (formatted.isNotEmpty) {
            artist = formatted;
          }
          final firstNav = firstPart.firstWhere(
            (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
            orElse: () => {},
          );
          artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
          for (final part in separated) {
            for (final r in part) {
              final y = int.tryParse(r['text']?.toString().trim() ?? '');
              if (y != null && y > 1900 && y < 2100) {
                year = y;
              }
            }
          }
        }

        final playlistId = playNav?['watchPlaylistEndpoint']?['playlistId']?.toString() ??
            playNav?['anyWatchEndpoint']?['playlistId']?.toString();

        return Album(
          id: browseId,
          playlistId: playlistId,
          title: title,
          artist: artist.isNotEmpty ? artist : 'Unknown Artist',
          artistId: artistId,
          year: year,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      // Playlist
      if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' ||
          browseId.startsWith('VL') ||
          browseId.startsWith('PL') ||
          browseId.startsWith('RDCLAK5uy_')) {
        final pid = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
        String? author;
        if (subtitleRuns.isNotEmpty) {
          final formatted = formatArtistRuns(subtitleRuns);
          author = formatted.isNotEmpty ? formatted : null;
        }
        return Playlist(
          id: pid,
          playlistId: pid,
          title: title,
          author: author,
          thumbnailUrl: thumbUrl,
          songCount: 0,
          songs: const [],
        );
      }

      // Artist
      if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC')) {
        String? subscribers;
        if (subtitleRuns.isNotEmpty) {
          subscribers = subtitleRuns.map((r) => r['text']?.toString() ?? '').join();
        }
        return Artist(
          id: browseId,
          name: title,
          thumbnailUrl: thumbUrl,
          subscribers: subscribers,
        );
      }
    }

    // 2. Song (watchEndpoint)
    final videoId = watchEndpoint?['videoId']?.toString() ??
        playNav?['watchEndpoint']?['videoId']?.toString() ??
        playNav?['anyWatchEndpoint']?['videoId']?.toString();

    if (videoId != null && videoId.isNotEmpty) {
      String artist = 'Unknown Artist';
      String? artistId;
      if (subtitleRuns.isNotEmpty) {
        if (separated.isNotEmpty) {
          final formatted = formatArtistRuns(separated[0]);
          if (formatted.isNotEmpty) artist = formatted;
          final firstNav = separated[0].firstWhere(
            (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
            orElse: () => {},
          );
          artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        } else {
          final formatted = formatArtistRuns(subtitleRuns);
          if (formatted.isNotEmpty) artist = formatted;
        }
      }

      final dur = _extractDurationFromRenderer(item);

      final musicVideoType = item['musicVideoType']?.toString() ??
          playNav?['musicVideoType']?.toString() ??
          navEndpoint?['musicVideoType']?.toString();
      final isVideo = musicVideoType != null && musicVideoType != 'MUSIC_VIDEO_TYPE_ATV';

      return Song(
        id: videoId,
        title: title,
        artist: artist,
        artistId: artistId,
        duration: dur,
        thumbnailUrl: thumbUrl,
        isVideo: isVideo,
      );
    }

    return null;
  }

  static Song? _parseAlbumSong(
    Map<String, dynamic> renderer, {
    required String defaultAlbumTitle,
    required String defaultAlbumId,
    required String defaultArtist,
    String? defaultArtistId,
    required String defaultThumbnail,
  }) {
    final playlistItemData = renderer['playlistItemData'] as Map<String, dynamic>?;
    final navEndpoint = renderer['navigationEndpoint'] as Map<String, dynamic>?;
    final overlayPlay = renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
        ?['musicPlayButtonRenderer']?['playNavigationEndpoint'] as Map<String, dynamic>?;

    final flexCols = renderer['flexColumns'] as List<dynamic>? ?? [];
    final col0Runs = flexCols.isNotEmpty
        ? _extractRuns(flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text'])
        : <Map<String, dynamic>>[];
    final col0Nav = col0Runs.isNotEmpty ? col0Runs[0]['navigationEndpoint'] as Map<String, dynamic>? : null;

    final videoId = playlistItemData?['videoId']?.toString() ??
        navEndpoint?['watchEndpoint']?['videoId']?.toString() ??
        overlayPlay?['watchEndpoint']?['videoId']?.toString() ??
        col0Nav?['watchEndpoint']?['videoId']?.toString();

    if (videoId == null || videoId.isEmpty) return null;

    final title = col0Runs.isNotEmpty ? _runsToText(col0Runs) : 'Unknown Title';

    String songArtist = defaultArtist;
    String? songArtistId = defaultArtistId;

    if (flexCols.length > 1) {
      final col1Runs = _extractRuns(flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']);
      final separated = _splitRunsBySeparator(col1Runs);
      if (separated.isNotEmpty) {
        final formatted = formatArtistRuns(separated[0]);
        if (formatted.isNotEmpty) {
          songArtist = formatted;
        }
        final firstNav = separated[0].firstWhere(
          (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
          orElse: () => {},
        );
        songArtistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
      }
    }

    final duration = _extractDurationFromRenderer(renderer);

    final thumb = _extractThumbnailUrl(renderer['thumbnail']);
    final effectiveThumb = thumb.isNotEmpty ? thumb : defaultThumbnail;

    final musicVideoType = renderer['musicVideoType']?.toString() ??
        overlayPlay?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']?.toString();
    final isVideo = musicVideoType != null && musicVideoType != 'MUSIC_VIDEO_TYPE_ATV';

    return Song(
      id: videoId,
      title: title,
      artist: songArtist.isNotEmpty ? songArtist : defaultArtist,
      artistId: songArtistId ?? defaultArtistId,
      album: defaultAlbumTitle,
      albumId: defaultAlbumId,
      duration: duration,
      thumbnailUrl: effectiveThumb,
      isVideo: isVideo,
    );
  }

  /// Parses YouTube Music search response JSON into a strongly typed [SearchResult].
  /// Matches Muzza's [SearchSummaryPage] for 'All' mode and [SearchPage] for filtered modes.
  @visibleForTesting
  static SearchResult parseSearchResponse(
    Map<String, dynamic> data, {
    SearchFilter filter = SearchFilter.all,
  }) {
    final songs = <Song>[];
    final videos = <Song>[];
    final albums = <Album>[];
    final artists = <Artist>[];
    final playlists = <Playlist>[];

    final tabs = data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List<dynamic>?;
    final tab = (tabs != null && tabs.isNotEmpty) ? tabs[0] : null;
    final sectionList = tab?['tabRenderer']?['content']?['sectionListRenderer'] as Map<String, dynamic>?;
    final sections = sectionList?['contents'] as List<dynamic>? ?? [];

    void addItem(dynamic item) {
      if (item is Song) {
        if (item.isVideo) {
          videos.add(item);
        } else {
          songs.add(item);
        }
      } else if (item is Album) {
        albums.add(item);
      } else if (item is Artist) {
        artists.add(item);
      } else if (item is Playlist) {
        playlists.add(item);
      }
    }

    dynamic topResult;
    if (filter == SearchFilter.all) {
      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;

        // 1. Top Result: musicCardShelfRenderer FIRST
        final card = section['musicCardShelfRenderer'] as Map<String, dynamic>?;
        if (card != null) {
          final top = _parseMusicCardShelfRenderer(card);
          if (top != null) {
            topResult ??= top;
            addItem(top);
          }
          final cardContents = card['contents'] as List<dynamic>?;
          if (cardContents != null) {
            for (final c in cardContents) {
              final r = c['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
              if (r != null) {
                final parsed = _parseMusicResponsiveListItemRenderer(r);
                if (parsed != null) addItem(parsed);
              }
            }
          }
        }

        // 2. musicShelfRenderer in server order
        final shelf = section['musicShelfRenderer'] as Map<String, dynamic>?;
        if (shelf != null) {
          final contents = shelf['contents'] as List<dynamic>?;
          if (contents != null) {
            for (final c in contents) {
              final r = c['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
              if (r != null) {
                final parsed = _parseMusicResponsiveListItemRenderer(r);
                if (parsed != null) addItem(parsed);
              }
            }
          }
        }

        // 3. itemSectionRenderer fallback
        final itemSection = section['itemSectionRenderer'] as Map<String, dynamic>?;
        if (itemSection != null) {
          final contents = itemSection['contents'] as List<dynamic>?;
          if (contents != null) {
            for (final c in contents) {
              final r = c['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
              if (r != null) {
                final parsed = _parseMusicResponsiveListItemRenderer(r);
                if (parsed != null) addItem(parsed);
              }
            }
          }
        }
      }
    } else {
      // Filtered mode
      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;
        final shelf = section['musicShelfRenderer'] as Map<String, dynamic>?;
        final contents = shelf?['contents'] as List<dynamic>?;
        if (contents != null) {
          for (final c in contents) {
            final r = c['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
            if (r != null) {
              final parsed = _parseMusicResponsiveListItemRenderer(r);
              if (parsed != null) addItem(parsed);
            }
          }
        }
      }
    }

    // Deduplicate items by ID
    final uniqueSongs = <String, Song>{};
    for (final s in songs) {
      uniqueSongs.putIfAbsent(s.id, () => s);
    }
    final uniqueVideos = <String, Song>{};
    for (final v in videos) {
      uniqueVideos.putIfAbsent(v.id, () => v);
    }
    final uniqueAlbums = <String, Album>{};
    for (final a in albums) {
      uniqueAlbums.putIfAbsent(a.id, () => a);
    }
    final uniqueArtists = <String, Artist>{};
    for (final a in artists) {
      uniqueArtists.putIfAbsent(a.id, () => a);
    }
    final uniquePlaylists = <String, Playlist>{};
    for (final p in playlists) {
      uniquePlaylists.putIfAbsent(p.id, () => p);
    }

    return SearchResult(
      topResult: topResult,
      songs: uniqueSongs.values.toList(),
      videos: uniqueVideos.values.toList(),
      albums: uniqueAlbums.values.toList(),
      artists: uniqueArtists.values.toList(),
      playlists: uniquePlaylists.values.toList(),
    );
  }

  /// Safe fallback search using Invidious companion proxy when rate-limited or in safe mode (songs only)
  static Future<SearchResult> _searchViaSafeProxy(String query) async {
    try {
      final uri = Uri.parse(
          'https://yt.chocolatemoo53.com/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
      final res = await _httpClient.get(uri).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final items = jsonDecode(res.body) as List<dynamic>;
        final songs = <Song>[];
        final videos = <Song>[];

        for (final item in items.take(25)) {
          final vid = item['videoId'] as String?;
          final title = item['title'] as String?;
          final author = item['author'] as String? ?? 'Unknown';
          final durationSec = (item['lengthSeconds'] is int)
              ? (item['lengthSeconds'] as int)
              : (int.tryParse(item['lengthSeconds']?.toString() ?? '') ?? 0);
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

        return SearchResult(
          songs: songs,
          videos: videos,
          albums: const [],
          artists: const [],
          playlists: const [],
        );
      }
    } catch (e) {
      debugPrint('InnerTubeService safe proxy search error: $e');
    }

    // Resilient fallback to YoutubeExplode if safe proxy times out or encounters network error (songs only)
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

  /// Search music, albums, artists, playlists using real InnerTube POST endpoint
  static Future<SearchResult> search(
    String query, {
    SearchFilter filter = SearchFilter.all,
    String? gl,
    String? hl,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const SearchResult();

    // Record search operation for anti-bot rate tracking
    AntiBotService.recordSearch(query: clean);

    // If proactive anti-bot shield is active, route search directly through safe proxy
    if (AntiBotService.isSafeModeActive) {
      LogService.info(
        'Anti-bot shield active (${AntiBotService.activeReason}). Routing search via safe proxy...',
        tag: 'InnerTubeService',
      );
      debugPrint('🛡️ InnerTubeService: Anti-bot shield active (${AntiBotService.activeReason}). Routing search via safe proxy...');
      return _searchViaSafeProxy(clean);
    }

    final effectiveGl = (gl != null && gl.isNotEmpty) ? gl : _gl;
    try {
      if (effectiveGl == 'IN' && visitorData == null) {
        await fetchVisitorData();
      }

      final body = <String, dynamic>{
        ..._clientContext(gl: effectiveGl, hl: hl),
        'query': clean,
      };
      if (filter.params != null) {
        body['params'] = filter.params;
      }

      final res = await _httpClient.post(
        Uri.parse('$_baseUrl/search'),
        headers: _headers(gl: effectiveGl),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final parsed = parseSearchResponse(data, filter: filter);
        if (!parsed.isEmpty) {
          return parsed;
        }
      } else if (res.statusCode == 403 || res.statusCode == 429) {
        AntiBotService.tripOnBotDetected('Search HTTP ${res.statusCode}');
        return _searchViaSafeProxy(clean);
      }
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
        return _searchViaSafeProxy(clean);
      } else {
        debugPrint('Direct search failed ($e). Falling back to YoutubeExplode (songs only)...');
      }
    }

    // Resilient fallback to YoutubeExplode strictly for songs (never fabricate albums)
    try {
      final ytResults = await _ytExplode.search.search(clean).timeout(const Duration(seconds: 4));
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

  static List<dynamic> _extractSectionListContents(Map<String, dynamic>? response) {
    if (response == null) return const [];
    final contents = response['contents'] as Map<String, dynamic>?;
    if (contents == null) return const [];

    final singleCol = contents['singleColumnBrowseResultsRenderer'] as Map<String, dynamic>?;
    if (singleCol != null) {
      final tabs = singleCol['tabs'] as List<dynamic>?;
      if (tabs != null && tabs.isNotEmpty && tabs[0] is Map<String, dynamic>) {
        final tab0 = tabs[0] as Map<String, dynamic>;
        final secList = tab0['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List<dynamic>?;
        if (secList != null) return secList;
      }
    }

    final twoCol = contents['twoColumnBrowseResultsRenderer'] as Map<String, dynamic>?;
    if (twoCol != null) {
      final tabs = twoCol['tabs'] as List<dynamic>?;
      if (tabs != null && tabs.isNotEmpty && tabs[0] is Map<String, dynamic>) {
        final tab0 = tabs[0] as Map<String, dynamic>;
        final secList = tab0['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List<dynamic>?;
        if (secList != null) return secList;
      }
    }

    final directSecList = contents['sectionListRenderer']?['contents'] as List<dynamic>?;
    if (directSecList != null) return directSecList;

    return const [];
  }

  static List<dynamic> _extractSecondaryContents(Map<String, dynamic>? response) {
    if (response == null) return const [];
    final twoCol = response['contents']?['twoColumnBrowseResultsRenderer'] as Map<String, dynamic>?;
    final secList = twoCol?['secondaryContents']?['sectionListRenderer']?['contents'] as List<dynamic>?;
    return secList ?? const [];
  }

  /// Browse an Album by its [browseId] (e.g. 'MPREb_...').
  /// Returns album metadata + ordered list of [Song]s.
  static Future<AlbumBrowseResult?> browseAlbum(String browseId) async {
    try {
      final response = await _browse(browseId: browseId);
      if (response == null) return null;

      final urlCanonical = response['microformat']?['microformatDataRenderer']?['urlCanonical']?.toString();
      String? playlistId = (urlCanonical != null && urlCanonical.contains('='))
          ? urlCanonical.split('=').last
          : null;

      final sections = _extractSectionListContents(response);
      final base = sections.isNotEmpty && sections[0] is Map<String, dynamic>
          ? sections[0] as Map<String, dynamic>
          : null;
      final header = base?['musicResponsiveHeaderRenderer'] as Map<String, dynamic>? ??
          response['header']?['musicResponsiveHeaderRenderer'] as Map<String, dynamic>? ??
          response['header']?['musicDetailHeaderRenderer'] as Map<String, dynamic>?;

      final title = _runsToText(header?['title']);
      if (title.isEmpty) return null;

      // Artist
      String artist = 'Unknown Artist';
      String? artistId;
      final straplineRuns = _extractRuns(header?['straplineTextOne']);
      if (straplineRuns.isNotEmpty) {
        final formatted = formatArtistRuns(straplineRuns);
        if (formatted.isNotEmpty) {
          artist = formatted;
        }
        final firstNav = straplineRuns.firstWhere(
          (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
          orElse: () => {},
        );
        artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
      } else {
        final subRuns = _extractRuns(header?['subtitle']);
        if (subRuns.isNotEmpty) {
          final formatted = formatArtistRuns(subRuns);
          artist = formatted.isNotEmpty ? formatted : 'Unknown Artist';
          final firstNav = subRuns.firstWhere(
            (r) => r['navigationEndpoint']?['browseEndpoint'] != null,
            orElse: () => {},
          );
          artistId = firstNav['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        }
      }

      // Year
      int? year;
      final subtitleRuns = _extractRuns(header?['subtitle']);
      for (final r in subtitleRuns) {
        final y = int.tryParse(r['text']?.toString().trim() ?? '');
        if (y != null && y > 1900 && y < 2100) {
          year = y;
        }
      }

      final thumbUrl = _extractThumbnailUrl(header?['thumbnail']);

      final descRuns = header?['description']?['musicDescriptionShelfRenderer']?['description'] ??
          header?['description'];
      final description = descRuns != null ? _runsToText(descRuns) : null;

      if (playlistId == null) {
        final buttons = header?['buttons'] as List<dynamic>?;
        if (buttons != null) {
          for (final b in buttons) {
            final cmd = b['buttonRenderer']?['navigationEndpoint'] ??
                b['buttonRenderer']?['command'] ??
                b['menuRenderer']?['items']?[0]?['menuNavigationItemRenderer']?['navigationEndpoint'];
            final pid = cmd?['watchPlaylistEndpoint']?['playlistId']?.toString() ??
                cmd?['watchEndpoint']?['playlistId']?.toString();
            if (pid != null) {
              playlistId = pid;
              break;
            }
          }
        }
      }

      // Parse tracks from secondaryContents or main contents
      final songs = <Song>[];
      final secondaryContents = _extractSecondaryContents(response);

      void extractSongsFromShelf(Map<String, dynamic>? shelf) {
        if (shelf == null) return;
        final items = shelf['contents'] as List<dynamic>?;
        if (items != null) {
          for (final item in items) {
            final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>? ??
                (item is Map<String, dynamic> ? item : null);
            if (renderer != null) {
              final song = _parseAlbumSong(
                renderer,
                defaultAlbumTitle: title,
                defaultAlbumId: browseId,
                defaultArtist: artist,
                defaultArtistId: artistId,
                defaultThumbnail: thumbUrl,
              );
              if (song != null) songs.add(song);
            }
          }
        }
      }

      if (secondaryContents.isNotEmpty) {
        final shelf = secondaryContents[0]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
            secondaryContents[0]['musicShelfRenderer'] as Map<String, dynamic>?;
        extractSongsFromShelf(shelf);
      }

      // If secondaryContents didn't have them, check main contents sectionList
      if (songs.isEmpty && sections.length > 1) {
        final shelf = sections[1]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
            sections[1]['musicShelfRenderer'] as Map<String, dynamic>?;
        extractSongsFromShelf(shelf);
      }

      // If songs are still empty and playlistId is available, browse VL$playlistId
      if (songs.isEmpty && playlistId != null && playlistId.isNotEmpty) {
        final plBrowseId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
        final plRes = await _browse(browseId: plBrowseId);
        if (plRes != null) {
          final plSec = _extractSecondaryContents(plRes);
          final plMain = _extractSectionListContents(plRes);
          if (plSec.isNotEmpty) {
            final shelf = plSec[0]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
                plSec[0]['musicShelfRenderer'] as Map<String, dynamic>?;
            extractSongsFromShelf(shelf);
          } else if (plMain.isNotEmpty) {
            final shelf = plMain[0]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
                plMain[0]['musicShelfRenderer'] as Map<String, dynamic>?;
            extractSongsFromShelf(shelf);
          }
        }
      }

      // Other versions
      final otherVersions = <Album>[];
      if (secondaryContents.length > 1) {
        final otherCarousel = secondaryContents[1]['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
        final otherItems = otherCarousel?['contents'] as List<dynamic>?;
        if (otherItems != null) {
          for (final item in otherItems) {
            final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>? ??
                (item is Map<String, dynamic> ? item : null);
            if (twoRow != null) {
              final parsed = _parseMusicTwoRowItemRenderer(twoRow);
              if (parsed is Album) otherVersions.add(parsed);
            }
          }
        }
      }

      return AlbumBrowseResult(
        browseId: browseId,
        playlistId: playlistId,
        title: title,
        artist: artist,
        artistId: artistId,
        year: year,
        thumbnailUrl: thumbUrl,
        description: description,
        songs: songs,
        otherVersions: otherVersions,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.browseAlbum failed for $browseId: $e\n$st');
      return null;
    }
  }

  /// Browse a Playlist by its [browseId] (e.g. 'PL...', 'RDCLAK5uy_...', or 'VL...').
  /// Normalizes [browseId] to ensure it starts with 'VL' before sending to InnerTube.
  static Future<PlaylistBrowseResult?> browsePlaylist(
    String browseId, {
    String? gl,
    String? hl,
  }) async {
    try {
      final normalizedBrowseId = browseId.startsWith('VL') ? browseId : 'VL$browseId';
      final response = await _browse(
        browseId: normalizedBrowseId,
        gl: gl,
        hl: hl,
      );
      if (response == null) return null;

      final sections = _extractSectionListContents(response);
      final base = sections.isNotEmpty && sections[0] is Map<String, dynamic>
          ? sections[0] as Map<String, dynamic>
          : null;
      final header = base?['musicResponsiveHeaderRenderer'] as Map<String, dynamic>? ??
          base?['musicEditablePlaylistDetailHeaderRenderer']?['header']?['musicResponsiveHeaderRenderer'] as Map<String, dynamic>? ??
          response['header']?['musicHeaderRenderer'] as Map<String, dynamic>? ??
          response['header']?['musicDetailHeaderRenderer'] as Map<String, dynamic>?;

      final title = _runsToText(header?['title']);
      if (title.isEmpty) return null;

      // Author
      String? author;
      String? authorId;
      final straplineRuns = _extractRuns(header?['straplineTextOne']);
      if (straplineRuns.isNotEmpty) {
        final formatted = formatArtistRuns(straplineRuns);
        author = formatted.isNotEmpty ? formatted : _runsToText(straplineRuns);
        authorId = straplineRuns.first['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
      } else {
        final subRuns = _extractRuns(header?['subtitle']);
        if (subRuns.isNotEmpty) {
          final formatted = formatArtistRuns(subRuns);
          author = formatted.isNotEmpty ? formatted : subRuns.first['text']?.toString();
          authorId = subRuns.first['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        } else {
          final facepileText = header?['facepile']?['avatarStackViewModel']?['text']?['content']?.toString();
          if (facepileText != null) {
            author = facepileText;
          }
        }
      }

      final thumbUrl = _extractThumbnailUrl(header?['thumbnail']);
      final descRuns = header?['description']?['musicDescriptionShelfRenderer']?['description'] ??
          header?['description'];
      final description = descRuns != null ? _runsToText(descRuns) : null;

      // Songs
      final songs = <Song>[];
      final secondaryContents = _extractSecondaryContents(response);

      Map<String, dynamic>? shelf;
      if (secondaryContents.isNotEmpty) {
        shelf = secondaryContents[0]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
            secondaryContents[0]['musicShelfRenderer'] as Map<String, dynamic>?;
      }
      if (shelf == null && sections.isNotEmpty) {
        shelf = sections[0]['musicPlaylistShelfRenderer'] as Map<String, dynamic>? ??
            sections[0]['musicShelfRenderer'] as Map<String, dynamic>?;
      }

      final items = shelf?['contents'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>? ??
              (item is Map<String, dynamic> ? item : null);
          if (renderer != null) {
            final parsed = _parseMusicResponsiveListItemRenderer(renderer);
            if (parsed is Song) {
              final effectiveThumb = parsed.thumbnailUrl.isNotEmpty ? parsed.thumbnailUrl : thumbUrl;
              songs.add(Song(
                id: parsed.id,
                title: parsed.title,
                artist: parsed.artist,
                artistId: parsed.artistId,
                album: parsed.album,
                albumId: parsed.albumId,
                duration: parsed.duration,
                thumbnailUrl: effectiveThumb,
                isVideo: parsed.isVideo,
              ));
            }
          }
        }
      }

      final playlistId = normalizedBrowseId.replaceFirst(RegExp(r'^VL'), '');

      return PlaylistBrowseResult(
        browseId: normalizedBrowseId,
        playlistId: playlistId,
        title: title,
        author: author,
        authorId: authorId,
        thumbnailUrl: thumbUrl,
        description: description,
        songCount: songs.length,
        songs: songs,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.browsePlaylist failed for $browseId: $e\n$st');
      return null;
    }
  }

  /// Browse an Artist by its [browseId] (e.g. 'UC...').
  /// Returns artist profile, top songs, and albums/singles lists with real browseIds.
  static Future<ArtistBrowseResult?> browseArtist(String browseId) async {
    try {
      final response = await _browse(browseId: browseId);
      if (response == null) return null;

      final immersive = response['header']?['musicImmersiveHeaderRenderer'] as Map<String, dynamic>?;
      final visual = response['header']?['musicVisualHeaderRenderer'] as Map<String, dynamic>?;
      final header = immersive ?? visual ?? (response['header'] as Map<String, dynamic>?);

      final name = _runsToText(header?['title']);
      if (name.isEmpty) return null;

      final thumbUrl = _extractThumbnailUrl(immersive?['thumbnail'] ?? visual?['foregroundThumbnail'] ?? header?['thumbnail']);
      final bannerUrl = _extractThumbnailUrl(response['background']?['thumbnail'] ?? visual?['thumbnail']);

      // Subscribers
      String? subscribers;
      final subBtn2 = immersive?['subscriptionButton2']?['subscribeButtonRenderer'];
      if (subBtn2 != null) {
        subscribers = _runsToText(subBtn2['subscriberCountWithSubscribeText']);
      }
      if (subscribers == null || subscribers.isEmpty) {
        final subBtn = immersive?['subscriptionButton']?['subscribeButtonRenderer'];
        if (subBtn != null) {
          subscribers = _runsToText(subBtn['longSubscriberCountText'] ?? subBtn['shortSubscriberCountText']);
        }
      }

      // Monthly listeners
      final monthlyListeners = _runsToText(immersive?['monthlyListenerCount']);

      // Description
      String? description;
      final descRuns = header?['description']?['musicDescriptionShelfRenderer']?['description'] ??
          header?['description'];
      if (descRuns != null) {
        description = _runsToText(descRuns);
      }

      // Sections
      final sections = _extractSectionListContents(response);

      final topSongs = <Song>[];
      final albums = <Album>[];
      final singles = <Album>[];

      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;

        if (description == null && section['musicDescriptionShelfRenderer'] != null) {
          description = _runsToText(section['musicDescriptionShelfRenderer']?['description']);
        }

        final shelf = section['musicShelfRenderer'] as Map<String, dynamic>?;
        if (shelf != null) {
          final items = shelf['contents'] as List<dynamic>?;
          if (items != null) {
            for (final item in items) {
              final renderer = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>? ??
                  (item is Map<String, dynamic> ? item : null);
              if (renderer != null) {
                final parsed = _parseMusicResponsiveListItemRenderer(renderer);
                if (parsed is Song) {
                  topSongs.add(parsed);
                }
              }
            }
          }
        }

        final carousel = section['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
        if (carousel != null) {
          final cTitle = _runsToText(carousel['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']).toLowerCase();
          final items = carousel['contents'] as List<dynamic>?;
          if (items != null) {
            for (final item in items) {
              final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
              final listItem = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
              final dynamic parsed = twoRow != null
                  ? _parseMusicTwoRowItemRenderer(twoRow)
                  : (listItem != null ? _parseMusicResponsiveListItemRenderer(listItem) : null);

              if (parsed is Album) {
                if (cTitle.contains('single') || cTitle.contains('ep')) {
                  singles.add(parsed);
                } else {
                  albums.add(parsed);
                }
              } else if (parsed is Song) {
                topSongs.add(parsed);
              }
            }
          }
        }
      }

      return ArtistBrowseResult(
        browseId: browseId,
        name: name,
        thumbnailUrl: thumbUrl.isNotEmpty ? thumbUrl : null,
        bannerUrl: bannerUrl.isNotEmpty ? bannerUrl : null,
        description: description?.isNotEmpty == true ? description : null,
        subscribers: subscribers?.isNotEmpty == true ? subscribers : null,
        monthlyListeners: monthlyListeners.isNotEmpty ? monthlyListeners : null,
        topSongs: topSongs,
        albums: albums,
        singles: singles,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.browseArtist failed for $browseId: $e\n$st');
      return null;
    }
  }

  /// Fetch regional/global Charts for [countryCode] (defaults to 'IN').
  /// Returns top songs, trending videos, and chart playlists/albums.
  static Future<ChartsResult> getCharts({String countryCode = 'IN', String? hl}) async {
    try {
      final response = await _browse(
        browseId: 'FEmusic_charts',
        formData: {'selectedValues': [countryCode]},
        gl: countryCode,
        hl: hl,
      );
      if (response == null) return ChartsResult(countryCode: countryCode);

      final sections = _extractSectionListContents(response);

      final topSongs = <Song>[];
      final trendingVideos = <Song>[];
      final playlists = <Playlist>[];
      final albums = <Album>[];

      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;
        final shelf = section['musicCarouselShelfRenderer'] as Map<String, dynamic>? ??
            section['musicShelfRenderer'] as Map<String, dynamic>?;
        if (shelf == null) continue;

        final title = _runsToText(shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title'] ?? shelf['title']).toLowerCase();
        final items = shelf['contents'] as List<dynamic>? ?? [];

        for (final item in items) {
          final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
          final listItem = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          final dynamic parsed = twoRow != null
              ? _parseMusicTwoRowItemRenderer(twoRow)
              : (listItem != null
                  ? _parseMusicResponsiveListItemRenderer(listItem)
                  : (item is Map<String, dynamic>
                      ? (_parseMusicTwoRowItemRenderer(item) ?? _parseMusicResponsiveListItemRenderer(item))
                      : null));

          if (parsed is Song) {
            if (title.contains('video') || title.contains('clip') || parsed.isVideo) {
              trendingVideos.add(parsed);
            } else {
              topSongs.add(parsed);
            }
          } else if (parsed is Playlist) {
            playlists.add(parsed);
          } else if (parsed is Album) {
            albums.add(parsed);
          }
        }
      }

      return ChartsResult(
        countryCode: countryCode,
        topSongs: topSongs,
        trendingVideos: trendingVideos,
        playlists: playlists,
        albums: albums,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.getCharts failed: $e\n$st');
      return ChartsResult(countryCode: countryCode);
    }
  }

  /// Fetch Explore hub (New releases, trending clips, and mood categories).
  static Future<ExploreResult> getExplore({String? gl, String? hl}) async {
    try {
      final response = await _browse(browseId: 'FEmusic_explore', gl: gl, hl: hl);
      if (response == null) return const ExploreResult();

      final sections = _extractSectionListContents(response);

      final newReleaseAlbums = <Album>[];
      final trendingVideos = <Song>[];
      final moodAndGenres = <MoodGenreItem>[];

      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;
        final carousel = section['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
        final grid = section['gridRenderer'] as Map<String, dynamic>?;

        if (carousel != null) {
          final moreBrowseId = carousel['header']?['musicCarouselShelfBasicHeaderRenderer']
              ?['moreContentButton']?['buttonRenderer']?['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
          final title = _runsToText(carousel['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']).toLowerCase();
          final items = carousel['contents'] as List<dynamic>? ?? [];

          if (moreBrowseId == 'FEmusic_new_releases_albums' || title.contains('album') || title.contains('release')) {
            for (final item in items) {
              final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>? ?? (item is Map<String, dynamic> ? item : null);
              if (twoRow != null) {
                final parsed = _parseMusicTwoRowItemRenderer(twoRow);
                if (parsed is Album) newReleaseAlbums.add(parsed);
              }
            }
          } else if (moreBrowseId == 'FEmusic_new_releases_videos' || title.contains('video') || title.contains('clip')) {
            for (final item in items) {
              final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>? ?? (item is Map<String, dynamic> ? item : null);
              if (twoRow != null) {
                final parsed = _parseMusicTwoRowItemRenderer(twoRow);
                if (parsed is Song) trendingVideos.add(parsed);
              }
            }
          } else if (moreBrowseId == 'FEmusic_moods_and_genres' || title.contains('mood') || title.contains('genre')) {
            for (final item in items) {
              final btn = item['musicNavigationButtonRenderer'] as Map<String, dynamic>? ?? (item is Map<String, dynamic> ? item : null);
              if (btn != null) {
                final parsed = _parseMusicNavigationButtonRenderer(btn);
                if (parsed != null) moodAndGenres.add(parsed);
              }
            }
          } else {
            for (final item in items) {
              final btn = item['musicNavigationButtonRenderer'] as Map<String, dynamic>?;
              if (btn != null) {
                final parsed = _parseMusicNavigationButtonRenderer(btn);
                if (parsed != null) moodAndGenres.add(parsed);
                continue;
              }
              final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>? ?? (item is Map<String, dynamic> ? item : null);
              if (twoRow != null) {
                final parsed = _parseMusicTwoRowItemRenderer(twoRow);
                if (parsed is Album) {
                  newReleaseAlbums.add(parsed);
                } else if (parsed is Song) {
                  trendingVideos.add(parsed);
                }
              }
            }
          }
        }

        if (grid != null) {
          final items = grid['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final btn = item['musicNavigationButtonRenderer'] as Map<String, dynamic>? ?? (item is Map<String, dynamic> ? item : null);
            if (btn != null) {
              final parsed = _parseMusicNavigationButtonRenderer(btn);
              if (parsed != null) moodAndGenres.add(parsed);
            }
          }
        }
      }

      return ExploreResult(
        newReleaseAlbums: newReleaseAlbums,
        trendingVideos: trendingVideos,
        moodAndGenres: moodAndGenres,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.getExplore failed: $e\n$st');
      return const ExploreResult();
    }
  }

  /// Fetch all Mood & Genre categories from 'FEmusic_moods_and_genres'.
  static Future<List<MoodGenreItem>> getMoodsAndGenres({String? gl, String? hl}) async {
    try {
      final response = await _browse(browseId: 'FEmusic_moods_and_genres', gl: gl, hl: hl);
      if (response == null) return const [];

      final sections = _extractSectionListContents(response);

      final result = <MoodGenreItem>[];
      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;
        final grid = section['gridRenderer'] as Map<String, dynamic>?;
        final carousel = section['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
        final items = (grid?['items'] ?? carousel?['contents']) as List<dynamic>? ?? [];

        for (final item in items) {
          final btn = item['musicNavigationButtonRenderer'] as Map<String, dynamic>? ??
              (item is Map<String, dynamic> && item['buttonText'] != null ? item : null);
          if (btn != null) {
            final parsed = _parseMusicNavigationButtonRenderer(btn);
            if (parsed != null) result.add(parsed);
          }
        }
      }
      return result;
    } catch (e, st) {
      debugPrint('InnerTubeService.getMoodsAndGenres failed: $e\n$st');
      return const [];
    }
  }

  /// Browse a specific Mood or Genre hub by [browseId] and optional [params].
  static Future<MoodGenreBrowseResult> browseMoodOrGenre(
    String browseId, {
    String? params,
    String? gl,
    String? hl,
  }) async {
    try {
      final response = await _browse(browseId: browseId, params: params, gl: gl, hl: hl);
      if (response == null) return const MoodGenreBrowseResult(title: '');

      final title = _runsToText(response['header']?['musicHeaderRenderer']?['title'] ?? response['header']?['title']);

      final sections = _extractSectionListContents(response);

      final songs = <Song>[];
      final playlists = <Playlist>[];
      final albums = <Album>[];

      for (final section in sections) {
        if (section is! Map<String, dynamic>) continue;
        final shelf = section['gridRenderer'] as Map<String, dynamic>? ??
            section['musicCarouselShelfRenderer'] as Map<String, dynamic>? ??
            section['musicShelfRenderer'] as Map<String, dynamic>?;
        if (shelf == null) continue;

        final items = (shelf['items'] ?? shelf['contents']) as List<dynamic>? ?? [];
        for (final item in items) {
          final twoRow = item['musicTwoRowItemRenderer'] as Map<String, dynamic>?;
          final listItem = item['musicResponsiveListItemRenderer'] as Map<String, dynamic>?;
          final dynamic parsed = twoRow != null
              ? _parseMusicTwoRowItemRenderer(twoRow)
              : (listItem != null
                  ? _parseMusicResponsiveListItemRenderer(listItem)
                  : (item is Map<String, dynamic>
                      ? (_parseMusicTwoRowItemRenderer(item) ?? _parseMusicResponsiveListItemRenderer(item))
                      : null));

          if (parsed is Song) {
            songs.add(parsed);
          } else if (parsed is Playlist) {
            playlists.add(parsed);
          } else if (parsed is Album) {
            albums.add(parsed);
          }
        }
      }

      return MoodGenreBrowseResult(
        title: title,
        songs: songs,
        playlists: playlists,
        albums: albums,
      );
    } catch (e, st) {
      debugPrint('InnerTubeService.browseMoodOrGenre failed: $e\n$st');
      return const MoodGenreBrowseResult(title: '');
    }
  }

  /// Clears in-memory quick picks cache
  static void clearQuickPicksCache() {
    _quickPicksMemoryCache.clear();
    _quickPicksCacheTimestamp.clear();
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
      final cachedAt = _quickPicksCacheTimestamp[cacheKey] ??
          DatabaseService.getCachedFeedTimestamp(cacheKey);
      final isFresh = cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl;

      if (isFresh &&
          _quickPicksMemoryCache.containsKey(cacheKey) &&
          _quickPicksMemoryCache[cacheKey]!.isNotEmpty) {
        final memHits = _quickPicksMemoryCache[cacheKey]!;
        LogService.info(
          'getQuickPicks cache=MEMORY key="$cacheKey" activeLanguages=$activeLanguages mood=$mood songs=${memHits.length}',
          tag: 'Feed',
        );
        return memHits;
      }
      final diskCached = DatabaseService.getCachedFeed(cacheKey);
      if (diskCached.isNotEmpty && isFresh) {
        _quickPicksMemoryCache[cacheKey] = diskCached;
        _quickPicksCacheTimestamp[cacheKey] = cachedAt;
        LogService.info(
          'getQuickPicks cache=DISK key="$cacheKey" activeLanguages=$activeLanguages mood=$mood songs=${diskCached.length}',
          tag: 'Feed',
        );
        return diskCached;
      }
    }

    LogService.info(
      'getQuickPicks cache=MISS(fresh) key="$cacheKey" activeLanguages=$activeLanguages mood=$mood forceRefresh=$forceRefresh',
      tag: 'Feed',
    );

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
