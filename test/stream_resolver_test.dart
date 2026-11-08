import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/stream_resolver_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = _RealHttpOverrides();

  group('StreamResolverService Tests', () {
    test('Resolves audio stream with active probe validation for standard track', () async {
      final url = await StreamResolverService.resolveAudioStreamUrl(
        'dQw4w9WgXcQ',
        songTitle: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
      );

      expect(url, isNotEmpty);
      expect(url.startsWith('https://'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Resolves audio stream with geoblock fallback for restricted track', () async {
      final url = await StreamResolverService.resolveAudioStreamUrl(
        'kJQP7kiw5Fk',
        songTitle: 'Despacito',
        artist: 'Luis Fonsi',
      );

      expect(url, isNotEmpty);
      expect(url.startsWith('https://'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Resolves audio stream with alternative matching for Mayabono Biharini', () async {
      final url = await StreamResolverService.resolveAudioStreamUrl(
        '5xPad9wg1B4',
        songTitle: 'Mayabono Biharini',
        artist: 'Somlata',
      );

      expect(url, isNotEmpty);
      expect(url.startsWith('https://'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Stream URL Cache returns instantly (0ms) on repeated requests', () async {
      final sw = Stopwatch()..start();
      // Second request for Mayabono Biharini must hit memory cache instantly
      final cachedUrl = await StreamResolverService.resolveAudioStreamUrl('5xPad9wg1B4');
      sw.stop();

      expect(cachedUrl, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(20)); // Sub-20ms cache hit
    });
  });
}
