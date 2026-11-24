import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:melody/services/update_service.dart';

class MockUrlLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  String? launchedUrl;
  PreferredLaunchMode? launchMode;
  bool returnSuccess = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    launchMode = options.mode;
    return returnSuccess;
  }

  @override
  Future<bool> canLaunch(String url) async => true;
}

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

    test('Correctly separates app-release.apk and melody-debug.apk', () {
      final dualAssets = [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-release.apk',
          'size': 28320396,
        },
        {
          'name': 'melody-debug.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.8/melody-debug.apk',
          'size': 108678587,
        },
      ];

      final releaseSelected = UpdateService.selectTargetApkAsset(dualAssets, isDebug: false);
      expect(releaseSelected, 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-release.apk');

      final debugSelected = UpdateService.selectTargetApkAsset(dualAssets, isDebug: true);
      expect(debugSelected, 'https://github.com/justabean0/melody/releases/download/v1.1.8/melody-debug.apk');
    });

    test('Debug/diag build correctly selects diag release APK', () {
      final diagAssets = [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-release.apk',
          'size': 42000000,
        },
        {
          'name': 'app-diag-release.apk',
          'browser_download_url': 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-diag-release.apk',
          'size': 45000000,
        },
      ];

      final selected = UpdateService.selectTargetApkAsset(diagAssets, isDebug: true);
      expect(selected, 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-diag-release.apk');

      final releaseSelected = UpdateService.selectTargetApkAsset(diagAssets, isDebug: false);
      expect(releaseSelected, 'https://github.com/justabean0/melody/releases/download/v1.1.8/app-release.apk');
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

  group('UpdateService Browser Update Launch Tests', () {
    test('launchUpdateUrl invokes externalApplication mode with provided URL', () async {
      final mock = MockUrlLauncher();
      UrlLauncherPlatform.instance = mock;

      const testUrl = 'https://github.com/justabean0/melody/releases/download/v1.1.11/app-release.apk';
      final result = await UpdateService.launchUpdateUrl(testUrl);

      expect(result, isTrue);
      expect(mock.launchedUrl, equals(testUrl));
      expect(mock.launchMode, equals(PreferredLaunchMode.externalApplication));
    });

    test('launchUpdateUrl returns false when platform launcher reports failure', () async {
      final mock = MockUrlLauncher();
      mock.returnSuccess = false;
      UrlLauncherPlatform.instance = mock;

      const testUrl = 'https://invalid-url';
      final result = await UpdateService.launchUpdateUrl(testUrl);

      expect(result, isFalse);
    });
  });
}
