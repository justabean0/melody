import 'package:flutter/foundation.dart';

/// Proactive Anti-Bot Shield & Circuit Breaker
///
/// Prevents Google from detecting the user's IP as an automated bot by monitoring
/// burst search and rapid track-skipping frequencies. If burst thresholds are
/// exceeded, it proactively routes 100% of traffic through the safe path
/// (yt.chocolatemoo53.com / Invidious proxy) BEFORE Google's bot checks are triggered.
class AntiBotService {
  static final List<DateTime> _searchTimestamps = [];
  static final List<DateTime> _playTimestamps = [];

  static DateTime? _safeModeUntil;
  static String? _activeReason;

  // Search burst thresholds:
  // > 8 searches in 15 seconds, or > 15 searches in 45 seconds
  static const int maxSearchesShortWindow = 8;
  static const Duration searchShortWindow = Duration(seconds: 15);
  static const int maxSearchesLongWindow = 15;
  static const Duration searchLongWindow = Duration(seconds: 45);

  // Play / track-skip burst thresholds:
  // > 12 plays in 15 seconds, or > 20 plays in 30 seconds
  static const int maxPlaysShortWindow = 12;
  static const Duration playShortWindow = Duration(seconds: 15);
  static const int maxPlaysLongWindow = 20;
  static const Duration playLongWindow = Duration(seconds: 30);

  // Combined activity threshold:
  // > 15 combined searches & plays in 15 seconds
  static const int maxCombinedShortWindow = 15;

  // Cooldown durations:
  static const Duration burstCooldown = Duration(seconds: 30);
  static const Duration botDetectedCooldown = Duration(minutes: 2);

  /// Whether Safe Mode is currently active
  static bool get isSafeModeActive {
    if (_safeModeUntil == null) return false;
    final now = DateTime.now();
    if (now.isAfter(_safeModeUntil!)) {
      debugPrint('🛡️ [Anti-Bot Shield]: Cooldown elapsed. Re-arming hybrid fast path.');
      _safeModeUntil = null;
      _activeReason = null;
      return false;
    }
    return true;
  }

  /// Reason why Safe Mode was activated
  static String? get activeReason => _activeReason;

  /// Time remaining before Safe Mode expires
  static Duration? get remainingCooldown {
    if (_safeModeUntil == null) return null;
    final diff = _safeModeUntil!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Records a search operation and checks if rate thresholds are exceeded
  static void recordSearch({String? query}) {
    final now = DateTime.now();
    _cleanOldTimestamps(_searchTimestamps, searchLongWindow, now);
    _searchTimestamps.add(now);

    final recentShort = _searchTimestamps
        .where((t) => now.difference(t) <= searchShortWindow)
        .length;
    final recentLong = _searchTimestamps.length;

    // Check combined activity in short window
    _cleanOldTimestamps(_playTimestamps, playLongWindow, now);
    final recentPlaysShort = _playTimestamps
        .where((t) => now.difference(t) <= searchShortWindow)
        .length;

    if (recentShort >= maxSearchesShortWindow) {
      _trip(
        burstCooldown,
        'Burst search pattern: $recentShort searches in ${searchShortWindow.inSeconds}s (Threshold: $maxSearchesShortWindow)',
      );
    } else if (recentLong >= maxSearchesLongWindow) {
      _trip(
        burstCooldown,
        'Elevated search volume: $recentLong searches in ${searchLongWindow.inSeconds}s (Threshold: $maxSearchesLongWindow)',
      );
    } else if ((recentShort + recentPlaysShort) >= maxCombinedShortWindow) {
      _trip(
        burstCooldown,
        'Combined burst activity: ${recentShort + recentPlaysShort} actions in ${searchShortWindow.inSeconds}s',
      );
    }
  }

  /// Records a track play / skip operation and checks if rate thresholds are exceeded
  static void recordPlay({String? videoId}) {
    final now = DateTime.now();
    _cleanOldTimestamps(_playTimestamps, playLongWindow, now);
    _playTimestamps.add(now);

    final recentShort = _playTimestamps
        .where((t) => now.difference(t) <= playShortWindow)
        .length;
    final recentLong = _playTimestamps.length;

    // Check combined activity in short window
    _cleanOldTimestamps(_searchTimestamps, searchLongWindow, now);
    final recentSearchesShort = _searchTimestamps
        .where((t) => now.difference(t) <= playShortWindow)
        .length;

    if (recentShort >= maxPlaysShortWindow) {
      _trip(
        burstCooldown,
        'Rapid track skipping: $recentShort plays in ${playShortWindow.inSeconds}s (Threshold: $maxPlaysShortWindow)',
      );
    } else if (recentLong >= maxPlaysLongWindow) {
      _trip(
        burstCooldown,
        'High play frequency: $recentLong plays in ${playLongWindow.inSeconds}s (Threshold: $maxPlaysLongWindow)',
      );
    } else if ((recentShort + recentSearchesShort) >= maxCombinedShortWindow) {
      _trip(
        burstCooldown,
        'Combined burst activity: ${recentShort + recentSearchesShort} actions in ${playShortWindow.inSeconds}s',
      );
    }
  }

  /// Reactively trips Safe Mode when a remote endpoint flags LOGIN_REQUIRED or 429
  static void tripOnBotDetected(String reason) {
    _trip(botDetectedCooldown, 'Upstream bot check encountered ($reason)');
  }

  /// Internal helper to activate or extend Safe Mode
  static void _trip(Duration duration, String reason) {
    final target = DateTime.now().add(duration);
    if (_safeModeUntil == null || target.isAfter(_safeModeUntil!)) {
      _safeModeUntil = target;
      _activeReason = reason;
      debugPrint(
        '🛡️ [Anti-Bot Shield ACTIVATED]: $reason.\n'
        '   Proactively diverting 100% traffic to Safe Path until $_safeModeUntil',
      );
    }
  }

  /// Removes timestamps older than the evaluation window
  static void _cleanOldTimestamps(List<DateTime> list, Duration maxAge, DateTime now) {
    list.removeWhere((t) => now.difference(t) > maxAge);
  }

  /// Resets circuit breaker state (for testing or manual cache clearing)
  static void reset() {
    _searchTimestamps.clear();
    _playTimestamps.clear();
    _safeModeUntil = null;
    _activeReason = null;
  }
}
