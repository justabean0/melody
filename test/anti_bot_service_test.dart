import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/anti_bot_service.dart';
import 'package:melody/services/audio_cache_service.dart';

void main() {
  setUp(() {
    AntiBotService.reset();
  });

  group('AntiBotService Proactive Circuit Breaker Tests', () {
    test('Initial state has safe mode inactive', () {
      expect(AntiBotService.isSafeModeActive, isFalse);
      expect(AntiBotService.activeReason, isNull);
    });

    test('Normal usage (1-2 searches) does not trip safe mode', () {
      AntiBotService.recordSearch(query: 'Coldplay');
      AntiBotService.recordSearch(query: 'Fix You');

      expect(AntiBotService.isSafeModeActive, isFalse);
    });

    test('Burst search (> 3 searches in 15s) trips safe mode proactively BEFORE bot check', () {
      AntiBotService.recordSearch(query: 'Track 1');
      AntiBotService.recordSearch(query: 'Track 2');
      AntiBotService.recordSearch(query: 'Track 3');

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Burst search pattern'));
      expect(AntiBotService.remainingCooldown, isNotNull);
      expect(AntiBotService.remainingCooldown!.inSeconds, greaterThan(0));
    });

    test('Burst playback / track skipping (> 3 plays in 15s) trips safe mode proactively', () {
      AntiBotService.recordPlay(videoId: 'vid1');
      AntiBotService.recordPlay(videoId: 'vid2');
      AntiBotService.recordPlay(videoId: 'vid3');

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Rapid track skipping'));
    });

    test('Combined burst activity (e.g. 2 searches + 2 plays in 15s) trips safe mode', () {
      AntiBotService.recordSearch(query: 'Query 1');
      AntiBotService.recordSearch(query: 'Query 2');
      AntiBotService.recordPlay(videoId: 'vidA');
      AntiBotService.recordPlay(videoId: 'vidB');

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Combined burst activity'));
    });

    test('tripOnBotDetected reactively activates 3-minute extended safe mode', () {
      AntiBotService.tripOnBotDetected('LOGIN_REQUIRED');

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('LOGIN_REQUIRED'));
      expect(AntiBotService.remainingCooldown!.inSeconds, greaterThan(120));
    });

    test('Reset clears all active shields and cooldowns', () {
      AntiBotService.tripOnBotDetected('Test');
      expect(AntiBotService.isSafeModeActive, isTrue);

      AntiBotService.reset();
      expect(AntiBotService.isSafeModeActive, isFalse);
      expect(AntiBotService.activeReason, isNull);
    });
  });

  group('AudioCacheService (5-Second Head Only) Tests', () {
    test('getPlayableUrl never returns local full-song file path', () {
      const remoteUrl = 'https://example.com/audio_stream.mp4';
      final result = AudioCacheService.getPlayableUrl('non_cached_id', remoteUrl);

      // Without head cache, must return the remote stream URL directly
      expect(result, equals(remoteUrl));
      // Must NEVER return a local .m4a or full-song file path
      expect(result.endsWith('.m4a'), isFalse);
    });

    test('Audio head size constant is strictly 128 KB (~5-8s of audio)', () {
      expect(AudioCacheService.headChunkSize, equals(131072)); // 128 KB
      expect(AudioCacheService.maxCachedHeads, equals(30));
    });
  });
}
