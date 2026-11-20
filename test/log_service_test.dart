import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/log_service.dart';

void main() {
  group('LogService Diagnostic Logging Tests', () {
    setUp(() {
      LogService.debugOverrideDiagnosticsEnabled = true;
      LogService.init();
      LogService.clear();
    });

    tearDown(() {
      LogService.debugOverrideDiagnosticsEnabled = null;
      LogService.clear();
    });

    test('LogService records and exports logs correctly', () {
      LogService.info('Testing info message', tag: 'Test');
      LogService.warning('Testing warning message', tag: 'Test');
      LogService.error('Testing error message', tag: 'Test', error: 'SampleError');
      LogService.recordBreadcrumb('User clicked play', category: 'playback');

      final logs = LogService.logs;
      expect(logs.length, 3);
      expect(LogService.errorCount, 1);
      expect(LogService.warningCount, 1);
      expect(LogService.breadcrumbs.length, 1);

      final exported = LogService.exportAllLogs(userNotes: 'Crash during seek');
      expect(exported, contains('MELODY DIAGNOSTIC REPORT'));
      expect(exported, contains('Crash during seek'));
      expect(exported, contains('Testing info message'));
      expect(exported, contains('Testing error message'));
      expect(exported, contains('SampleError'));
      expect(exported, contains('BREADCRUMBS'));
      expect(exported, contains('User clicked play'));
    });

    test('LogService respects maximum logs cap', () {
      for (int i = 0; i < LogService.maxLogs + 50; i++) {
        LogService.info('Log message $i', tag: 'Flood');
      }

      expect(LogService.logs.length, LogService.maxLogs);
    });

    test('LogService respects maximum breadcrumbs ring buffer cap', () {
      for (int i = 0; i < LogService.maxBreadcrumbs + 30; i++) {
        LogService.recordBreadcrumb('Step $i', category: 'action');
      }

      expect(LogService.breadcrumbs.length, LogService.maxBreadcrumbs);
      expect(LogService.breadcrumbs.first.message, 'Step 30');
      expect(LogService.breadcrumbs.last.message, 'Step ${LogService.maxBreadcrumbs + 29}');
    });

    test('LogService clear wipes all records and breadcrumbs', () {
      LogService.info('Before clear', tag: 'Test');
      LogService.recordBreadcrumb('Action before clear', category: 'navigation');
      expect(LogService.logs.isNotEmpty, true);
      expect(LogService.breadcrumbs.isNotEmpty, true);

      LogService.clear();
      expect(LogService.logs.isEmpty, true);
      expect(LogService.breadcrumbs.isEmpty, true);
      expect(LogService.errorCount, 0);
    });

    test('LogService no-ops when diagnostics are disabled', () {
      LogService.debugOverrideDiagnosticsEnabled = false;

      LogService.info('Should be ignored', tag: 'Test');
      LogService.error('Should also be ignored', tag: 'Test');
      LogService.recordBreadcrumb('Ignored breadcrumb', category: 'action');

      expect(LogService.logs.isEmpty, true);
      expect(LogService.breadcrumbs.isEmpty, true);
      expect(LogService.errorCount, 0);
    });
  });
}
