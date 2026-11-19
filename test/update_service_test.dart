import 'dart:io';
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

    test('Handles -debug suffix in version comparison', () {
      expect(UpdateService.isNewerVersion('1.1.7-debug', '1.1.8-debug'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.7-debug', '1.1.8'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.8-debug', '1.1.7-debug'), isFalse);
      expect(UpdateService.isNewerVersion('1.1.7-debug', '1.1.7'), isFalse);
    });

    test('Compares build numbers when semantic version is identical', () {
      expect(UpdateService.isNewerVersion('1.0.0+1', '1.0.0+2'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0+2', '1.0.0+1'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0+1', '1.0.0+1'), isFalse);
      expect(UpdateService.isNewerVersion('1.1.7-debug+8', '1.1.7-debug+9'), isTrue);
    });
  });

  group('UpdateService Release vs Debug Asset Isolation Tests', () {
    final sampleAssets = [
      {
        'name': 'Melody-1.1.7-debug.apk',
        'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.7/Melody-1.1.7-debug.apk',
        'size': 108645594,
      },
      {
        'name': 'Melody-1.1.7-release.apk',
        'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.7/Melody-1.1.7-release.apk',
        'size': 45231200,
      },
    ];

    test('Release build strictly selects release APK and never debug APK', () {
      final selected = UpdateService.selectTargetApkAsset(sampleAssets, isDebug: false);
      expect(selected, 'https://github.com/justabean0/melody/releases/download/v1.1.7/Melody-1.1.7-release.apk');
      expect(selected, isNot(contains('debug')));
    });

    test('Debug build strictly selects debug APK and never release APK', () {
      final selected = UpdateService.selectTargetApkAsset(sampleAssets, isDebug: true);
      expect(selected, 'https://github.com/justabean0/melody/releases/download/v1.1.7/Melody-1.1.7-debug.apk');
      expect(selected, contains('debug'));
    });

    test('Release build ignores assets if only debug APK is uploaded', () {
      final debugOnlyAssets = [
        {
          'name': 'app-debug.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.7/app-debug.apk',
          'size': 108000000,
        }
      ];
      final selected = UpdateService.selectTargetApkAsset(debugOnlyAssets, isDebug: false);
      expect(selected, isNull);
    });

    test('Debug build ignores assets if only release APK is uploaded', () {
      final releaseOnlyAssets = [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.7/app-release.apk',
          'size': 45000000,
        }
      ];
      final selected = UpdateService.selectTargetApkAsset(releaseOnlyAssets, isDebug: true);
      expect(selected, isNull);
    });
  });

  group('UpdateService Pubspec Version Sync Tests', () {
    test('Fallback constants match pubspec.yaml version and build number', () {
      final pubspecFile = File('pubspec.yaml');
      expect(pubspecFile.existsSync(), isTrue);
      final content = pubspecFile.readAsStringSync();
      final match = RegExp(r'^version:\s*([0-9.]+)\+([0-9]+)', multiLine: true).firstMatch(content);
      expect(match, isNotNull, reason: 'version string should be found in pubspec.yaml');
      final expectedVersion = match!.group(1);
      final expectedBuild = int.parse(match.group(2)!);

      expect(UpdateService.appVersion, equals(expectedVersion));
      expect(UpdateService.appBuildNumber, equals(expectedBuild));
    });
  });
}
