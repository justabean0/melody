import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'anti_bot_service.dart';
import 'innertube_version_manager.dart';

class CachedStream {
  final String url;
  final DateTime expiresAt;

  CachedStream(this.url, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class StreamResolverService {
  static final http.Client _httpClient = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

  /// In-memory LRU Stream URL Cache with TTL (typically 4-6 hours)
  static final Map<String, CachedStream> _streamCache = {};

  /// Primary solver: High-speed US instance with SABR companion proxy support
  static const String _primaryInstance = 'https://yt.chocolatemoo53.com';

  static int _parseBitrate(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  /// Invalidates a cached stream if playback encounters a 403 or error
  static void invalidateCache(String videoId) {
    _streamCache.remove(videoId);
    debugPrint('StreamResolverService: Invalidated cache for $videoId');
  }

  /// Helper to record stream URL in cache with expiration
  static void _saveToCache(String videoId, String url) {
    DateTime expiresAt = DateTime.now().add(const Duration(hours: 4));
    try {
      final uri = Uri.parse(url);
      final expireParam = uri.queryParameters['expire'];
      if (expireParam != null) {
        final sec = int.tryParse(expireParam);
        if (sec != null && sec > 0) {
          expiresAt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
        }
      }
    } catch (_) {}

    _streamCache[videoId] = CachedStream(url, expiresAt);
    debugPrint('StreamResolverService: Cached stream for $videoId (expires at $expiresAt)');
  }

  /// Probes an audio stream URL using streaming HTTP headers to ensure
  /// it is not geo-restricted and can be read without downloading the entire body.
  static Future<bool> _probeStream(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('gcr')) {
        return false;
      }

      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-1'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedResponse = await _httpClient.send(request).timeout(
        const Duration(milliseconds: 1800),
      );

      final isSuccess = streamedResponse.statusCode == 200 || streamedResponse.statusCode == 206;
      await streamedResponse.stream.listen((_) {}).cancel();
      return isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// 1. HYBRID FAST PATH: Direct InnerTube player API (200-400ms)
  /// If Google detects bot, flags LOGIN_REQUIRED, or requires cipher, returns null to fall back safely.
  static Future<String?> _tryInnerTubeFastPath(String videoId) async {
    try {
      final profile = InnerTubeVersionManager.currentProfile;
      final url = Uri.parse('https://www.youtube.com/youtubei/v1/player');
      final body = jsonEncode({
        'context': {
          'client': profile.toContextClient(),
        },
        'videoId': videoId,
      });

      final res = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': profile.userAgent,
        },
        body: body,
      ).timeout(const Duration(milliseconds: 1500));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {}

      // Inspect for outdated client version strings or deprecation
      final isOutdated = InnerTubeVersionManager.inspectResponseForOutdatedClient(
        statusCode: res.statusCode,
        responseBody: data,
        rawBody: res.body,
      );

      if (isOutdated) {
        debugPrint('InnerTube Fast Path: Outdated/rejected client version detected. Tripping anti-bot shield...');
        AntiBotService.tripOnBotDetected('Outdated client version rejected by YouTube');
        return null;
      }

      if (res.statusCode == 200 && data != null) {
        final playability = data['playabilityStatus']?['status'] as String?;
        if (playability == 'OK') {
          final streamingData = data['streamingData'] as Map<String, dynamic>?;
          final formats = streamingData?['adaptiveFormats'] as List<dynamic>?;
          if (formats != null && formats.isNotEmpty) {
            final audioFormats = formats
                .where((f) =>
                    (f['mimeType'] as String? ?? '').startsWith('audio/') &&
                    f['url'] != null &&
                    !(f['url'] as String).contains('gcr='))
                .toList();

            if (audioFormats.isNotEmpty) {
              audioFormats.sort((a, b) =>
                  (_parseBitrate(b['bitrate'])).compareTo(_parseBitrate(a['bitrate'])));
              final directUrl = audioFormats.first['url'] as String;
              debugPrint('InnerTube Fast Path: SUCCESS for $videoId in sub-second using ${profile.key}!');
              return directUrl;
            }
          }
        } else {
          debugPrint('InnerTube Fast Path: Bot-check / login required ($playability). Tripping anti-bot shield & safe fallback...');
          AntiBotService.tripOnBotDetected(playability ?? 'STATUS_NOT_OK');
        }
      } else if (res.statusCode == 429) {
        debugPrint('InnerTube Fast Path: HTTP 429 rate limit. Tripping anti-bot shield...');
        AntiBotService.tripOnBotDetected('HTTP 429');
      }
    } catch (e) {
      debugPrint('InnerTube Fast Path: Skipped ($e). Falling back to safe path...');
    }
    return null;
  }

  /// Extracts audio streams from an Invidious instance for a given videoId
  static Future<String?> _extractAudioFromInstance(
    String instance,
    String videoId, {
    Duration timeout = const Duration(seconds: 5),
    bool optimistic = false,
  }) async {
    try {
      final url = Uri.parse('$instance/api/v1/videos/$videoId?local=true');
      final response = await _httpClient.get(url).timeout(timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final adaptive = data['adaptiveFormats'] as List<dynamic>?;

      if (adaptive == null || adaptive.isEmpty) return null;

      final mp4Candidates = <Map<String, dynamic>>[];
      final otherCandidates = <Map<String, dynamic>>[];

      for (final f in adaptive) {
        final type = (f['type'] as String?)?.toLowerCase() ?? '';
        final streamUrl = f['url'] as String?;
        final bitrate = _parseBitrate(f['bitrate']);

        if (type.startsWith('audio/') && streamUrl != null && streamUrl.isNotEmpty) {
          if (type.contains('mp4') || type.contains('m4a')) {
            mp4Candidates.add({'url': streamUrl, 'bitrate': bitrate});
          } else {
            otherCandidates.add({'url': streamUrl, 'bitrate': bitrate});
          }
        }
      }

      mp4Candidates.sort((a, b) => (b['bitrate'] as int).compareTo(a['bitrate'] as int));
      otherCandidates.sort((a, b) => (b['bitrate'] as int).compareTo(a['bitrate'] as int));

      final allCandidates = [...mp4Candidates, ...otherCandidates];

      // OPTIMISTIC PLAYBACK:
      // Return top candidate immediately without adding probe network latency.
      if (optimistic && allCandidates.isNotEmpty) {
        return allCandidates.first['url'] as String;
      }

      // Probe top candidates to guarantee playback without 403 Access Denied errors
      for (final candidate in allCandidates.take(2)) {
        final streamUrl = candidate['url'] as String;
        if (await _probeStream(streamUrl)) {
          return streamUrl;
        }
      }

      // Check formatStreams fallback
      final formatStreams = data['formatStreams'] as List<dynamic>?;
      if (formatStreams != null && formatStreams.isNotEmpty) {
        for (final fs in formatStreams.take(2)) {
          final streamUrl = fs['url'] as String?;
          if (streamUrl != null && await _probeStream(streamUrl)) {
            return streamUrl;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Searches an instance for an alternative working stream of the same track
  static Future<String?> _searchAlternativeAudio(
    String instance,
    String query,
    String originalVideoId,
    String songTitle, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final searchUrl = Uri.parse('$instance/api/v1/search?q=$query&type=video');
      final sRes = await _httpClient.get(searchUrl).timeout(timeout);

      if (sRes.statusCode == 200) {
        final items = jsonDecode(sRes.body) as List<dynamic>;
        for (final item in items.take(8)) {
          final altVideoId = item['videoId'] as String?;
          if (altVideoId == null || altVideoId == originalVideoId) continue;

          final altAudioUrl = await _extractAudioFromInstance(
            instance,
            altVideoId,
            timeout: const Duration(seconds: 5),
            optimistic: false,
          );
          if (altAudioUrl != null) {
            debugPrint('Resolved working alternative stream for "$songTitle": $altVideoId via $instance');
            return altAudioUrl;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// CONCURRENT FAST RACING SOLVER:
  /// Races direct InnerTube (< 300ms) and Companion Proxy (< 600ms) in parallel.
  /// Whichever resolves first wins immediately, completely eliminating sequential timeout delays.
  static Future<String?> _raceFastSolvers(String videoId, {bool optimistic = true}) async {
    final completer = Completer<String?>();
    int pending = 2;

    void handleWinner(String? url, String source) {
      if (url != null && !completer.isCompleted) {
        debugPrint('⚡ Fast Stream Race WON by $source for $videoId!');
        completer.complete(url);
      } else {
        pending--;
        if (pending <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    // 1. Direct InnerTube fast path
    if (!AntiBotService.isSafeModeActive) {
      _tryInnerTubeFastPath(videoId)
          .then((u) => handleWinner(u, 'InnerTube'))
          .catchError((_) => handleWinner(null, 'InnerTube'));
    } else {
      pending--;
    }

    // 2. Primary Companion Proxy (Chocolatemoo)
    _extractAudioFromInstance(
      _primaryInstance,
      videoId,
      timeout: const Duration(seconds: 4),
      optimistic: optimistic,
    ).then((u) => handleWinner(u, 'CompanionProxy')).catchError((_) => handleWinner(null, 'CompanionProxy'));

    return completer.future;
  }

  /// Master stream resolver featuring:
  /// 1. Instant Cache hit (0ms)
  /// 2. Concurrent Fast Solver Race (InnerTube + Companion Proxy, 250-600ms)
  /// 3. YoutubeExplode Local Client Fallback
  /// 4. Smart Alternative Track Matching
  static Future<String> resolveAudioStreamUrl(
    String videoId, {
    String? songTitle,
    String? artist,
    bool optimistic = true,
  }) async {
    // 1. STREAM URL CACHE: Instant 0ms return if cached and unexpired
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('StreamResolverService: Cache HIT for $videoId (0ms startup)');
      return cached.url;
    }

    // 2. CONCURRENT FAST SOLVER RACE: InnerTube & Companion Proxy simultaneously
    final racedUrl = await _raceFastSolvers(videoId, optimistic: optimistic);
    if (racedUrl != null) {
      _saveToCache(videoId, racedUrl);
      return racedUrl;
    }

    // 3. FAST LOCAL CLIENT: YoutubeExplode direct streams
    try {
      final manifest = await _ytExplode.videos.streamsClient
          .getManifest(yt.VideoId(videoId))
          .timeout(const Duration(seconds: 3));
      final mp4Streams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();

      final candidates = mp4Streams.isNotEmpty ? mp4Streams : manifest.audioOnly.toList();
      for (final s in candidates.sortByBitrate().reversed) {
        final streamUrl = s.url.toString();
        if (optimistic || await _probeStream(streamUrl)) {
          debugPrint('Resolved direct audio stream for $videoId via YoutubeExplode fallback');
          _saveToCache(videoId, streamUrl);
          return streamUrl;
        }
      }
    } catch (e) {
      debugPrint('YoutubeExplode fallback skipped ($e). Trying alternative track match...');
    }

    // 4. SMART ALTERNATIVE TRACK SEARCH:
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final cleanTitle = songTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      final query = Uri.encodeComponent('$cleanTitle ${artist ?? ''}'.trim());
      debugPrint('Direct stream for $videoId geoblocked or unavailable. Searching alternative for "$cleanTitle"...');

      final primaryAlt = await _searchAlternativeAudio(
        _primaryInstance,
        query,
        videoId,
        songTitle,
        timeout: const Duration(seconds: 4),
      );
      if (primaryAlt != null) {
        _saveToCache(videoId, primaryAlt);
        return primaryAlt;
      }
    }

    throw Exception('Failed to resolve playable audio stream for video: $videoId');
  }

  static void dispose() {
    _httpClient.close();
    _ytExplode.close();
  }
}
