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

    test('Burst search (> 8 searches in 15s) trips safe mode proactively BEFORE bot check', () {
      for (int i = 0; i < 8; i++) {
        AntiBotService.recordSearch(query: 'Track $i');
      }

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Burst search pattern'));
      expect(AntiBotService.remainingCooldown, isNotNull);
      expect(AntiBotService.remainingCooldown!.inSeconds, greaterThan(0));
    });

    test('Burst playback / track skipping (> 12 plays in 15s) trips safe mode proactively', () {
      for (int i = 0; i < 12; i++) {
        AntiBotService.recordPlay(videoId: 'vid$i');
      }

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Rapid track skipping'));
    });

    test('Combined burst activity (> 15 searches + plays in 15s) trips safe mode', () {
      for (int i = 0; i < 5; i++) {
        AntiBotService.recordSearch(query: 'Query $i');
      }
      for (int i = 0; i < 11; i++) {
        AntiBotService.recordPlay(videoId: 'vid$i');
      }

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('Combined burst activity'));
    });

    test('tripOnBotDetected reactively activates extended safe mode', () {
      AntiBotService.tripOnBotDetected('LOGIN_REQUIRED');

      expect(AntiBotService.isSafeModeActive, isTrue);
      expect(AntiBotService.activeReason, contains('LOGIN_REQUIRED'));
      expect(AntiBotService.remainingCooldown!.inSeconds, greaterThan(90));
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
