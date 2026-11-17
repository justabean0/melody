import 'dart:collection';
import 'package:flutter/foundation.dart';
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

class LogService {
  static const int maxLogs = 600;
  static final DoubleLinkedQueue<LogEntry> _logs = DoubleLinkedQueue<LogEntry>();
  static final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Intercept debugPrint so standard Flutter logs flow into our diagnostic buffer
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.trim().isNotEmpty) {
        log(message, tag: _detectTag(message));
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
      error(
        details.summary.toString(),
        tag: 'FlutterError',
        error: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
      );
    };

    // Capture uncaught platform / async errors
    PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
      error(
        'Uncaught async error: $err',
        tag: 'PlatformError',
        error: err.toString(),
        stackTrace: stack.toString(),
      );
      return false;
    };

    info('LogService initialized. Real-time diagnostic logging active.', tag: 'LogService');
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

  static void _addEntry(LogEntry entry) {
    if (_logs.length >= maxLogs) {
      _logs.removeFirst();
    }
    _logs.addLast(entry);
    logCountNotifier.value++;
  }

  static List<LogEntry> get logs => _logs.toList();

  static int get errorCount => _logs.where((l) => l.level == LogLevel.error).length;
  static int get warningCount => _logs.where((l) => l.level == LogLevel.warning).length;

  static void clear() {
    _logs.clear();
    logCountNotifier.value = 0;
  }

  static String getSystemSummary() {
    final activeProfile = InnerTubeVersionManager.currentProfile;
    return 'Platform: Android/Flutter (${kDebugMode ? "DEBUG" : "RELEASE"} Mode)\n'
        'InnerTube Profile: ${activeProfile.clientName} v${activeProfile.clientVersion}\n'
        'InnerTube Status: ${InnerTubeVersionManager.isOutdatedWarningActive ? "Outdated Warning" : "Healthy"}\n'
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
}
