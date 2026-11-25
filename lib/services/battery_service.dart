import 'dart:io';
import 'package:flutter/services.dart';

class BatteryService {
  static const MethodChannel _channel = MethodChannel('com.melody.music/battery');

  static bool get _isSupportedPlatform =>
      Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST');

  /// Checks whether battery optimizations are disabled (unrestricted) for the app.
  /// Always returns true on non-Android platforms.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isSupportedPlatform) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Launches the system battery optimization dialog or settings page.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Opens the system app details / battery optimization settings page.
  static Future<void> openBatteryOptimizationSettings() async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } catch (_) {}
  }

  /// Syncs the background playback preference to native SharedPreferences.
  static Future<void> syncBackgroundPlayback(bool enabled) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod('setBackgroundPlaybackEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// Retrieves the current background playback preference from native SharedPreferences.
  static Future<bool> getNativeBackgroundPlaybackEnabled() async {
    if (!_isSupportedPlatform) return false;
    try {
      final res = await _channel.invokeMethod<bool>('getBackgroundPlaybackEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
