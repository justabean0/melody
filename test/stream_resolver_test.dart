import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/stream_resolver_service.dart';

void main() {
  setUp(() {
    AntiBotService.reset();
    StreamResolverService.clearCache();
    StreamResolverService.clientOverride = null;
  });

  tearDown(() {
    StreamResolverService.clientOverride = null;
    StreamResolverService.clearCache();
  });

  group('StreamResolverService Hermetic Tests', () {
    test('In-memory cache hit avoids repeat HTTP calls', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        if (request.url.toString().contains('youtubei/v1/player')) {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                    'bitrate': 131072,
                    'url': 'https://rr1.googlevideo.com/videoplayback?id=cached_track',
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final firstUrl = await StreamResolverService.resolveAudioStreamUrl(
        'test_video_cache',
        client: mockClient,
      );
      expect(firstUrl, 'https://rr1.googlevideo.com/videoplayback?id=cached_track');
      final requestsAfterFirst = requestCount;
      expect(requestsAfterFirst, greaterThan(0));

      final secondUrl = await StreamResolverService.resolveAudioStreamUrl(
        'test_video_cache',
        client: mockClient,
      );
      expect(secondUrl, firstUrl);
      expect(requestCount, equals(requestsAfterFirst));
    });

    test('Direct InnerTube success resolves without needing proxy', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('youtubei/v1/player')) {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'OK'},
              'streamingData': {
                'adaptiveFormats': [
                  {
                    'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                    'bitrate': 160000,
                    'url': 'https://rr2.googlevideo.com/videoplayback?id=innertube_direct',
                  }
                ]
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final url = await StreamResolverService.resolveAudioStreamUrl(
        'direct_video_123',
        client: mockClient,
      );

      expect(url, 'https://rr2.googlevideo.com/videoplayback?id=innertube_direct');
    });

    test('Invidious proxy fallback when direct InnerTube fails', () async {
      final mockClient = MockClient((request) async {
        final uriStr = request.url.toString();
        if (uriStr.contains('youtubei/v1/player')) {
          return http.Response(
            jsonEncode({
              'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (uriStr.contains('/api/v1/videos/fallback_video')) {
          return http.Response(
            jsonEncode({
              'adaptiveFormats': [
                {
                  'type': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': 128000,
                  'url': 'https://yt.chocolatemoo53.com/videoplayback?id=invidious_proxy',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (uriStr.contains('videoplayback?id=invidious_proxy')) {
          return http.Response('', 200, headers: {'content-type': 'audio/mp4'});
        }
        return http.Response('Not found', 404);
      });

      final url = await StreamResolverService.resolveAudioStreamUrl(
        'fallback_video',
        client: mockClient,
      );

      expect(url, 'https://yt.chocolatemoo53.com/videoplayback?id=invidious_proxy');
    });

    test('Graceful error handling when all tiers fail', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server error', 500);
      });

      expect(
        () => StreamResolverService.resolveAudioStreamUrl(
          'unplayable_video_id',
          client: mockClient,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Simultaneous concurrent requests for same videoId are deduplicated', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'adaptiveFormats': [
                {
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': 131072,
                  'url': 'https://rr1.googlevideo.com/videoplayback?id=dedup_track',
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final results = await Future.wait([
        StreamResolverService.resolveAudioStreamUrl('concurrent_track', client: mockClient),
        StreamResolverService.resolveAudioStreamUrl('concurrent_track', client: mockClient),
        StreamResolverService.resolveAudioStreamUrl('concurrent_track', client: mockClient),
      ]);

      expect(results[0], 'https://rr1.googlevideo.com/videoplayback?id=dedup_track');
      expect(results[1], results[0]);
      expect(results[2], results[0]);
      expect(requestCount, lessThanOrEqualTo(2));
    });
  });
}
