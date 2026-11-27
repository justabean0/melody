import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'log_service.dart';

class NativeAudioStream {
  final String url;
  final int? itag;
  final int? bitrate;
  final String? format;
  final String? mimeType;
  final int? durationMs;

  const NativeAudioStream({
    required this.url,
    this.itag,
    this.bitrate,
    this.format,
    this.mimeType,
    this.durationMs,
  });

  @override
  String toString() =>
      'NativeAudioStream(itag: $itag, bitrate: $bitrate, format: $format, mimeType: $mimeType, durationMs: $durationMs)';
}

class NativeExtractorService {
  static const MethodChannel _channel = MethodChannel('com.melody.music/extractor');

  @visibleForTesting
  static Future<NativeAudioStream?> Function(String videoId)? testResolver;

  @visibleForTesting
  static Future<NativeAudioStream?> Function(String videoId, String quality)?
      testQualityResolver;

  /// Resolves an audio stream on-device using TeamNewPipe/NewPipeExtractor.
  /// Enforces a 12-second timeout and returns null on failure or non-Android platforms.
  static Future<NativeAudioStream?> resolveAudioStream(
    String videoId, {
    String quality = 'High',
    bool preferM4a = false,
  }) async {
    if (testQualityResolver != null) {
      return await testQualityResolver!(videoId, quality);
    }
    if (testResolver != null) {
      return await testResolver!(videoId);
    }

    try {
      final args = <String, dynamic>{
        'videoId': videoId,
        'quality': quality,
      };
      if (preferM4a) {
        args['preferM4a'] = true;
      }
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'resolveAudioStream',
        args,
      ).timeout(const Duration(seconds: 12));

      if (res == null) return null;

      final url = res['url']?.toString();
      if (url == null || url.isEmpty || !url.startsWith('https://')) {
        LogService.warning(
          'NativeExtractor returned invalid or non-HTTPS URL for $videoId',
          tag: 'NativeExtractor',
        );
        return null;
      }

      final itag = res['itag'] is int
          ? res['itag'] as int
          : int.tryParse(res['itag']?.toString() ?? '');
      final bitrate = res['bitrate'] is int
          ? res['bitrate'] as int
          : int.tryParse(res['bitrate']?.toString() ?? '');
      final format = res['format']?.toString();
      final mimeType = res['mimeType']?.toString();
      final durationMs = res['durationMs'] is int
          ? res['durationMs'] as int
          : int.tryParse(res['durationMs']?.toString() ?? '');

      return NativeAudioStream(
        url: url,
        itag: itag,
        bitrate: bitrate,
        format: format,
        mimeType: mimeType,
        durationMs: durationMs,
      );
    } on MissingPluginException {
      // Expected in hermetic unit test environments or non-supported platforms
      LogService.warning(
        'NewPipeExtractor method channel not implemented on current platform',
        tag: 'NativeExtractor',
      );
      return null;
    } on TimeoutException {
      LogService.warning(
        'NativeExtractor timed out after 12s for $videoId',
        tag: 'NativeExtractor',
      );
      return null;
    } catch (e) {
      LogService.warning(
        'NativeExtractor extraction failed for $videoId: $e',
        tag: 'NativeExtractor',
      );
      return null;
    }
  }
}
