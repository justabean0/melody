import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'database_service.dart';

/// InnerTube Client Profile configuration
class InnerTubeClientProfile {
  final String clientName;
  final String clientVersion;
  final String userAgent;

  const InnerTubeClientProfile({
    required this.clientName,
    required this.clientVersion,
    required this.userAgent,
  });

  String get key => '${clientName}_$clientVersion';

  Map<String, dynamic> toContextClient() => {
        'clientName': clientName,
        'clientVersion': clientVersion,
        'hl': 'en',
        'gl': 'US',
      };
}

/// InnerTube Client Version Manager
///
/// Monitors client version strings used for InnerTube API calls.
/// YouTube periodically sunsets/deprecates old client versions.
/// This manager:
/// 1. Detects when YouTube rejects or flags a client version string as outdated.
/// 2. Alerts the user & logs diagnostic status ("so that we know about it").
/// 3. Automatically rotates through healthy fallback client profiles.
/// 4. Provides remote sync capability so client version strings can be updated OTA.
class InnerTubeVersionManager {
  static final http.Client _httpClient = http.Client();

  /// Default pool of client profiles (ordered by modern stability)
  static final List<InnerTubeClientProfile> _profiles = [
    const InnerTubeClientProfile(
      clientName: 'VISIONOS',
      clientVersion: '0.1',
      userAgent: 'Mozilla/5.0 (VisionOS; Mobile) AppleWebKit/605.1.15',
    ),
    const InnerTubeClientProfile(
      clientName: 'ANDROID_VR',
      clientVersion: '1.56.21',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US) gzip',
    ),
    const InnerTubeClientProfile(
      clientName: 'WEB_REMIX',
      clientVersion: '1.20241001.01.00',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
    ),
    const InnerTubeClientProfile(
      clientName: 'ANDROID_MUSIC',
      clientVersion: '7.02.51',
      userAgent:
          'com.google.android.apps.youtube.music/7.02.51 (Linux; U; Android 14; en_US) gzip',
    ),
  ];

  static int _currentIndex = 0;
  static final Set<String> _deprecatedProfiles = {};
  static bool _isOutdatedWarningActive = false;
  static String? _outdatedReason;
  static DateTime? _lastOutdatedDetectedAt;

  /// ValueNotifier for UI listeners (Home Screen banner, Settings badges)
  static final ValueNotifier<bool> onOutdatedStatusChanged =
      ValueNotifier<bool>(false);

  static bool get isOutdatedWarningActive => _isOutdatedWarningActive;
  static String? get outdatedReason => _outdatedReason;
  static DateTime? get lastOutdatedDetectedAt => _lastOutdatedDetectedAt;

  /// Current active client profile
  static InnerTubeClientProfile get currentProfile {
    // Find first non-deprecated profile
    for (int i = 0; i < _profiles.length; i++) {
      final index = (_currentIndex + i) % _profiles.length;
      final p = _profiles[index];
      if (!_deprecatedProfiles.contains(p.key)) {
        return p;
      }
    }
    // If all deprecated, return first profile while safe path takes over
    return _profiles.first;
  }

  /// List of all profiles and their status
  static List<InnerTubeClientProfile> get allProfiles =>
      List.unmodifiable(_profiles);

  static bool isProfileDeprecated(InnerTubeClientProfile profile) =>
      _deprecatedProfiles.contains(profile.key);

  /// Analyzes an InnerTube response to detect outdated client version strings
  static bool inspectResponseForOutdatedClient({
    required int statusCode,
    Map<String, dynamic>? responseBody,
    String? rawBody,
  }) {
    if (statusCode == 400) {
      _reportOutdated('HTTP 400 Bad Request (Invalid or deprecated client version)');
      return true;
    }

    if (responseBody != null) {
      final playability = responseBody['playabilityStatus']?['status'] as String?;
      final reason =
          responseBody['playabilityStatus']?['reason'] as String? ?? '';
      final lowerReason = reason.toLowerCase();

      if (lowerReason.contains('version') ||
          lowerReason.contains('supported') ||
          lowerReason.contains('update your app') ||
          lowerReason.contains('deprecated')) {
        _reportOutdated('YouTube deprecation message: "$reason"');
        return true;
      }

      // YouTube flags outdated/bot-checked client versions with LOGIN_REQUIRED
      if (playability == 'LOGIN_REQUIRED') {
        _reportOutdated('Client rejected with LOGIN_REQUIRED (version may be deprecated)');
        return true;
      }
    }

    if (rawBody != null) {
      final lower = rawBody.toLowerCase();
      if (lower.contains('invalid_client_version') ||
          lower.contains('client_version_deprecated')) {
        _reportOutdated('YouTube rejected client version string');
        return true;
      }
    }

    return false;
  }

  /// Triggers outdated notification and rotates to next available client profile
  static void _reportOutdated(String reason) {
    final active = currentProfile;
    _deprecatedProfiles.add(active.key);
    _isOutdatedWarningActive = true;
    _outdatedReason = reason;
    _lastOutdatedDetectedAt = DateTime.now();

    debugPrint(
      '⚠️ [InnerTubeVersionManager] OUTDATED CLIENT DETECTED!\n'
      '   Profile: ${active.clientName} v${active.clientVersion}\n'
      '   Reason: $reason\n'
      '   Rotating to fallback profile...',
    );

    // Advance to next profile
    _currentIndex = (_currentIndex + 1) % _profiles.length;
    onOutdatedStatusChanged.value = true;
  }

  /// Manually dismiss the warning banner for the current session
  static void dismissWarning() {
    _isOutdatedWarningActive = false;
    onOutdatedStatusChanged.value = false;
  }

  /// Resets client version status (re-tests all profiles)
  static void reset() {
    _deprecatedProfiles.clear();
    _isOutdatedWarningActive = false;
    _outdatedReason = null;
    _lastOutdatedDetectedAt = null;
    _currentIndex = 0;
    onOutdatedStatusChanged.value = false;
    debugPrint('InnerTubeVersionManager: Reset to default client profiles.');
  }

  /// Attempts to fetch modern InnerTube client strings from remote update source
  static Future<bool> syncLatestClientVersions() async {
    try {
      final updateSource = DatabaseService.getUpdateSource();
      // If custom source or remote config endpoint exists, query it
      final uri = Uri.parse(updateSource);
      final res = await _httpClient.get(uri).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data.containsKey('innertube_client_version')) {
          final newVer = data['innertube_client_version'] as String;
          final newClient = data['innertube_client_name'] as String? ?? 'ANDROID_MUSIC';
          final newUA = data['innertube_user_agent'] as String? ??
              'com.google.android.apps.youtube.music/$newVer (Linux; U; Android 14; en_US) gzip';

          final newProfile = InnerTubeClientProfile(
            clientName: newClient,
            clientVersion: newVer,
            userAgent: newUA,
          );

          _profiles.insert(0, newProfile);
          _currentIndex = 0;
          _deprecatedProfiles.remove(newProfile.key);
          _isOutdatedWarningActive = false;
          onOutdatedStatusChanged.value = false;
          debugPrint('InnerTubeVersionManager: Synced new client string $newClient $newVer');
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}
