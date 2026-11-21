import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'stream_resolver_service.dart';

/// Local 5-Second Audio Head Cache & Embedded Loopback Proxy
///
/// Ensures ZERO-DELAY playback startup by caching ONLY the first 5-8 seconds
/// (~128 KB) of songs on local storage. It deliberately NEVER downloads or caches
/// the full song, keeping device storage minimal (<5 MB max) while eliminating
/// network buffering delay.
class AudioCacheService {
  static HttpServer? _proxyServer;
  static int _port = 0;
  static Directory? _headsDir;
  static final http.Client _httpClient = http.Client();

  /// Default head chunk size: 128 KB (~6-8 seconds of 128kbps AAC / Opus)
  static const int headChunkSize = 131072;

  /// Bounded upstream chunk size: 256 KB per request to avoid idle TCP drops while paused
  static const int upstreamChunkSize = 262144;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Max head files to keep on disk (~12.8 MB total for 100 songs)
  static const int maxCachedHeads = 100;

  static int get proxyPort => _port;
  static bool get isProxyRunning => _proxyServer != null;

  /// Initializes the 5-second head disk cache directory and embedded loopback proxy
  static Future<void> init() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      _headsDir = Directory('${baseDir.path}/melody_heads');

      if (!await _headsDir!.exists()) {
        await _headsDir!.create(recursive: true);
      }

      // Purge any legacy full-song cache directories from previous versions
      final legacySongsDir = Directory('${baseDir.path}/melody_songs');
      if (await legacySongsDir.exists()) {
        try {
          await legacySongsDir.delete(recursive: true);
          debugPrint('AudioCacheService: Purged legacy full-song cache directory');
        } catch (_) {}
      }

      // Bind loopback proxy server to an ephemeral port
      _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _proxyServer!.port;
      debugPrint('AudioCacheService: Local 5s head caching proxy listening on port $_port');

      _proxyServer!.listen(_handleProxyRequest, onError: (e) {
        debugPrint('AudioCacheService: Proxy server error: $e');
      });
    } catch (e) {
      debugPrint('AudioCacheService init warning: $e');
    }
  }

  /// Handles incoming HTTP range streaming requests from AudioPlayer
  static Future<void> _handleProxyRequest(HttpRequest request) async {
    final response = request.response;
    try {
      // Security: Strictly enforce loopback connections only
      if (request.connectionInfo?.remoteAddress.isLoopback != true) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      final id = request.uri.queryParameters['id'] ?? '';
      final rawRemoteUrl = request.uri.queryParameters['url'] ?? '';

      if (rawRemoteUrl.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }

      Uri remoteUri = Uri.parse(Uri.decodeComponent(rawRemoteUrl));
      final incomingRange = request.headers.value(HttpHeaders.rangeHeader);

      int reqStart = 0;
      int? reqEnd;
      if (incomingRange != null) {
        final trimmed = incomingRange.trim();
        if (!trimmed.startsWith('bytes=')) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */*');
          await response.close();
          return;
        }
        final spec = trimmed.substring(6).trim();
        final parts = spec.split('-');
        if (parts.length != 2) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */*');
          await response.close();
          return;
        }
        final parsedStart = int.tryParse(parts[0]);
        if (parsedStart == null || parsedStart < 0) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */*');
          await response.close();
          return;
        }
        reqStart = parsedStart;
        if (parts[1].isNotEmpty) {
          final parsedEnd = int.tryParse(parts[1]);
          if (parsedEnd == null || parsedEnd < reqStart) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */*');
            await response.close();
            return;
          }
          reqEnd = parsedEnd;
        }
      }

      final headFile = File('${_headsDir?.path}/$id.head');
      final metaFile = File('${_headsDir?.path}/$id.meta');
      final hasHead = await headFile.exists() && await metaFile.exists();

      int totalLength = 0;
      Uint8List? headBytes;

      if (hasHead) {
        headBytes = await headFile.readAsBytes();
        final metaContent = (await metaFile.readAsString()).trim();
        totalLength = int.tryParse(metaContent) ?? (headBytes.length * 20);
      } else {
        totalLength = int.tryParse(remoteUri.queryParameters['clen'] ?? '') ?? 0;
      }

      if (totalLength > 0 && reqStart >= totalLength) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        await response.close();
        return;
      }

      // Fast-path: start inside or at beginning of cached 5s head
      if (headBytes != null && reqStart < headBytes.length) {
        if (totalLength <= 0) totalLength = headBytes.length * 20;
        final effectiveEnd = (reqEnd != null && reqEnd < totalLength) ? reqEnd : totalLength - 1;
        final contentLength = effectiveEnd - reqStart + 1;

        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $reqStart-$effectiveEnd/$totalLength');
        response.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
        response.headers.contentType = ContentType('audio', 'mp4');

        final headSliceEnd = headBytes.length < effectiveEnd + 1 ? headBytes.length : effectiveEnd + 1;
        response.add(headBytes.sublist(reqStart, headSliceEnd));
        await response.flush();

        final currentOffset = headSliceEnd;
        if (currentOffset <= effectiveEnd) {
          await _streamBoundedChunks(
            response: response,
            videoId: id,
            initialRemoteUri: remoteUri,
            startOffset: currentOffset,
            endOffset: effectiveEnd,
          );
        } else {
          await response.close();
        }
        return;
      }

      // Passthrough / Seek beyond cached head:
      // Request initial chunk upstream to discover exact total length & content type if unknown
      var firstChunkEnd = reqStart + upstreamChunkSize - 1;
      if (reqEnd != null && reqEnd < firstChunkEnd) {
        firstChunkEnd = reqEnd;
      }
      if (totalLength > 0 && firstChunkEnd >= totalLength) {
        firstChunkEnd = totalLength - 1;
      }

      final probeReq = http.Request('GET', remoteUri)
        ..headers[HttpHeaders.rangeHeader] = 'bytes=$reqStart-$firstChunkEnd'
        ..headers['User-Agent'] = _defaultUserAgent;

      http.StreamedResponse remoteRes = await _httpClient.send(probeReq);

      // Handle stream expiration or 403/502/416
      if ((remoteRes.statusCode >= 400 || remoteRes.statusCode == HttpStatus.requestedRangeNotSatisfiable) && id.isNotEmpty) {
        StreamResolverService.invalidateCache(id);
        await evict(id);
        try {
          final freshUrl = await StreamResolverService.resolveAudioStreamUrl(id, optimistic: false);
          remoteUri = Uri.parse(freshUrl);
          final retryReq = http.Request('GET', remoteUri)
            ..headers[HttpHeaders.rangeHeader] = 'bytes=$reqStart-$firstChunkEnd'
            ..headers['User-Agent'] = _defaultUserAgent;
          final retryRes = await _httpClient.send(retryReq);
          if (retryRes.statusCode < 400) {
            remoteRes = retryRes;
          }
        } catch (_) {}
      }

      if (remoteRes.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        await response.close();
        return;
      }

      if (remoteRes.statusCode == HttpStatus.ok) {
        if (reqStart > 0) {
          // Upstream ignored Range header and returned full stream starting from 0.
          // Skip the first reqStart bytes.
          response.statusCode = HttpStatus.partialContent;
          final effectiveEnd = (reqEnd != null && reqEnd < totalLength) ? reqEnd : (totalLength > 0 ? totalLength - 1 : null);
          response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          if (effectiveEnd != null && totalLength > 0) {
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $reqStart-$effectiveEnd/$totalLength');
            response.headers.set(HttpHeaders.contentLengthHeader, '${effectiveEnd - reqStart + 1}');
          }
          var skipped = 0;
          var sent = 0;
          await for (final chunk in remoteRes.stream) {
            if (skipped + chunk.length <= reqStart) {
              skipped += chunk.length;
              continue;
            }
            final sliceStart = (reqStart > skipped) ? reqStart - skipped : 0;
            skipped += chunk.length;
            final dataToSend = chunk.sublist(sliceStart);
            if (effectiveEnd != null && (reqStart + sent + dataToSend.length - 1 > effectiveEnd)) {
              final needed = effectiveEnd - (reqStart + sent) + 1;
              if (needed > 0) {
                response.add(dataToSend.sublist(0, needed));
                sent += needed;
              }
              break;
            } else {
              response.add(dataToSend);
              sent += dataToSend.length;
            }
          }
          await response.close();
          return;
        } else {
          // reqStart == 0
          response.statusCode = HttpStatus.ok;
          remoteRes.headers.forEach((name, value) {
            final lower = name.toLowerCase();
            if (lower != 'content-encoding' && lower != 'transfer-encoding' && lower != 'connection') {
              response.headers.set(name, value);
            }
          });
          await response.addStream(remoteRes.stream);
          await response.close();
          return;
        }
      }

      // Extract total length from Content-Range header: bytes start-end/total
      final cr = remoteRes.headers[HttpHeaders.contentRangeHeader] ?? '';
      if (cr.contains('/')) {
        final totalStr = cr.split('/').last.trim();
        totalLength = int.tryParse(totalStr) ?? totalLength;
      }
      if (totalLength <= 0) {
        totalLength = remoteRes.contentLength ?? (headChunkSize * 250);
      }

      final effectiveEnd = (reqEnd != null && reqEnd < totalLength) ? reqEnd : totalLength - 1;
      final contentLength = effectiveEnd - reqStart + 1;

      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $reqStart-$effectiveEnd/$totalLength');
      response.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());

      final ct = remoteRes.headers[HttpHeaders.contentTypeHeader];
      if (ct != null) {
        try {
          response.headers.contentType = ContentType.parse(ct);
        } catch (_) {
          response.headers.contentType = ContentType('audio', 'mp4');
        }
      } else {
        response.headers.contentType = ContentType('audio', 'mp4');
      }

      var currentOffset = reqStart;
      await for (final chunk in remoteRes.stream) {
        response.add(chunk);
        currentOffset += chunk.length;
      }
      await response.flush();

      if (currentOffset <= effectiveEnd) {
        await _streamBoundedChunks(
          response: response,
          videoId: id,
          initialRemoteUri: remoteUri,
          startOffset: currentOffset,
          endOffset: effectiveEnd,
        );
      } else {
        await response.close();
      }
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Streams remaining bytes in bounded chunks (256 KB) with automatic retry and stream re-resolution
  static Future<void> _streamBoundedChunks({
    required HttpResponse response,
    required String videoId,
    required Uri initialRemoteUri,
    required int startOffset,
    required int endOffset,
  }) async {
    var currentOffset = startOffset;
    var remoteUri = initialRemoteUri;

    while (currentOffset <= endOffset) {
      var chunkEnd = currentOffset + upstreamChunkSize - 1;
      if (chunkEnd > endOffset) {
        chunkEnd = endOffset;
      }

      int retries = 0;
      bool chunkSuccess = false;

      while (retries < 3 && !chunkSuccess) {
        try {
          final chunkReq = http.Request('GET', remoteUri)
            ..headers[HttpHeaders.rangeHeader] = 'bytes=$currentOffset-$chunkEnd'
            ..headers['User-Agent'] = _defaultUserAgent;

          final chunkRes = await _httpClient.send(chunkReq).timeout(const Duration(seconds: 8));

          if (chunkRes.statusCode == HttpStatus.partialContent ||
              (chunkRes.statusCode == HttpStatus.ok && currentOffset == 0)) {
            await for (final data in chunkRes.stream) {
              response.add(data);
              currentOffset += data.length;
            }
            await response.flush();
            chunkSuccess = true;
          } else if (chunkRes.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
            // Requested past EOF: finish streaming cleanly
            debugPrint('AudioCacheService: Upstream 416 at $currentOffset-$chunkEnd. Terminating chunk stream cleanly.');
            return;
          } else if (chunkRes.statusCode >= 400) {
            if (videoId.isNotEmpty) {
              StreamResolverService.invalidateCache(videoId);
              await evict(videoId);
              try {
                final freshUrl = await StreamResolverService.resolveAudioStreamUrl(videoId, optimistic: false);
                remoteUri = Uri.parse(freshUrl);
              } catch (_) {}
            }
            retries++;
            if (retries < 3) await Future.delayed(Duration(milliseconds: 150 * retries));
          } else {
            retries++;
            if (retries < 3) await Future.delayed(Duration(milliseconds: 150 * retries));
          }
        } on SocketException catch (_) {
          // Client player closed or seeked away
          return;
        } on HttpException catch (_) {
          return;
        } catch (e) {
          retries++;
          if (retries >= 3) {
            debugPrint('AudioCacheService: Chunk retry exhausted at $currentOffset: $e');
            return;
          }
          await Future.delayed(Duration(milliseconds: 150 * retries));
        }
      }

      if (!chunkSuccess) {
        break;
      }
    }

    try {
      await response.close();
    } catch (_) {}
  }

  /// Evicts the cached head and metadata for a specific video ID.
  static Future<void> evict(String videoId) async {
    if (_headsDir == null) return;
    try {
      final headFile = File('${_headsDir!.path}/$videoId.head');
      final metaFile = File('${_headsDir!.path}/$videoId.meta');
      if (await headFile.exists()) {
        await headFile.delete();
      }
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
      debugPrint('AudioCacheService: Evicted head cache for $videoId');
    } catch (e) {
      debugPrint('AudioCacheService: Error evicting head cache for $videoId: $e');
    }
  }

  /// Pre-caches the first 5-8 seconds (~128 KB) of an upcoming or played track to disk
  static Future<void> prefetchHead(String videoId, String remoteUrl) async {
    if (_headsDir == null) return;
    try {
      final headFile = File('${_headsDir!.path}/$videoId.head');
      final metaFile = File('${_headsDir!.path}/$videoId.meta');

      if (await headFile.exists() && await metaFile.exists()) {
        final metaContent = (await metaFile.readAsString()).trim();
        final existingLen = int.tryParse(metaContent);
        if (existingLen != null && existingLen > 0) {
          try {
            await headFile.setLastModified(DateTime.now());
          } catch (_) {}
          return; // Already cached and valid
        } else {
          await evict(videoId);
        }
      }

      final uri = Uri.parse(remoteUrl);
      final req = http.Request('GET', uri)
        ..headers[HttpHeaders.rangeHeader] = 'bytes=0-${headChunkSize - 1}'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      final streamedRes = await _httpClient.send(req).timeout(const Duration(seconds: 4));
      if (streamedRes.statusCode >= 400) {
        await evict(videoId);
        return;
      }

      if (streamedRes.statusCode == HttpStatus.ok || streamedRes.statusCode == HttpStatus.partialContent) {
        // Extract exact content-length from URL parameter 'clen' if present (embedded by YouTube/Invidious)
        int totalLength = int.tryParse(uri.queryParameters['clen'] ?? '') ?? 0;

        final contentRange = streamedRes.headers['content-range'] ?? '';
        if (totalLength == 0 && contentRange.contains('/')) {
          totalLength = int.tryParse(contentRange.split('/').last) ?? 0;
        }
        if (totalLength == 0) {
          totalLength = streamedRes.contentLength ?? 0;
        }
        // Generous fallback (~32 MB) for long tracks (15-30 mins) so seeking is never clipped by small estimates
        if (totalLength == 0) {
          totalLength = headChunkSize * 250;
        }

        final bytes = await streamedRes.stream.toBytes();
        if (bytes.isNotEmpty) {
          await headFile.writeAsBytes(bytes, flush: true);
          await metaFile.writeAsString(totalLength.toString(), flush: true);
          debugPrint('AudioCacheService: Pre-cached 5s head for $videoId (${bytes.length} bytes, total: $totalLength)');

          // Keep head cache compact
          await _pruneHeadsCache();
        }
      }
    } catch (e) {
      debugPrint('AudioCacheService: Head prefetch skipped for $videoId: $e');
    }
  }

  /// Ensures the 5-second head for any played or listened-to song is cached on disk.
  static void ensureHeadCached(String videoId, String remoteUrl) {
    unawaited(prefetchHead(videoId, remoteUrl));
  }

  /// Prunes old 5s heads if cached count exceeds maxCachedHeads
  static Future<void> _pruneHeadsCache() async {
    if (_headsDir == null) return;
    try {
      final entities = await _headsDir!.list().toList();
      final headFiles = entities.whereType<File>().where((f) => f.path.endsWith('.head')).toList();
      if (headFiles.length > maxCachedHeads) {
        headFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        final toRemove = headFiles.take(headFiles.length - maxCachedHeads);
        for (final f in toRemove) {
          final metaPath = f.path.replaceAll('.head', '.meta');
          try {
            await f.delete();
            final metaFile = File(metaPath);
            if (await metaFile.exists()) await metaFile.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Checks if the first 5-8 seconds are pre-cached on local storage
  static bool hasCachedHead(String videoId) {
    if (_headsDir == null) return false;
    final head = File('${_headsDir!.path}/$videoId.head');
    return head.existsSync() && head.lengthSync() > 1000;
  }

  /// Determines the optimal playable source URL:
  /// 1. Local loopback proxy if 5s head is cached (<2ms start)
  /// 2. Direct remote URL otherwise
  /// Deliberately never downloads or caches full songs on disk.
  static String getPlayableUrl(String videoId, String remoteUrl) {
    if (isProxyRunning && hasCachedHead(videoId)) {
      debugPrint('AudioCacheService: Using 5s head cache proxy for $videoId');
      final encoded = Uri.encodeComponent(remoteUrl);
      return 'http://127.0.0.1:$_port/stream?id=$videoId&url=$encoded';
    }

    return remoteUrl;
  }

  /// Clears all 5-second head files from disk
  static Future<void> clearHeadCache() async {
    if (_headsDir != null && await _headsDir!.exists()) {
      try {
        final entities = await _headsDir!.list().toList();
        for (final entity in entities) {
          if (entity is File) await entity.delete();
        }
        debugPrint('AudioCacheService: Cleared all 5-second head cache files');
      } catch (e) {
        debugPrint('AudioCacheService: Error clearing head cache: $e');
      }
    }
  }

  /// Disposes background server and HTTP resources
  static Future<void> dispose() async {
    _httpClient.close();
    await _proxyServer?.close(force: true);
    _proxyServer = null;
  }
}
