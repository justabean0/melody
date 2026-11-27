import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'anti_bot_service.dart';
import 'audio_cache_service.dart';
import 'database_service.dart';
import 'innertube_version_manager.dart';
import 'log_service.dart';
import 'native_extractor_service.dart';

class CachedStream {
  final String url;
  final DateTime expiresAt;

  CachedStream(this.url, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class DownloadStreamSelection {
  final String url;
  final String mimeType;
  final String extension;
  final int bitrateBps;
  final int? itag;

  const DownloadStreamSelection({
    required this.url,
    required this.mimeType,
    required this.extension,
    this.bitrateBps = 0,
    this.itag,
  });
}

class StreamResolverService {
  static final http.Client _httpClient = http.Client();
  static final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

  @visibleForTesting
  static http.Client? clientOverride;

  /// In-memory LRU Stream URL Cache with TTL (typically 4-6 hours)
  static final Map<String, CachedStream> _streamCache = {};

  /// In-flight stream resolutions to prevent simultaneous duplicate fetches
  static final Map<String, Future<String>> _inFlightResolutions = {};

  /// Seed Invidious instances used as reliable defaults & offline fallbacks
  static const List<String> _seedInstances = [
    'https://yt.chocolatemoo53.com',
  ];

  /// Active list of validated Invidious instances
  static List<String> _activeInstances = List.from(_seedInstances);

  /// Per-instance cooldown tracking (demoted for 5m upon 403/429/5xx/timeout)
  static final Map<String, DateTime> _instanceCooldowns = {};

  static const String _instanceCacheKey = 'melody_invidious_instances_cache';
  static const String _instanceCacheTimeKey = 'melody_invidious_instances_cache_time';

  /// Concurrency guards for user vs speculative resolution
  static int _activeUserResolutions = 0;
  static int _activeSpeculativeCount = 0;

  @visibleForTesting
  static int get activeUserResolutions => _activeUserResolutions;

  @visibleForTesting
  static void setActiveUserResolutionsForTesting(int count) {
    _activeUserResolutions = count;
  }

  @visibleForTesting
  static int get activeSpeculativeCount => _activeSpeculativeCount;

  /// Excluded regions for Invidious instances (censored or geoblocked)
  static const Set<String> _blockedRegions = {'IR', 'RU', 'CN', 'KP', 'SY', 'BY'};

  static int _parseBitrate(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  static int _parseItag(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    return int.tryParse(val.toString()) ?? 0;
  }

  /// Orders candidate audio streams for the requested [quality] tier (`High`, `Medium`, `Low`).
  @visibleForTesting
  static List<T> orderStreamsByQuality<T>(
    List<T> candidates,
    int Function(T) bitrateBps,
    String quality, {
    int Function(T)? itagOf,
  }) {
    if (candidates.length <= 1) return List<T>.from(candidates);
    final tier = DatabaseService.normalizeAudioQuality(quality);
    final ordered = List<T>.from(candidates);

    int itagRank(T item) {
      final tag = itagOf?.call(item) ?? 0;
      if (tier == 'High') {
        if (tag == 251) return 2;
        if (tag == 140) return 1;
      } else {
        if (tag == 140) return 2;
        if (tag == 251) return 1;
      }
      return 0;
    }

    ordered.sort((a, b) {
      final ba = bitrateBps(a);
      final bb = bitrateBps(b);
      final aHasBitrate = ba > 0;
      final bHasBitrate = bb > 0;
      if (aHasBitrate != bHasBitrate) {
        return aHasBitrate ? -1 : 1;
      }

      if (aHasBitrate && bHasBitrate) {
        switch (tier) {
          case 'Low':
            final cmp = ba.compareTo(bb);
            if (cmp != 0) return cmp;
            break;
          case 'Medium':
            const targetBps = 128000;
            final aInBand = ba >= 96000 && ba <= 144000;
            final bInBand = bb >= 96000 && bb <= 144000;
            if (aInBand != bInBand) {
              return aInBand ? -1 : 1;
            }
            final aDist = (ba - targetBps).abs();
            final bDist = (bb - targetBps).abs();
            final distCmp = aDist.compareTo(bDist);
            if (distCmp != 0) return distCmp;
            final highTie = bb.compareTo(ba);
            if (highTie != 0) return highTie;
            break;
          case 'High':
          default:
            final cmp = bb.compareTo(ba);
            if (cmp != 0) return cmp;
            break;
        }
      }

      return itagRank(b).compareTo(itagRank(a));
    });
    return ordered;
  }

  static bool _isM4aMimeOrItag(String? mimeType, {String? formatName, int? itag}) {
    final mime = (mimeType ?? '').toLowerCase();
    final fmt = (formatName ?? '').toLowerCase();
    return mime.contains('mp4') ||
        mime.contains('m4a') ||
        fmt.contains('m4a') ||
        itag == 139 ||
        itag == 140 ||
        itag == 141;
  }

  /// Normalizes a raw MIME/format hint into a clean MIME type and file extension.
  static ({String mimeType, String extension}) normalizeDownloadFormat(
    String? rawMime, {
    String? formatName,
    int? itag,
  }) {
    final cleanMime = (rawMime ?? '').split(';').first.trim().toLowerCase();
    if (_isM4aMimeOrItag(cleanMime, formatName: formatName, itag: itag)) {
      return (mimeType: 'audio/mp4', extension: 'm4a');
    }
    if (cleanMime.contains('webm')) {
      return (mimeType: 'audio/webm', extension: 'webm');
    }
    if (cleanMime.contains('mpeg') || cleanMime.contains('mp3')) {
      return (mimeType: 'audio/mpeg', extension: 'mp3');
    }
    if (cleanMime.contains('ogg') || cleanMime.contains('opus')) {
      return (mimeType: 'audio/ogg', extension: 'ogg');
    }
    if (cleanMime.startsWith('audio/')) {
      final sub = cleanMime.substring('audio/'.length).replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (sub.isNotEmpty) {
        return (mimeType: cleanMime, extension: sub == 'mp4' ? 'm4a' : sub);
      }
    }
    return (mimeType: 'audio/mp4', extension: 'm4a');
  }

  /// Orders candidates preferring highest-bitrate M4A (AAC / audio/mp4) for offline downloads.
  @visibleForTesting
  static List<T> orderStreamsPreferM4a<T>(
    List<T> candidates,
    int Function(T) bitrateBps,
    String? Function(T) mimeTypeOf, {
    int Function(T)? itagOf,
  }) {
    if (candidates.length <= 1) return List<T>.from(candidates);
    final ordered = List<T>.from(candidates);
    ordered.sort((a, b) {
      final aM4a = _isM4aMimeOrItag(
        mimeTypeOf(a),
        itag: itagOf?.call(a),
      );
      final bM4a = _isM4aMimeOrItag(
        mimeTypeOf(b),
        itag: itagOf?.call(b),
      );
      if (aM4a != bM4a) {
        return aM4a ? -1 : 1;
      }
      final ba = bitrateBps(a);
      final bb = bitrateBps(b);
      final cmp = bb.compareTo(ba);
      if (cmp != 0) return cmp;
      final ta = itagOf?.call(a) ?? 0;
      final tb = itagOf?.call(b) ?? 0;
      return tb.compareTo(ta);
    });
    return ordered;
  }

  static String _cacheKey(String videoId, String quality) =>
      '${DatabaseService.normalizeAudioQuality(quality)}_$videoId';

  /// Clears in-memory stream cache
  static void clearCache() {
    _streamCache.clear();
  }

  /// Resets instance pool for testing
  @visibleForTesting
  static void resetInstancesForTesting({List<String>? instances}) {
    _activeInstances = instances != null ? List.from(instances) : List.from(_seedInstances);
    _instanceCooldowns.clear();
    _activeUserResolutions = 0;
    _activeSpeculativeCount = 0;
  }

  /// Returns healthy instances rotated by availability.
  /// Demoted instances remain skipped during their 5-minute cooldown.
  /// If all instances are in cooldown, returns instances sorted by oldest failure timestamp.
  static List<String> getHealthyInstances() {
    final now = DateTime.now();
    final healthy = _activeInstances
        .where((inst) => !(_instanceCooldowns[inst]?.isAfter(now) ?? false))
        .toList();
    if (healthy.isNotEmpty) return healthy;

    // If all active instances are in cooldown, sort by oldest failure timestamp (earliest expiry)
    // rather than resetting to a dead host.
    final fallbackList = List<String>.from(_activeInstances);
    fallbackList.sort((a, b) {
      final aExpiry = _instanceCooldowns[a] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bExpiry = _instanceCooldowns[b] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aExpiry.compareTo(bExpiry);
    });
    return fallbackList;
  }

  /// Demotes an instance for 5 minutes.
  /// Does not log duplicate lines if already within cooldown.
  static void markInstanceFailed(String instance) {
    final now = DateTime.now();
    final currentExpiry = _instanceCooldowns[instance];
    if (currentExpiry != null && currentExpiry.isAfter(now)) {
      return;
    }
    _instanceCooldowns[instance] = now.add(const Duration(minutes: 5));
    debugPrint('StreamResolverService: Demoted instance $instance for 5m due to failure');
  }

  /// Strict URL validation preventing SSRF, private IPs, credentials, or path injection.
  static String? sanitizeAndValidateInstanceUrl(String rawUrl) {
    try {
      final uri = Uri.tryParse(rawUrl.trim());
      if (uri == null) return null;

      // 1. Strict HTTPS scheme only
      if (uri.scheme.toLowerCase() != 'https') return null;

      // 2. Reject credentials / userinfo
      if (uri.userInfo.isNotEmpty) return null;

      // 3. Reject path injection (must be empty or just '/')
      if (uri.path.isNotEmpty && uri.path != '/') return null;

      // 4. Reject query or fragment
      if (uri.hasQuery || uri.fragment.isNotEmpty) return null;

      // 5. Port must be 443 or default
      if (uri.hasPort && uri.port != 443) return null;

      final host = uri.host.trim().toLowerCase();
      if (host.isEmpty) return null;

      // 6. Check IP addresses (block private, loopback, multicast, etc.)
      final ip = InternetAddress.tryParse(host);
      if (ip != null) {
        if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return null;
        final raw = ip.rawAddress;
        if (ip.type == InternetAddressType.IPv4) {
          if (raw[0] == 0) return null; // 0.0.0.0/8
          if (raw[0] == 10) return null; // 10.0.0.0/8
          if (raw[0] == 127) return null; // 127.0.0.0/8
          if (raw[0] == 169 && raw[1] == 254) return null; // 169.254.0.0/16
          if (raw[0] == 172 && (raw[1] >= 16 && raw[1] <= 31)) return null; // 172.16.0.0/12
          if (raw[0] == 192 && raw[1] == 168) return null; // 192.168.0.0/16
          if (raw[0] == 100 && (raw[1] >= 64 && raw[1] <= 127)) return null; // 100.64.0.0/10
          if (raw[0] >= 224) return null; // multicast / reserved
        } else if (ip.type == InternetAddressType.IPv6) {
          if (raw[0] == 0xfc || raw[0] == 0xfd) return null; // fc00::/7 ULA
          // Check IPv4-mapped IPv6 (::ffff:a.b.c.d)
          bool isIpv4Mapped = true;
          for (int i = 0; i < 10; i++) {
            if (raw[i] != 0) isIpv4Mapped = false;
          }
          if (raw[10] != 0xff || raw[11] != 0xff) isIpv4Mapped = false;
          if (isIpv4Mapped) {
            final b0 = raw[12], b1 = raw[13];
            if (b0 == 0 || b0 == 10 || b0 == 127) return null;
            if (b0 == 169 && b1 == 254) return null;
            if (b0 == 172 && (b1 >= 16 && b1 <= 31)) return null;
            if (b0 == 192 && b1 == 168) return null;
            if (b0 >= 224) return null;
          }
        }
      } else {
        // 7. Domain name validation
        if (host == 'localhost') return null;
        if (host.endsWith('.local') ||
            host.endsWith('.localhost') ||
            host.endsWith('.lan') ||
            host.endsWith('.internal') ||
            host.endsWith('.home') ||
            host.endsWith('.corp') ||
            host.endsWith('.test') ||
            host.endsWith('.invalid')) {
          return null;
        }

        // Must match valid domain structure: at least one dot, alphanumeric + hyphens
        final domainRegex =
            RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$');
        if (!domainRegex.hasMatch(host)) return null;

        // TLD must be all letters and >= 2 chars
        final tld = host.split('.').last;
        if (!RegExp(r'^[a-z]{2,}$').hasMatch(tld)) return null;
      }

      return 'https://$host';
    } catch (_) {
      return null;
    }
  }

  /// Parses and filters instances from https://api.invidious.io/instances.json
  static List<String> parseAndValidateInstancesJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final List<String> validHosts = [];

      void processEntry(dynamic domain, dynamic infoObj) {
        if (infoObj is! Map<String, dynamic>) return;
        final type = infoObj['type']?.toString().toLowerCase();
        if (type != 'https') return;

        final api = infoObj['api'];
        if (api != true && api != 1 && api != 'true') return;

        final region = infoObj['region']?.toString().toUpperCase();
        if (region != null && _blockedRegions.contains(region)) return;
        final country = infoObj['country']?.toString().toUpperCase();
        if (country != null && _blockedRegions.contains(country)) return;

        final uriStr = infoObj['uri']?.toString() ?? (domain != null ? 'https://$domain' : null);
        if (uriStr == null) return;

        final validated = sanitizeAndValidateInstanceUrl(uriStr);
        if (validated != null && !validHosts.contains(validated)) {
          validHosts.add(validated);
        }
      }

      if (decoded is List) {
        for (final item in decoded) {
          if (item is List && item.length >= 2) {
            processEntry(item[0], item[1]);
          } else if (item is Map<String, dynamic>) {
            processEntry(item['name'] ?? item['domain'], item);
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        decoded.forEach((key, val) {
          processEntry(key, val);
        });
      }

      return validHosts;
    } catch (_) {
      return [];
    }
  }

  /// Initializes the dynamic instance pool lazily or from cache
  static Future<void> initInstances({http.Client? client}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_instanceCacheKey);
      final cachedTime = prefs.getInt(_instanceCacheTimeKey);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (cachedJson != null && cachedTime != null) {
        final ageMs = nowMs - cachedTime;
        if (ageMs < 86400000) {
          final instances = parseAndValidateInstancesJson(cachedJson);
          if (instances.isNotEmpty) {
            _updateActiveInstances(instances);
            return;
          }
        }
      }

      unawaited(_fetchInstancesJson(client: client));
    } catch (e) {
      debugPrint('StreamResolverService initInstances error: $e');
    }
  }

  static Future<void> _fetchInstancesJson({http.Client? client}) async {
    try {
      final httpClient = client ?? clientOverride ?? _httpClient;
      final uri = Uri.parse('https://api.invidious.io/instances.json');
      final res = await httpClient.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final instances = parseAndValidateInstancesJson(res.body);
        if (instances.isNotEmpty) {
          _updateActiveInstances(instances);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_instanceCacheKey, res.body);
            await prefs.setInt(_instanceCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
          } catch (_) {}
        }
      }
    } catch (e) {
      LogService.warning('Could not fetch instances.json ($e), using seeds.', tag: 'StreamResolver');
    }
  }

  static void _updateActiveInstances(List<String> discovered) {
    final list = <String>[..._seedInstances];
    for (final inst in discovered) {
      if (!list.contains(inst)) list.add(inst);
    }
    _activeInstances = list;
    debugPrint('StreamResolverService: Active Invidious instance pool updated (${_activeInstances.length} instances)');
  }

  /// Invalidates cached streams across all quality tiers for [videoId].
  static void invalidateCache(String videoId) {
    _streamCache.removeWhere((key, _) => key == videoId || key.endsWith('_$videoId'));
    AudioCacheService.evict(videoId);
    debugPrint('StreamResolverService: Invalidated cache for $videoId');
  }

  /// Helper to record stream URL in cache with expiration
  static void _saveToCache(String videoId, String quality, String url) {
    DateTime expiresAt = DateTime.now().add(const Duration(minutes: 20));
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

    final key = _cacheKey(videoId, quality);
    _streamCache[key] = CachedStream(url, expiresAt);
    debugPrint('StreamResolverService: Cached stream for $key (expires at $expiresAt)');
  }

  /// Probes an audio stream URL using streaming HTTP headers to ensure
  /// it is not geo-restricted and can be read without downloading the entire body.
  static Future<bool> _probeStream(String url, {http.Client? client}) async {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('gcr')) {
        return false;
      }

      final httpClient = client ?? clientOverride ?? _httpClient;
      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-1'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedResponse = await httpClient.send(request).timeout(
        const Duration(milliseconds: 1800),
      );

      final isSuccess = streamedResponse.statusCode == 200 || streamedResponse.statusCode == 206;
      await streamedResponse.stream.listen((_) {}).cancel();
      return isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Quick 2s probe for non-googlevideo or non-expire URLs verifying HTTP 200/206
  /// and content-type starting with 'audio/'. Rejects HTML/403/500 immediately.
  static Future<bool> _probeAudioUrl(
    String url, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final uri = Uri.parse(url);
      final httpClient = client ?? clientOverride ?? _httpClient;
      final request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-0'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedResponse = await httpClient.send(request).timeout(timeout);
      final statusCode = streamedResponse.statusCode;
      final contentType = streamedResponse.headers['content-type']?.toLowerCase() ?? '';
      await streamedResponse.stream.listen((_) {}).cancel();

      final isSuccess = (statusCode == 200 || statusCode == 206) && contentType.startsWith('audio/');
      if (!isSuccess) {
        LogService.warning(
          'Audio probe rejected (status: $statusCode, type: $contentType) for $url',
          tag: 'StreamResolver',
        );
      }
      return isSuccess;
    } catch (e) {
      LogService.warning('Audio probe error for $url: $e', tag: 'StreamResolver');
      return false;
    }
  }

  /// 1. HYBRID FAST PATH: Direct InnerTube player API (200-400ms)
  static Future<String?> _tryInnerTubeFastPath(
    String videoId, {
    String quality = 'High',
    http.Client? client,
  }) async {
    final res = await _tryInnerTubeFastPathWithMeta(
      videoId,
      quality: quality,
      client: client,
    );
    return res?.url;
  }

  static Future<DownloadStreamSelection?> _tryInnerTubeFastPathWithMeta(
    String videoId, {
    String quality = 'High',
    bool preferM4a = false,
    http.Client? client,
  }) async {
    try {
      final httpClient = client ?? clientOverride ?? _httpClient;
      final profile = InnerTubeVersionManager.currentProfile;
      final url = Uri.parse('https://www.youtube.com/youtubei/v1/player');
      final body = jsonEncode({
        'context': {
          'client': profile.toContextClient(),
        },
        'videoId': videoId,
      });

      final res = await httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': profile.userAgent,
        },
        body: body,
      ).timeout(const Duration(milliseconds: 2500));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {}

      final isOutdated = InnerTubeVersionManager.inspectResponseForOutdatedClient(
        statusCode: res.statusCode,
        responseBody: data,
        rawBody: res.body,
      );

      if (isOutdated) {
        debugPrint('InnerTube Fast Path: Outdated/rejected client version detected. Tripping anti-bot shield...');
        LogService.warning('InnerTube Fast Path: Outdated client version rejected for $videoId', tag: 'StreamResolver');
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
              final ordered = preferM4a
                  ? orderStreamsPreferM4a<dynamic>(
                      audioFormats,
                      (f) => _parseBitrate(f['bitrate']),
                      (f) => f['mimeType'] as String?,
                      itagOf: (f) => _parseItag(f['itag']),
                    )
                  : orderStreamsByQuality<dynamic>(
                      audioFormats,
                      (f) => _parseBitrate(f['bitrate']),
                      quality,
                      itagOf: (f) => _parseItag(f['itag']),
                    );
              final picked = ordered.first;
              final directUrl = picked['url'] as String;
              final pickedItag = _parseItag(picked['itag']);
              final fmt = normalizeDownloadFormat(
                picked['mimeType'] as String?,
                itag: pickedItag,
              );
              debugPrint(
                'InnerTube Fast Path: SUCCESS for $videoId ($quality) in sub-second using ${profile.key}!',
              );
              return DownloadStreamSelection(
                url: directUrl,
                mimeType: fmt.mimeType,
                extension: fmt.extension,
                bitrateBps: _parseBitrate(picked['bitrate']),
                itag: pickedItag > 0 ? pickedItag : null,
              );
            }
          }
        } else {
          debugPrint('InnerTube Fast Path: Bot-check / login required ($playability). Tripping anti-bot shield & safe fallback...');
          LogService.warning('InnerTube Fast Path: Bot-check / playability ($playability) for $videoId', tag: 'StreamResolver');
          AntiBotService.tripOnBotDetected(playability ?? 'STATUS_NOT_OK');
        }
      } else if (res.statusCode == 429) {
        debugPrint('InnerTube Fast Path: HTTP 429 rate limit. Tripping anti-bot shield...');
        LogService.warning('InnerTube Fast Path: HTTP 429 rate limit for $videoId', tag: 'StreamResolver');
        AntiBotService.tripOnBotDetected('HTTP 429');
      } else {
        LogService.warning('InnerTube Fast Path: HTTP ${res.statusCode} for $videoId', tag: 'StreamResolver');
      }
    } catch (e) {
      debugPrint('InnerTube Fast Path: Skipped ($e). Falling back to safe path...');
      LogService.warning('InnerTube Fast Path error for $videoId: $e', tag: 'StreamResolver');
    }
    return null;
  }

  /// Extracts audio streams from an Invidious instance for a given videoId
  static Future<String?> _extractAudioFromInstance(
    String instance,
    String videoId, {
    String quality = 'High',
    Duration timeout = const Duration(seconds: 4),
    bool optimistic = false,
    http.Client? client,
  }) async {
    final res = await _extractAudioWithMetaFromInstance(
      instance,
      videoId,
      quality: quality,
      timeout: timeout,
      optimistic: optimistic,
      client: client,
    );
    return res?.url;
  }

  static Future<DownloadStreamSelection?> _extractAudioWithMetaFromInstance(
    String instance,
    String videoId, {
    String quality = 'High',
    Duration timeout = const Duration(seconds: 4),
    bool optimistic = false,
    bool preferM4a = false,
    http.Client? client,
  }) async {
    try {
      final httpClient = client ?? clientOverride ?? _httpClient;
      // Do not append ?local=true so Invidious returns direct googlevideo streams with expire=
      final url = Uri.parse('$instance/api/v1/videos/$videoId');
      final response = await httpClient.get(url).timeout(timeout);

      if (response.statusCode != 200) {
        LogService.warning(
          'Companion proxy HTTP ${response.statusCode} on $instance for $videoId',
          tag: 'StreamResolver',
        );
        markInstanceFailed(instance);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final adaptive = data['adaptiveFormats'] as List<dynamic>?;

      if (adaptive == null || adaptive.isEmpty) {
        LogService.warning(
          'Companion proxy empty adaptive formats on $instance for $videoId',
          tag: 'StreamResolver',
        );
        markInstanceFailed(instance);
        return null;
      }

      final directGoogleVideo = <Map<String, dynamic>>[];
      final proxyOrNonGoogle = <Map<String, dynamic>>[];

      for (final f in adaptive) {
        final type = (f['type'] as String?)?.toLowerCase() ?? '';
        final streamUrl = f['url'] as String?;
        final bitrate = _parseBitrate(f['bitrate']);
        final itag = f['itag'] != null ? int.tryParse(f['itag'].toString()) ?? 0 : 0;

        if (type.startsWith('audio/') && streamUrl != null && streamUrl.isNotEmpty) {
          final resolvedUrl = streamUrl.startsWith('http')
              ? streamUrl
              : Uri.parse(instance).resolve(streamUrl).toString();

          bool isDirectGoogleVideo = false;
          try {
            final u = Uri.parse(resolvedUrl);
            if (u.host.contains('googlevideo.com') && u.queryParameters.containsKey('expire')) {
              isDirectGoogleVideo = true;
            }
          } catch (_) {}

          final candidate = {
            'url': resolvedUrl,
            'bitrate': bitrate,
            'itag': itag,
            'isDirectGoogleVideo': isDirectGoogleVideo,
            'type': type,
          };

          if (isDirectGoogleVideo) {
            directGoogleVideo.add(candidate);
          } else {
            proxyOrNonGoogle.add(candidate);
          }
        }
      }

      final sortedDirect = preferM4a
          ? orderStreamsPreferM4a<Map<String, dynamic>>(
              directGoogleVideo,
              (c) => c['bitrate'] as int,
              (c) => c['type'] as String?,
              itagOf: (c) => c['itag'] as int,
            )
          : orderStreamsByQuality<Map<String, dynamic>>(
              directGoogleVideo,
              (c) => c['bitrate'] as int,
              quality,
              itagOf: (c) => c['itag'] as int,
            );
      final sortedProxy = preferM4a
          ? orderStreamsPreferM4a<Map<String, dynamic>>(
              proxyOrNonGoogle,
              (c) => c['bitrate'] as int,
              (c) => c['type'] as String?,
              itagOf: (c) => c['itag'] as int,
            )
          : orderStreamsByQuality<Map<String, dynamic>>(
              proxyOrNonGoogle,
              (c) => c['bitrate'] as int,
              quality,
              itagOf: (c) => c['itag'] as int,
            );

      final allCandidates = [
        ...sortedDirect,
        ...sortedProxy,
      ];

      for (final candidate in allCandidates) {
        final streamUrl = candidate['url'] as String;
        // Probe EVERY CompanionProxy candidate URL (including googlevideo.com links that may be IP-bound/SABR 503/403)
        // with the 2s Range: bytes=0-0 check before returning it.
        final isValid = await _probeAudioUrl(streamUrl, client: httpClient);
        if (isValid) {
          final itag = candidate['itag'] as int;
          final fmt = normalizeDownloadFormat(
            candidate['type'] as String?,
            itag: itag,
          );
          return DownloadStreamSelection(
            url: streamUrl,
            mimeType: fmt.mimeType,
            extension: fmt.extension,
            bitrateBps: candidate['bitrate'] as int,
            itag: itag > 0 ? itag : null,
          );
        }
      }

      final formatStreams = data['formatStreams'] as List<dynamic>?;
      if (formatStreams != null && formatStreams.isNotEmpty) {
        for (final fs in formatStreams) {
          final streamUrl = fs['url'] as String?;
          if (streamUrl != null && streamUrl.isNotEmpty) {
            final resolvedUrl = streamUrl.startsWith('http')
                ? streamUrl
                : Uri.parse(instance).resolve(streamUrl).toString();
            final isValid = await _probeAudioUrl(resolvedUrl, client: httpClient);
            if (isValid) {
              final fmt = normalizeDownloadFormat(fs['type'] as String?);
              return DownloadStreamSelection(
                url: resolvedUrl,
                mimeType: fmt.mimeType,
                extension: fmt.extension,
              );
            }
          }
        }
      }

      markInstanceFailed(instance);
    } catch (e) {
      LogService.warning('Companion proxy error on $instance for $videoId: $e', tag: 'StreamResolver');
      markInstanceFailed(instance);
    }
    return null;
  }

  /// Resolves direct stream via YoutubeExplode
  static Future<String?> _resolveViaYoutubeExplode(
    String videoId, {
    String quality = 'High',
    bool optimistic = true,
    http.Client? client,
  }) async {
    final res = await _resolveWithMetaViaYoutubeExplode(
      videoId,
      quality: quality,
      optimistic: optimistic,
      client: client,
    );
    return res?.url;
  }

  static Future<DownloadStreamSelection?> _resolveWithMetaViaYoutubeExplode(
    String videoId, {
    String quality = 'High',
    bool optimistic = true,
    bool preferM4a = false,
    http.Client? client,
  }) async {
    // Only skip in hermetic mock tests where clientOverride is explicitly provided
    if (clientOverride != null) return null;
    try {
      final manifest = await _ytExplode.videos.streamsClient
          .getManifest(yt.VideoId(videoId))
          .timeout(const Duration(milliseconds: 5500));

      final allAudio = manifest.audioOnly.toList();
      final tier = DatabaseService.normalizeAudioQuality(quality);
      final List<yt.AudioOnlyStreamInfo> eligible;
      if (tier == 'Low' || preferM4a) {
        eligible = allAudio;
      } else {
        final solidAudio = allAudio.where((s) => s.bitrate.bitsPerSecond >= 96000).toList();
        eligible = solidAudio.isNotEmpty ? solidAudio : allAudio;
      }

      final orderedCandidates = preferM4a
          ? orderStreamsPreferM4a<yt.AudioOnlyStreamInfo>(
              eligible,
              (s) => s.bitrate.bitsPerSecond,
              (s) => s.codec.mimeType,
              itagOf: (s) => s.tag,
            )
          : orderStreamsByQuality<yt.AudioOnlyStreamInfo>(
              eligible,
              (s) => s.bitrate.bitsPerSecond,
              tier,
              itagOf: (s) => s.tag,
            );

      for (final s in orderedCandidates) {
        final streamUrl = s.url.toString();
        if (optimistic || await _probeStream(streamUrl, client: client)) {
          final sizeKb = (s.size.totalBytes / 1024).round();
          LogService.recordBreadcrumb(
            'Resolved direct audio stream for $videoId via YoutubeExplode (itag: ${s.tag}, bitrate: ${s.bitrate.bitsPerSecond}, size: ${sizeKb}KB)',
            category: 'stream',
          );
          final fmt = normalizeDownloadFormat(
            s.codec.mimeType,
            formatName: s.container.name,
            itag: s.tag,
          );
          return DownloadStreamSelection(
            url: streamUrl,
            mimeType: fmt.mimeType,
            extension: fmt.extension,
            bitrateBps: s.bitrate.bitsPerSecond,
            itag: s.tag,
          );
        }
      }
    } catch (e) {
      LogService.warning('YoutubeExplode resolution error ($e) for $videoId', tag: 'StreamResolver');
    }
    return null;
  }

  /// Searches an instance for an alternative working stream of the same track.
  /// Enforces a hard 10s total timeout budget, probes max 3 candidates, and respects cooldowns.
  static Future<String?> _searchAlternativeAudio(
    String query,
    String originalVideoId,
    String songTitle, {
    String quality = 'High',
    Duration timeout = const Duration(seconds: 10),
    http.Client? client,
  }) async {
    final stopwatch = Stopwatch()..start();
    final instances = getHealthyInstances();
    int probedCandidates = 0;

    for (final instance in instances.take(2)) {
      if (stopwatch.elapsedMilliseconds >= 10000 || probedCandidates >= 3) break;
      try {
        final httpClient = client ?? clientOverride ?? _httpClient;
        final searchUrl = Uri.parse('$instance/api/v1/search?q=$query&type=video');
        final remainingMs = 10000 - stopwatch.elapsedMilliseconds;
        if (remainingMs <= 1000) break;

        final searchTimeout = Duration(milliseconds: remainingMs.clamp(1000, 3500));
        final sRes = await httpClient.get(searchUrl).timeout(searchTimeout);

        if (sRes.statusCode == 200) {
          final items = jsonDecode(sRes.body) as List<dynamic>;
          for (final item in items) {
            if (stopwatch.elapsedMilliseconds >= 10000 || probedCandidates >= 3) break;
            final altVideoId = item['videoId'] as String?;
            if (altVideoId == null || altVideoId == originalVideoId) continue;

            probedCandidates++;
            final candRemainingMs = 10000 - stopwatch.elapsedMilliseconds;
            if (candRemainingMs <= 1000) break;

            final extractTimeout = Duration(milliseconds: candRemainingMs.clamp(1000, 3000));
            final altAudioUrl = await _extractAudioFromInstance(
              instance,
              altVideoId,
              quality: quality,
              timeout: extractTimeout,
              optimistic: false,
              client: httpClient,
            );
            if (altAudioUrl != null) {
              LogService.recordBreadcrumb(
                'Resolved alternative stream for "$songTitle": $altVideoId via $instance (probed $probedCandidates)',
                category: 'stream',
              );
              return altAudioUrl;
            }
          }
        } else {
          markInstanceFailed(instance);
        }
      } catch (e) {
        markInstanceFailed(instance);
      }
    }
    return null;
  }

  /// Hedged parallel race:
  /// - If [skipCompanionProxy] is true: launch YoutubeExplode at t = 0.0s
  /// - Otherwise: start CompanionProxy against healthy instance at t = 0.0s (timeout: 4s)
  /// - t = 1.5s: If not resolved yet, launch YoutubeExplode in parallel
  /// - If CompanionProxy fails fast (< 1.5s), launch YoutubeExplode immediately
  /// - Total 7.5s hard race cap from t = 0s.
  /// - Completer never aborts while YoutubeExplode is still active.
  /// - Logs start/win/failure with itag/size.
  static Future<String?> _hedgedParallelRace(
    String videoId, {
    String quality = 'High',
    bool optimistic = true,
    bool skipCompanionProxy = false,
    http.Client? client,
  }) async {
    final completer = Completer<String?>();
    Timer? hedgeTimer;
    Timer? raceTimeoutTimer;
    int pendingRacers = 0;
    bool ytLaunched = false;

    void win(String? url, String source) {
      if (url != null && !completer.isCompleted) {
        String itagInfo = '';
        try {
          final uri = Uri.parse(url);
          final itag = uri.queryParameters['itag'];
          if (itag != null) itagInfo = ' (itag: $itag)';
        } catch (_) {}
        LogService.recordBreadcrumb('Hedged race WON by $source for $videoId$itagInfo', category: 'stream');
        debugPrint('⚡ Stream Race WON by $source for $videoId$itagInfo');
        completer.complete(url);
      }
    }

    void launchYoutubeExplode() {
      if (ytLaunched || completer.isCompleted) return;
      ytLaunched = true;
      pendingRacers++;
      LogService.recordBreadcrumb('Hedged race: YoutubeExplode started for $videoId', category: 'stream');
      _resolveViaYoutubeExplode(videoId, quality: quality, optimistic: optimistic, client: client).then((url) {
        if (url != null) {
          win(url, 'YoutubeExplode');
        } else {
          pendingRacers--;
          if (pendingRacers <= 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((err) {
        LogService.warning('Hedged race: YoutubeExplode error for $videoId: $err', tag: 'StreamResolver');
        pendingRacers--;
        if (pendingRacers <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    void racerDone() {
      pendingRacers--;
      if (!completer.isCompleted) {
        if (!ytLaunched) {
          hedgeTimer?.cancel();
          launchYoutubeExplode();
        } else if (pendingRacers <= 0) {
          LogService.warning('Hedged race ended with no streams for $videoId', tag: 'StreamResolver');
          completer.complete(null);
        }
      }
    }

    // 7.5-second hard cap from t = 0s
    raceTimeoutTimer = Timer(const Duration(milliseconds: 7500), () {
      if (!completer.isCompleted) {
        LogService.warning('Hedged race 7.5s hard cap reached for $videoId', tag: 'StreamResolver');
        debugPrint('StreamResolverService: 7.5s total race cap reached for $videoId');
        completer.complete(null);
      }
    });

    // Racer 1: Direct InnerTube fast path (if safe mode inactive)
    if (!AntiBotService.isSafeModeActive) {
      pendingRacers++;
      _tryInnerTubeFastPath(videoId, quality: quality, client: client).then((url) {
        if (url != null) {
          win(url, 'InnerTube');
        } else {
          racerDone();
        }
      }).catchError((_) {
        racerDone();
      });
    }

    if (skipCompanionProxy) {
      // Direct retry mode: bypass CompanionProxy completely, launch YoutubeExplode at t = 0.0s
      launchYoutubeExplode();
    } else {
      // Racer 2: CompanionProxy against healthy instance (started at t = 0s)
      pendingRacers++;
      bool proxyCompleted = false;

      Future<String?> executeProxy() async {
        final instances = getHealthyInstances();
        if (instances.isEmpty) return null;
        final inst = instances.first;
        LogService.recordBreadcrumb('Hedged race: CompanionProxy started on $inst for $videoId', category: 'stream');
        try {
          return await _extractAudioFromInstance(
            inst,
            videoId,
            quality: quality,
            timeout: const Duration(seconds: 4),
            optimistic: optimistic,
            client: client,
          );
        } catch (_) {
          return null;
        }
      }

      executeProxy().then((url) {
        proxyCompleted = true;
        if (url != null) {
          win(url, 'CompanionProxy');
        } else {
          racerDone();
        }
      }).catchError((_) {
        proxyCompleted = true;
        racerDone();
      });

      // Hedge timer: at t = 1.5s, if not completed, launch YoutubeExplode in parallel
      hedgeTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!proxyCompleted && !completer.isCompleted) {
          launchYoutubeExplode();
        }
      });
    }

    try {
      final result = await completer.future;
      return result;
    } finally {
      hedgeTimer?.cancel();
      raceTimeoutTimer.cancel();
    }
  }

  /// Fast racing solver for speculative pre-warming
  static Future<String?> _raceFastSolvers(
    String videoId, {
    String quality = 'High',
    bool optimistic = true,
    http.Client? client,
  }) async {
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

    if (!AntiBotService.isSafeModeActive) {
      _tryInnerTubeFastPath(videoId, quality: quality, client: client)
          .then((u) => handleWinner(u, 'InnerTube'))
          .catchError((_) => handleWinner(null, 'InnerTube'));
    } else {
      pending--;
    }

    final instances = getHealthyInstances();
    final instance = instances.first;
    _extractAudioFromInstance(
      instance,
      videoId,
      quality: quality,
      timeout: const Duration(seconds: 4),
      optimistic: optimistic,
      client: client,
    ).then((u) => handleWinner(u, 'CompanionProxy')).catchError((_) => handleWinner(null, 'CompanionProxy'));

    return completer.future;
  }

  /// Master stream resolver
  static Future<String> resolveAudioStreamUrl(
    String videoId, {
    String? songTitle,
    String? artist,
    String? quality,
    bool optimistic = true,
    bool isSpeculative = false,
    bool skipCompanionProxy = false,
    http.Client? client,
  }) async {
    final effectiveQuality =
        DatabaseService.normalizeAudioQuality(quality ?? DatabaseService.getAudioQuality());
    final cacheKey = _cacheKey(videoId, effectiveQuality);

    // 1. STREAM URL CACHE: Instant 0ms return if cached and unexpired
    final cached = _streamCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      final isProxy = cached.url.contains('127.0.0.1') ||
          _activeInstances.any((inst) => cached.url.startsWith(inst));
      if (!skipCompanionProxy || !isProxy) {
        LogService.recordBreadcrumb('Stream cache HIT for $cacheKey', category: 'stream');
        debugPrint('StreamResolverService: Cache HIT for $cacheKey (0ms startup)');
        return cached.url;
      }
    }

    // Speculative requests yield immediately if user playback is active
    if (isSpeculative && _activeUserResolutions > 0) {
      throw Exception('Speculative resolution skipped due to active user playback');
    }

    // Deduplicate simultaneous requests for same videoId + quality (unless skipCompanionProxy)
    if (!skipCompanionProxy) {
      final inFlight = _inFlightResolutions[cacheKey];
      if (inFlight != null) {
        LogService.recordBreadcrumb('Awaiting in-flight resolution for $cacheKey', category: 'stream');
        return await inFlight;
      }
    }

    if (!isSpeculative) {
      _activeUserResolutions++;
    }

    final future = _doResolveAudioStreamUrl(
      videoId,
      songTitle: songTitle,
      artist: artist,
      quality: effectiveQuality,
      optimistic: optimistic,
      isSpeculative: isSpeculative,
      skipCompanionProxy: skipCompanionProxy,
      client: client,
    );
    if (!skipCompanionProxy) {
      _inFlightResolutions[cacheKey] = future;
    }

    try {
      final res = await future;
      return res;
    } finally {
      if (!skipCompanionProxy) {
        _inFlightResolutions.remove(cacheKey);
      }
      if (!isSpeculative) {
        _activeUserResolutions--;
        if (_activeUserResolutions < 0) _activeUserResolutions = 0;
      }
    }
  }

  static Future<String> _doResolveAudioStreamUrl(
    String videoId, {
    String? songTitle,
    String? artist,
    required String quality,
    bool optimistic = true,
    bool isSpeculative = false,
    bool skipCompanionProxy = false,
    http.Client? client,
  }) async {
    final effectiveClient = client ?? clientOverride ?? _httpClient;
    LogService.recordBreadcrumb(
      'Resolving stream for $videoId (quality: $quality, optimistic: $optimistic, speculative: $isSpeculative, skipProxy: $skipCompanionProxy)',
      category: 'stream',
    );

    // Primary path (Android, user-initiated & speculative):
    // Resolve via on-device TeamNewPipe/NewPipeExtractor directly on the user's IP.
    try {
      final nativeStream =
          await NativeExtractorService.resolveAudioStream(videoId, quality: quality);
      if (nativeStream != null && nativeStream.url.isNotEmpty) {
        final itagStr = nativeStream.itag != null ? 'itag: ${nativeStream.itag}, ' : '';
        final bitrateStr = nativeStream.bitrate != null ? 'bitrate: ${nativeStream.bitrate}kbps, ' : '';
        final formatStr = nativeStream.format != null ? 'format: ${nativeStream.format}' : '';
        LogService.recordBreadcrumb(
          'Stream resolved via NewPipeExtractor for $videoId ($quality: $itagStr$bitrateStr$formatStr)',
          category: 'stream',
        );
        debugPrint(
          '⚡ Stream resolved via NewPipeExtractor for $videoId ($quality: $itagStr$bitrateStr$formatStr)',
        );
        _saveToCache(videoId, quality, nativeStream.url);
        return nativeStream.url;
      }
    } catch (e) {
      LogService.warning(
        'NewPipeExtractor resolution failed for $videoId: $e, falling back to secondary resolvers',
        tag: 'StreamResolver',
      );
    }

    if (isSpeculative) {
      // Speculative pre-warming only executes fast solvers
      final racedUrl = await _raceFastSolvers(
        videoId,
        quality: quality,
        optimistic: optimistic,
        client: effectiveClient,
      );
      if (racedUrl != null) {
        _saveToCache(videoId, quality, racedUrl);
        return racedUrl;
      }
      throw Exception('Speculative stream resolution skipped heavy fallbacks for $videoId');
    }

    // User-initiated resolution: Hedged parallel race
    final racedUrl = await _hedgedParallelRace(
      videoId,
      quality: quality,
      optimistic: optimistic,
      skipCompanionProxy: skipCompanionProxy,
      client: effectiveClient,
    );
    if (racedUrl != null) {
      LogService.recordBreadcrumb('Stream race WON for $videoId ($quality)', category: 'stream');
      _saveToCache(videoId, quality, racedUrl);
      return racedUrl;
    }

    // SMART ALTERNATIVE TRACK SEARCH:
    // Only invoked if both CompanionProxy and YoutubeExplode fail
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final cleanTitle = songTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      final query = Uri.encodeComponent('$cleanTitle ${artist ?? ''}'.trim());
      LogService.recordBreadcrumb('Direct streams unavailable for $videoId. Searching alternative for "$cleanTitle"...', category: 'stream');
      debugPrint('Direct stream for $videoId geoblocked or unavailable. Searching alternative for "$cleanTitle"...');

      final altAudio = await _searchAlternativeAudio(
        query,
        videoId,
        songTitle,
        quality: quality,
        timeout: const Duration(seconds: 10),
        client: effectiveClient,
      );
      if (altAudio != null) {
        _saveToCache(videoId, quality, altAudio);
        return altAudio;
      }
    }

    LogService.recordBreadcrumb('Stream resolution completely failed for $videoId', category: 'stream');
    LogService.error('Failed to resolve playable audio stream for video: $videoId', tag: 'StreamResolver');
    throw Exception('Failed to resolve playable audio stream for video: $videoId');
  }

  /// Resolves a stream selection specifically for offline downloads, preferring
  /// the highest-bitrate M4A (AAC / `audio/mp4`) stream with safe fallback.
  static Future<DownloadStreamSelection> resolveDownloadStream(
    String videoId, {
    String? songTitle,
    String? artist,
    http.Client? client,
  }) async {
    final effectiveClient = client ?? clientOverride ?? _httpClient;

    // 1. Primary: On-device extractor preferring highest-bitrate M4A
    try {
      final nativeStream = await NativeExtractorService.resolveAudioStream(
        videoId,
        quality: 'High',
        preferM4a: true,
      );
      if (nativeStream != null && nativeStream.url.isNotEmpty) {
        final fmt = normalizeDownloadFormat(
          nativeStream.mimeType,
          formatName: nativeStream.format,
          itag: nativeStream.itag,
        );
        return DownloadStreamSelection(
          url: nativeStream.url,
          mimeType: fmt.mimeType,
          extension: fmt.extension,
          bitrateBps: (nativeStream.bitrate ?? 0) * 1000,
          itag: nativeStream.itag,
        );
      }
    } catch (_) {}

    // 2. InnerTube player fast path preferring M4A
    if (!AntiBotService.isSafeModeActive) {
      final innertube = await _tryInnerTubeFastPathWithMeta(
        videoId,
        quality: 'High',
        preferM4a: true,
        client: effectiveClient,
      );
      if (innertube != null) {
        return innertube;
      }
    }

    // 3. Companion instances preferring M4A
    for (final instance in getHealthyInstances().take(2)) {
      final picked = await _extractAudioWithMetaFromInstance(
        instance,
        videoId,
        quality: 'High',
        timeout: const Duration(seconds: 4),
        optimistic: false,
        preferM4a: true,
        client: effectiveClient,
      );
      if (picked != null) {
        return picked;
      }
    }

    // 4. YoutubeExplode M4A fallback
    final ytSelection = await _resolveWithMetaViaYoutubeExplode(
      videoId,
      quality: 'High',
      optimistic: false,
      preferM4a: true,
      client: effectiveClient,
    );
    if (ytSelection != null) {
      return ytSelection;
    }

    // 5. Fallback to standard stream resolution with inferred extension/MIME
    final fallbackUrl = await resolveAudioStreamUrl(
      videoId,
      songTitle: songTitle,
      artist: artist,
      quality: 'High',
      optimistic: false,
      client: effectiveClient,
    );
    final uri = Uri.tryParse(fallbackUrl);
    final rawMime = uri?.queryParameters['mime'];
    final rawItag = int.tryParse(uri?.queryParameters['itag'] ?? '');
    final fmt = normalizeDownloadFormat(rawMime, itag: rawItag);
    return DownloadStreamSelection(
      url: fallbackUrl,
      mimeType: fmt.mimeType,
      extension: fmt.extension,
      itag: rawItag,
    );
  }

  /// Speculatively pre-resolves a stream and pre-caches its 5-second head
  /// in the background, capped at 1 in-flight request max and yielding to user play.
  static void preWarm(
    String videoId, {
    String? songTitle,
    String? artist,
    String? quality,
    bool isSpeculative = true,
    http.Client? client,
  }) {
    final effectiveQuality =
        DatabaseService.normalizeAudioQuality(quality ?? DatabaseService.getAudioQuality());
    final cacheKey = _cacheKey(videoId, effectiveQuality);
    if (_streamCache.containsKey(cacheKey) && !_streamCache[cacheKey]!.isExpired) return;
    if (isSpeculative && (_activeUserResolutions > 0 || _activeSpeculativeCount >= 1)) {
      debugPrint('StreamResolverService: Skipping speculative preWarm for $videoId (busy)');
      return;
    }

    if (isSpeculative) _activeSpeculativeCount++;
    unawaited(() async {
      try {
        final url = await resolveAudioStreamUrl(
          videoId,
          songTitle: songTitle,
          artist: artist,
          quality: effectiveQuality,
          optimistic: true,
          isSpeculative: isSpeculative,
          client: client,
        );
        await AudioCacheService.prefetchHead(videoId, url);
        debugPrint('⚡ Pre-warmed audio stream & head cache for $videoId');
      } catch (_) {
      } finally {
        if (isSpeculative) {
          _activeSpeculativeCount--;
          if (_activeSpeculativeCount < 0) _activeSpeculativeCount = 0;
        }
      }
    }());
  }

  static void dispose() {
    _httpClient.close();
    clientOverride?.close();
    _ytExplode.close();
  }
}
