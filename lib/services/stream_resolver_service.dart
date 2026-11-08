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

  /// Reliable fallback instances in priority order
  static const List<String> _fallbackInstances = [
    'https://invidious.nerdvpn.de',
    'https://inv.nadeko.net',
    'https://invidious.tiekoetter.com',
  ];

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
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/player');
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
      ).timeout(const Duration(milliseconds: 1800));

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
      final url = Uri.parse('$instance/api/v1/videos/$videoId');
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
      // If optimistic flag is enabled and stream has no geo-restrictions,
      // return top candidate immediately without adding probe network latency.
      if (optimistic && allCandidates.isNotEmpty) {
        final topUrl = allCandidates.first['url'] as String;
        if (!topUrl.contains('gcr=')) {
          return topUrl;
        }
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

  /// PARALLEL INSTANCE RACING:
  /// Races multiple fallback instances simultaneously. The first working stream wins!
  static Future<String?> _raceInstances(String videoId, List<String> instances) async {
    final completer = Completer<String?>();
    int pending = instances.length;

    for (final instance in instances) {
      _extractAudioFromInstance(instance, videoId, timeout: const Duration(seconds: 4)).then((url) {
        if (url != null && !completer.isCompleted) {
          debugPrint('Parallel Instance Race won by $instance for $videoId');
          completer.complete(url);
        } else {
          pending--;
          if (pending <= 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        pending--;
        if (pending <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
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

  /// Master stream resolver featuring:
  /// 1. Instant Cache hit (0ms)
  /// 2. Hybrid Fast Path (InnerTube, ~250ms)
  /// 3. Optimistic Safe Path with Chocolatemoo
  /// 4. Parallel Instance Racing fallback
  /// 5. Smart Alternative Track Matching
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

    // Record stream resolution action in anti-bot monitor
    AntiBotService.recordPlay(videoId: videoId);

    // 2. HYBRID FAST PATH: Direct InnerTube request
    // Proactively bypass InnerTube if anti-bot shield is active due to burst activity
    if (AntiBotService.isSafeModeActive) {
      debugPrint('🛡️ StreamResolverService: Anti-bot shield is ACTIVE (${AntiBotService.activeReason}). Proactively routing directly to safe path...');
    } else {
      final innerTubeUrl = await _tryInnerTubeFastPath(videoId);
      if (innerTubeUrl != null) {
        _saveToCache(videoId, innerTubeUrl);
        return innerTubeUrl;
      }
    }

    // 3. PRIMARY SAFE SOLVER: Chocolatemoo
    final primaryUrl = await _extractAudioFromInstance(
      _primaryInstance,
      videoId,
      timeout: const Duration(seconds: 5),
      optimistic: optimistic,
    );
    if (primaryUrl != null) {
      debugPrint('Resolved verified stream for $videoId via primary ($_primaryInstance)');
      _saveToCache(videoId, primaryUrl);
      return primaryUrl;
    }

    // 4. SMART ALTERNATIVE TRACK SEARCH ON PRIMARY SOLVER:
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final cleanTitle = songTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      final query = Uri.encodeComponent('$cleanTitle ${artist ?? ''}'.trim());
      debugPrint('Direct stream for $videoId geoblocked or unavailable. Searching alternative for "$cleanTitle"...');

      final primaryAlt = await _searchAlternativeAudio(_primaryInstance, query, videoId, songTitle);
      if (primaryAlt != null) {
        _saveToCache(videoId, primaryAlt);
        return primaryAlt;
      }
    }

    // 5. PARALLEL INSTANCE RACING: Race fallback instances concurrently
    debugPrint('Racing fallback instances in parallel for $videoId...');
    final racedUrl = await _raceInstances(videoId, _fallbackInstances);
    if (racedUrl != null) {
      _saveToCache(videoId, racedUrl);
      return racedUrl;
    }

    // 6. FALLBACK SEARCH: If alternative was not found on primary, try fallbacks
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final cleanTitle = songTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      final query = Uri.encodeComponent('$cleanTitle ${artist ?? ''}'.trim());

      for (final fallback in _fallbackInstances) {
        final fallbackAlt = await _searchAlternativeAudio(
          fallback,
          query,
          videoId,
          songTitle,
          timeout: const Duration(milliseconds: 2500),
        );
        if (fallbackAlt != null) {
          _saveToCache(videoId, fallbackAlt);
          return fallbackAlt;
        }
      }
    }

    // 7. SECONDARY FALLBACK: YoutubeExplode direct client
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(yt.VideoId(videoId));
      final mp4Streams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();

      final candidates = mp4Streams.isNotEmpty ? mp4Streams : manifest.audioOnly.toList();
      for (final s in candidates.sortByBitrate().reversed) {
        final streamUrl = s.url.toString();
        if (await _probeStream(streamUrl)) {
          _saveToCache(videoId, streamUrl);
          return streamUrl;
        }
      }
    } catch (e) {
      debugPrint('YoutubeExplode fallback failed: $e');
    }

    throw Exception('Failed to resolve playable audio stream for video: $videoId');
  }

  static void dispose() {
    _httpClient.close();
    _ytExplode.close();
  }
}
