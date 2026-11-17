import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/log_service.dart';

void main() {
  group('LogService Diagnostic Logging Tests', () {
    setUp(() {
      LogService.init();
      LogService.clear();
    });

    test('LogService records and exports logs correctly', () {
      LogService.info('Testing info message', tag: 'Test');
      LogService.warning('Testing warning message', tag: 'Test');
      LogService.error('Testing error message', tag: 'Test', error: 'SampleError');

      final logs = LogService.logs;
      expect(logs.length, 3);
      expect(LogService.errorCount, 1);
      expect(LogService.warningCount, 1);

      final exported = LogService.exportAllLogs(userNotes: 'Crash during seek');
      expect(exported, contains('MELODY DIAGNOSTIC REPORT'));
      expect(exported, contains('Crash during seek'));
      expect(exported, contains('Testing info message'));
      expect(exported, contains('Testing error message'));
      expect(exported, contains('SampleError'));
    });

    test('LogService respects maximum logs cap', () {
      for (int i = 0; i < LogService.maxLogs + 50; i++) {
        LogService.info('Log message $i', tag: 'Flood');
      }

      expect(LogService.logs.length, LogService.maxLogs);
    });

    test('LogService clear wipes all records', () {
      LogService.info('Before clear', tag: 'Test');
      expect(LogService.logs.isNotEmpty, true);

      LogService.clear();
      expect(LogService.logs.isEmpty, true);
      expect(LogService.errorCount, 0);
    });
  });
}
