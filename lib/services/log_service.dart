import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/build_flags.dart';
import 'anti_bot_service.dart';
import 'innertube_version_manager.dart';

enum LogLevel { info, warning, error, debug }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final prefix = switch (level) {
      LogLevel.error => '🛑 [ERROR]',
      LogLevel.warning => '⚠️ [WARN]',
      LogLevel.info => 'ℹ️ [INFO]',
      LogLevel.debug => '🐛 [DEBUG]',
    };
    final errStr = error != null ? ' | Error: $error' : '';
    final stStr = stackTrace != null ? '\nStackTrace: $stackTrace' : '';
    return '[$formattedTime] $prefix [$tag] $message$errStr$stStr';
  }
}

class Breadcrumb {
  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, dynamic>? data;

  Breadcrumb({
    required this.timestamp,
    required this.category,
    required this.message,
    this.data,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final dataStr = (data != null && data!.isNotEmpty) ? ' | data: $data' : '';
    return '[$formattedTime] [$category] $message$dataStr';
  }
}

class DiagnosticNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (!LogService.isDiagnosticsEnabled) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    final prevName = previousRoute?.settings.name ?? previousRoute?.runtimeType.toString();
    LogService.recordBreadcrumb(
      'Navigated to $name${prevName != null ? " from $prevName" : ""}',
      category: 'navigation',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (!LogService.isDiagnosticsEnabled) return;
    final name = route.settings.name ?? route.runtimeType.toString();
    final prevName = previousRoute?.settings.name ?? previousRoute?.runtimeType.toString();
    LogService.recordBreadcrumb(
      'Popped $name${prevName != null ? ", returned to $prevName" : ""}',
      category: 'navigation',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (!LogService.isDiagnosticsEnabled) return;
    final newName = newRoute?.settings.name ?? newRoute?.runtimeType.toString();
    final oldName = oldRoute?.settings.name ?? oldRoute?.runtimeType.toString();
    LogService.recordBreadcrumb(
      'Replaced $oldName with $newName',
      category: 'navigation',
    );
  }
}

class LogService {
  static const int maxLogs = 600;
  static const int maxBreadcrumbs = 100;

  static final DoubleLinkedQueue<LogEntry> _logs = DoubleLinkedQueue<LogEntry>();
  static final DoubleLinkedQueue<Breadcrumb> _breadcrumbs = DoubleLinkedQueue<Breadcrumb>();
  static final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);
  static bool _initialized = false;
  static bool _isLogging = false;

  @visibleForTesting
  static bool? debugOverrideDiagnosticsEnabled;

  static bool get isDiagnosticsEnabled =>
      debugOverrideDiagnosticsEnabled ?? kIsDiagnosticsEnabled;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Intercept debugPrint so standard Flutter logs flow into our diagnostic buffer
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (_isLogging) {
        originalDebugPrint(message, wrapWidth: wrapWidth);
        return;
      }
      if (isDiagnosticsEnabled && message != null && message.trim().isNotEmpty) {
        _isLogging = true;
        try {
          log(message, tag: _detectTag(message));
        } finally {
          _isLogging = false;
        }
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    // Capture uncaught Flutter framework widget errors
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (originalOnError != null) {
        originalOnError(details);
      } else {
        FlutterError.presentError(details);
      }
      if (isDiagnosticsEnabled) {
        recordBreadcrumb(
          'Flutter error: ${details.summary}',
          category: 'error',
        );
        error(
          details.summary.toString(),
          tag: 'FlutterError',
          error: details.exceptionAsString(),
          stackTrace: details.stack?.toString(),
        );
      }
    };

    // Capture uncaught platform / async errors
    PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
      if (isDiagnosticsEnabled) {
        recordBreadcrumb(
          'Platform async error: $err',
          category: 'error',
        );
        error(
          'Uncaught async error: $err',
          tag: 'PlatformError',
          error: err.toString(),
          stackTrace: stack.toString(),
        );
      }
      return false;
    };

    if (isDiagnosticsEnabled) {
      info('LogService initialized. Real-time diagnostic logging active.', tag: 'LogService');
    }
  }

  static String _detectTag(String msg) {
    if (msg.contains('AudioService')) return 'AudioService';
    if (msg.contains('AudioCacheService')) return 'AudioCache';
    if (msg.contains('StreamResolverService') || msg.contains('StreamResolver')) return 'StreamResolver';
    if (msg.contains('InnerTubeService') || msg.contains('InnerTube')) return 'InnerTube';
    if (msg.contains('Anti-Bot')) return 'AntiBot';
    if (msg.contains('Search Pre-Warming') || msg.contains('SearchProvider')) return 'Search';
    if (msg.contains('DatabaseService')) return 'Database';
    return 'App';
  }

  static void log(String message, {String tag = 'App', LogLevel level = LogLevel.info}) {
    if (!isDiagnosticsEnabled) return;
    LogLevel detectedLevel = level;
    final lower = message.toLowerCase();
    if (message.contains('🛑') || lower.contains('error') || lower.contains('failed') || lower.contains('exception')) {
      detectedLevel = LogLevel.error;
    } else if (message.contains('⚠️') || lower.contains('warning') || lower.contains('warn')) {
      detectedLevel = LogLevel.warning;
    }

    _addEntry(LogEntry(
      timestamp: DateTime.now(),
      level: detectedLevel,
      tag: tag,
      message: message,
    ));
  }

  static void info(String message, {String tag = 'App'}) =>
      _addEntry(LogEntry(timestamp: DateTime.now(), level: LogLevel.info, tag: tag, message: message));

  static void warning(String message, {String tag = 'App'}) =>
      _addEntry(LogEntry(timestamp: DateTime.now(), level: LogLevel.warning, tag: tag, message: message));

  static void error(String message, {String tag = 'App', Object? error, String? stackTrace}) =>
      _addEntry(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        tag: tag,
        message: message,
        error: error?.toString(),
        stackTrace: stackTrace,
      ));

  static void recordBreadcrumb(
    String message, {
    String category = 'action',
    Map<String, dynamic>? data,
  }) {
    if (!isDiagnosticsEnabled) return;
    if (_breadcrumbs.length >= maxBreadcrumbs) {
      _breadcrumbs.removeFirst();
    }
    _breadcrumbs.addLast(Breadcrumb(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      data: data,
    ));
    developer.log('[Breadcrumb] [$category] $message', name: 'MelodyDiag');
  }

  static void _addEntry(LogEntry entry) {
    if (!isDiagnosticsEnabled) return;
    if (_logs.length >= maxLogs) {
      _logs.removeFirst();
    }
    _logs.addLast(entry);
    logCountNotifier.value++;
    developer.log(entry.toString(), name: entry.tag);
    if (entry.tag == 'Feed') {
      // Also emit via print() so adb logcat captures [Feed] under the flutter tag in --release builds.
      // ignore: avoid_print
      print('[Feed] ${entry.message}');
    }
  }

  static List<LogEntry> get logs => _logs.toList();
  static List<Breadcrumb> get breadcrumbs => _breadcrumbs.toList();

  static int get errorCount => _logs.where((l) => l.level == LogLevel.error).length;
  static int get warningCount => _logs.where((l) => l.level == LogLevel.warning).length;

  static void clear() {
    _logs.clear();
    _breadcrumbs.clear();
    logCountNotifier.value = 0;
  }

  static String getSystemSummary() {
    final activeProfile = InnerTubeVersionManager.currentProfile;
    final modeStr = kEnableDiagnostics
        ? "RELEASE (Diagnostics Enabled)"
        : (kDebugMode ? "DEBUG" : "RELEASE (Standard)");
    final antiBotStatus = AntiBotService.isSafeModeActive
        ? "ACTIVE (${AntiBotService.activeReason ?? 'Cooldown'})"
        : "Inactive";

    return 'Platform: Android/Flutter ($modeStr)\n'
        'InnerTube Profile: ${activeProfile.clientName} v${activeProfile.clientVersion}\n'
        'InnerTube Status: ${InnerTubeVersionManager.isOutdatedWarningActive ? "Outdated Warning" : "Healthy"}\n'
        'Anti-Bot Shield: $antiBotStatus\n'
        'Breadcrumbs: ${_breadcrumbs.length} recorded\n'
        'Total Log Count: ${_logs.length} (Errors: $errorCount, Warnings: $warningCount)';
  }

  static String exportAllLogs({String? userNotes}) {
    final sb = StringBuffer();
    sb.writeln('========================================');
    sb.writeln('       MELODY DIAGNOSTIC REPORT         ');
    sb.writeln('========================================');
    sb.writeln('Generated: ${DateTime.now().toIso8601String()}');
    sb.writeln(getSystemSummary());
    if (userNotes != null && userNotes.trim().isNotEmpty) {
      sb.writeln('\nUser Notes: $userNotes');
    }
    sb.writeln('\n------------- BREADCRUMBS --------------');
    if (_breadcrumbs.isEmpty) {
      sb.writeln('No breadcrumbs recorded.');
    } else {
      for (final bc in _breadcrumbs) {
        sb.writeln(bc.toString());
      }
    }
    sb.writeln('\n---------------- LOGS ------------------');
    if (_logs.isEmpty) {
      sb.writeln('No logs recorded.');
    } else {
      for (final entry in _logs) {
        sb.writeln(entry.toString());
      }
    }
    sb.writeln('========================================');
    return sb.toString();
  }

  static const _platform = MethodChannel('com.melody.music/diagnostics');

  /// Opens the native Android share sheet with a generated .txt crash log
  /// allowing sharing via Google Drive, Email, WhatsApp, QuickShare, etc.
  static Future<bool> shareLogFile({String? userNotes}) async {
    if (!isDiagnosticsEnabled) return false;
    try {
      final content = exportAllLogs(userNotes: userNotes);
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final file = File('${tempDir.path}/melody_crash_log_$ts.txt');
      await file.writeAsString(content);

      if (Platform.isAndroid) {
        await _platform.invokeMethod('shareLogFile', {
          'filePath': file.path,
          'title': 'Melody Crash Log ($ts)',
        });
        return true;
      }
      return false;
    } catch (e) {
      error('Failed to share log file: $e', tag: 'LogService');
      return false;
    }
  }

  /// Saves the crash log directly to the device's public Downloads directory
  static Future<String?> saveLogToDownloads({String? userNotes}) async {
    if (!isDiagnosticsEnabled) return null;
    try {
      final content = exportAllLogs(userNotes: userNotes);
      final now = DateTime.now();
      final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'melody_crash_log_$ts.txt';

      if (Platform.isAndroid) {
        final result = await _platform.invokeMethod<String>('saveToDownloads', {
          'content': content,
          'fileName': fileName,
        });
        return result ?? 'Downloads/$fileName';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(content);
        return file.path;
      }
    } catch (e) {
      error('Failed to save log to Downloads: $e', tag: 'LogService');
      return null;
    }
  }

  /// Uploads the diagnostic log to an instant web paste link (e.g. paste.rs / dpaste.org)
  /// so the user can download or share the raw text file from any browser on PC or phone.
  static Future<String?> uploadLogToCloud({String? userNotes}) async {
    if (!isDiagnosticsEnabled) return null;
    final content = exportAllLogs(userNotes: userNotes);

    // 1. Try paste.rs (instant raw text file)
    try {
      final res = await http.post(
        Uri.parse('https://paste.rs'),
        headers: {'Content-Type': 'text/plain'},
        body: content,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final url = res.body.trim();
        if (url.startsWith('http')) return url;
      }
    } catch (_) {}

    // 2. Fallback to dpaste.org
    try {
      final res = await http.post(
        Uri.parse('https://dpaste.org/api/'),
        body: {
          'content': content,
          'format': 'url',
          'expiry_days': '14',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final url = res.body.trim();
        if (url.startsWith('http')) {
          // Add /raw for direct download
          return url.endsWith('/raw') ? url : '$url/raw';
        }
      }
    } catch (_) {}

    return null;
  }
}
