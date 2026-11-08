import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class StreamResolverService {
  static final http.Client _httpClient = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

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

  /// Probes an audio stream URL using streaming HTTP headers to ensure
  /// it is not geo-restricted and can be read without downloading the entire body.
  static Future<bool> _probeStream(String url) async {
    try {
      final uri = Uri.parse(url);
      // Immediately reject any direct URL with geo-content restrictions (e.g. gcr=ir, gcr=us)
      // which YouTube CDN blocks with HTTP 403 when called from outside that region.
      if (uri.queryParameters.containsKey('gcr')) {
        return false;
      }

      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-1'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedResponse = await _httpClient.send(request).timeout(
        const Duration(milliseconds: 2000),
      );

      final isSuccess = streamedResponse.statusCode == 200 || streamedResponse.statusCode == 206;
      // Cancel the stream to immediately free the TCP socket connection
      await streamedResponse.stream.listen((_) {}).cancel();
      return isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Extracts verified audio streams from an Invidious instance for a given videoId
  static Future<String?> _extractAudioFromInstance(
    String instance,
    String videoId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final url = Uri.parse('$instance/api/v1/videos/$videoId');
      final response = await _httpClient.get(url).timeout(timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final adaptive = data['adaptiveFormats'] as List<dynamic>?;

      if (adaptive == null || adaptive.isEmpty) return null;

      // Filter and prioritize audio streams: MP4/AAC first, sorted by bitrate descending
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

      // Probe top candidates (highest bitrate MP4 and Opus) to guarantee playback
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

  /// Resolves direct audio stream URL with Chocolatemoo as the primary solver,
  /// followed by high-reliability fallbacks, geoblock detection, and auto-alternative matching.
  static Future<String> resolveAudioStreamUrl(
    String videoId, {
    String? songTitle,
    String? artist,
  }) async {
    // 1. PRIMARY SOLVER: Always attempt chocolatemoo first
    final primaryUrl = await _extractAudioFromInstance(
      _primaryInstance,
      videoId,
      timeout: const Duration(seconds: 5),
    );
    if (primaryUrl != null) {
      debugPrint('Resolved verified stream for $videoId via primary ($_primaryInstance)');
      return primaryUrl;
    }

    // 2. SMART ALTERNATIVE TRACK SEARCH ON PRIMARY SOLVER:
    // If the primary solver's direct stream is geoblocked or unavailable,
    // search for a clean release of the same track via primary solver immediately.
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final cleanTitle = songTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      final query = Uri.encodeComponent('$cleanTitle ${artist ?? ''}'.trim());
      debugPrint('Direct stream for $videoId geoblocked or unavailable. Searching alternative for "$cleanTitle"...');

      final primaryAlt = await _searchAlternativeAudio(_primaryInstance, query, videoId, songTitle);
      if (primaryAlt != null) {
        return primaryAlt;
      }
    }

    // 3. FALLBACK SOLVERS: Try fallback instances for direct stream
    for (final fallback in _fallbackInstances) {
      final fallbackUrl = await _extractAudioFromInstance(
        fallback,
        videoId,
        timeout: const Duration(milliseconds: 2500),
      );
      if (fallbackUrl != null) {
        debugPrint('Resolved verified stream for $videoId via fallback ($fallback)');
        return fallbackUrl;
      }
    }

    // 4. FALLBACK SEARCH: If alternative was not found on primary, try fallbacks
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
          return fallbackAlt;
        }
      }
    }

    // 5. SECONDARY FALLBACK: YoutubeExplode direct client
    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(yt.VideoId(videoId));
      final mp4Streams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();

      final candidates = mp4Streams.isNotEmpty ? mp4Streams : manifest.audioOnly.toList();
      for (final s in candidates.sortByBitrate().reversed) {
        final streamUrl = s.url.toString();
        if (await _probeStream(streamUrl)) {
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
