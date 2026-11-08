import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/update_service.dart';

void main() {
  group('UpdateService Semantic Version Comparison Tests', () {
    test('Detects standard patch upgrade', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isFalse);
    });

    test('Handles v prefix gracefully', () {
      expect(UpdateService.isNewerVersion('v1.0.0', 'v1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', 'v1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.1', '1.0.0'), isFalse);
    });

    test('Detects minor and major upgrades', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.1.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.9', '1.1.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.9.9', '2.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isFalse);
    });

    test('Handles identical versions as no update', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.2.3', '1.2.3'), isFalse);
    });

    test('Compares build numbers when semantic version is identical', () {
      expect(UpdateService.isNewerVersion('1.0.0+1', '1.0.0+2'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0+2', '1.0.0+1'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0+1', '1.0.0+1'), isFalse);
    });
  });
}
