import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String changelog;
  final String downloadUrl;
  final int? apkSize;
  final bool hasUpdate;
  final String releaseName;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.changelog,
    required this.downloadUrl,
    this.apkSize,
    required this.hasUpdate,
    required this.releaseName,
  });
}

class UpdateService {
  static const MethodChannel _channel = MethodChannel('com.melody.music/updater');
  static final http.Client _httpClient = http.Client();

  /// Default application version matching pubspec.yaml
  static const String appVersion = '1.1.6';
  static const int appBuildNumber = 8;

  /// Retrieves the running app version from the native platform (or fallback)
  static Future<String> getCurrentVersion() async {
    if (Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
        if (res != null) {
          final vName = res['versionName'] as String?;
          if (vName != null && vName.isNotEmpty) {
            return vName;
          }
        }
      } catch (e) {
        debugPrint('Error getting native version: $e');
      }
    }
    return appVersion;
  }

  /// Checks whether the running app build is a Debug variant
  static Future<bool> isDebugBuild() async {
    if (kDebugMode) return true;
    if (Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
        if (res != null) {
          final isDebug = res['isDebug'] as bool? ?? false;
          final pkg = res['packageName'] as String? ?? '';
          final vName = res['versionName'] as String? ?? '';
          return isDebug || pkg.endsWith('.debug') || vName.contains('debug');
        }
      } catch (_) {}
    }
    return false;
  }

  /// Compares semantic versions (e.g., '1.0.1' > '1.0.0')
  static bool isNewerVersion(String current, String remote) {
    try {
      final cleanCurrent = current
          .replaceFirst(RegExp(r'^[vV]'), '')
          .split('+')[0]
          .split('-')[0];
      final cleanRemote = remote
          .replaceFirst(RegExp(r'^[vV]'), '')
          .split('+')[0]
          .split('-')[0];

      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final remoteParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }

      // If versions are identical, compare build number if available
      final currentBuild = _extractBuildNumber(current);
      final remoteBuild = _extractBuildNumber(remote);
      if (remoteBuild != null && currentBuild != null) {
        return remoteBuild > currentBuild;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  static int? _extractBuildNumber(String ver) {
    if (ver.contains('+')) {
      final part = ver.split('+').last;
      return int.tryParse(part);
    }
    return null;
  }

  /// Filters release assets strictly separating release vs debug APKs
  @visibleForTesting
  static String? selectTargetApkAsset(List<dynamic> assets, {required bool isDebug}) {
    String? releaseApkUrl;
    String? debugApkUrl;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String? ?? '';
      if (!name.endsWith('.apk') || url.isEmpty) continue;

      if (name.contains('debug')) {
        debugApkUrl ??= url;
      } else {
        releaseApkUrl ??= url;
      }
    }

    return isDebug ? debugApkUrl : releaseApkUrl;
  }

  /// Checks for an available update from the configured source URL
  static Future<UpdateInfo?> checkForUpdate({String? customSourceUrl}) async {
    final rawSource = customSourceUrl ?? DatabaseService.getUpdateSource();
    var sourceUrl = rawSource.trim();
    if (sourceUrl.contains('Srijan/melody') || sourceUrl.contains('YOUR_USERNAME')) {
      sourceUrl = 'https://api.github.com/repos/justabean0/melody/releases/latest';
    }
    if (sourceUrl.isEmpty) return null;

    final currentVer = await getCurrentVersion();

    try {
      final uri = Uri.parse(sourceUrl.trim());
      final res = await _httpClient.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json, application/json',
        'User-Agent': 'Melody-Music-App/1.0',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        debugPrint('Update check failed with status: ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body);

      String remoteVer = '';
      String changelog = '';
      String downloadUrl = '';
      int? apkSize;
      String releaseName = '';

      final isDebug = await isDebugBuild();

      // 1. GitHub Releases API format
      if (data is Map<String, dynamic> && data.containsKey('tag_name')) {
        remoteVer = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
        releaseName = data['name'] as String? ?? 'v$remoteVer';
        changelog = data['body'] as String? ?? 'Bug fixes and performance improvements.';

        final assets = data['assets'] as List<dynamic>? ?? [];
        final targetUrl = selectTargetApkAsset(assets, isDebug: isDebug);

        if (targetUrl == null) {
          debugPrint('Update check: Running ${isDebug ? "Debug" : "Release"} build, but no matching APK found in release assets.');
          return null;
        }

        downloadUrl = targetUrl;
        final matchedAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
              (a) => a?['browser_download_url'] == targetUrl,
              orElse: () => null,
            );
        apkSize = matchedAsset?['size'] as int?;
      }
      // 2. Custom JSON Manifest format
      else if (data is Map<String, dynamic>) {
        remoteVer = (data['version'] as String? ?? '').replaceFirst(RegExp(r'^[vV]'), '');
        releaseName = data['releaseName'] as String? ?? 'v$remoteVer';
        changelog = data['changelog'] as String? ?? 'New version available.';

        if (isDebug) {
          downloadUrl = (data['debugDownloadUrl'] as String? ?? '').isNotEmpty
              ? (data['debugDownloadUrl'] as String)
              : '';
          apkSize = data['debugApkSize'] as int?;
        } else {
          downloadUrl = (data['releaseDownloadUrl'] as String? ?? '').isNotEmpty
              ? (data['releaseDownloadUrl'] as String)
              : (data['downloadUrl'] as String? ?? '');
          apkSize = data['releaseApkSize'] as int? ?? data['apkSize'] as int?;
        }
      }

      if (remoteVer.isEmpty || downloadUrl.isEmpty) {
        debugPrint('Update check: valid version or APK download URL not found in payload.');
        return null;
      }

      final hasUpdate = isNewerVersion(currentVer, remoteVer);

      return UpdateInfo(
        currentVersion: currentVer,
        latestVersion: remoteVer,
        changelog: changelog,
        downloadUrl: downloadUrl,
        apkSize: apkSize,
        hasUpdate: hasUpdate,
        releaseName: releaseName,
      );
    } catch (e) {
      debugPrint('Update check exception: $e');
      return null;
    }
  }

  /// Downloads the APK file to temporary cache and reports download progress
  static Future<File> downloadApk(
    String downloadUrl, {
    required void Function(int receivedBytes, int totalBytes, double percent) onProgress,
  }) async {
    final uri = Uri.parse(downloadUrl);
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'Melody-Music-App/1.0';

    final streamedResponse = await _httpClient.send(request);
    if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
      throw Exception('Failed to download APK: HTTP ${streamedResponse.statusCode}');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;

    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/melody-update.apk');

    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final sink = apkFile.openWrite();

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      final percent = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
      onProgress(receivedBytes, totalBytes, percent.clamp(0.0, 1.0));
    }

    await sink.flush();
    await sink.close();

    return apkFile;
  }

  /// Launches the native Android package installer (or runs installer on Windows)
  static Future<bool> installApk(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('installApk', {
          'filePath': filePath,
        });
        return success ?? false;
      } on PlatformException catch (e) {
        debugPrint('Install error: ${e.message}');
        return false;
      }
    } else if (Platform.isWindows) {
      // On Windows desktop, execute or open the file
      try {
        await Process.start('explorer.exe', [filePath]);
        return true;
      } catch (e) {
        debugPrint('Windows install trigger error: $e');
        return false;
      }
    }
    return false;
  }
}
