import 'package:flutter_test/flutter_test.dart';
import 'package:melody/services/innertube_version_manager.dart';

void main() {
  setUp(() {
    InnerTubeVersionManager.reset();
  });

  group('InnerTubeVersionManager Tests', () {
    test('Initial state provides modern active profile without outdated warnings', () {
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isFalse);
      expect(InnerTubeVersionManager.outdatedReason, isNull);
      expect(InnerTubeVersionManager.currentProfile.clientName, equals('ANDROID_MUSIC'));
      expect(InnerTubeVersionManager.currentProfile.clientVersion, equals('7.02.51'));
    });

    test('HTTP 400 detects outdated client version and triggers alert', () {
      final isOutdated = InnerTubeVersionManager.inspectResponseForOutdatedClient(
        statusCode: 400,
        rawBody: 'Bad Request: INVALID_CLIENT_VERSION',
      );

      expect(isOutdated, isTrue);
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isTrue);
      expect(InnerTubeVersionManager.outdatedReason, contains('HTTP 400 Bad Request'));
      // Verifies rotation to next fallback profile
      expect(InnerTubeVersionManager.currentProfile.clientVersion, equals('6.42.52'));
    });

    test('PlayabilityStatus with deprecation reason triggers alert and rotates profile', () {
      final isOutdated = InnerTubeVersionManager.inspectResponseForOutdatedClient(
        statusCode: 200,
        responseBody: {
          'playabilityStatus': {
            'status': 'ERROR',
            'reason': 'This client version is no longer supported. Please update your app.',
          }
        },
      );

      expect(isOutdated, isTrue);
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isTrue);
      expect(InnerTubeVersionManager.outdatedReason, contains('no longer supported'));
      expect(InnerTubeVersionManager.isProfileDeprecated(
        const InnerTubeClientProfile(
          clientName: 'ANDROID_MUSIC',
          clientVersion: '7.02.51',
          userAgent: '',
        ),
      ), isTrue);
    });

    test('LOGIN_REQUIRED response triggers outdated alert', () {
      final isOutdated = InnerTubeVersionManager.inspectResponseForOutdatedClient(
        statusCode: 200,
        responseBody: {
          'playabilityStatus': {
            'status': 'LOGIN_REQUIRED',
          }
        },
      );

      expect(isOutdated, isTrue);
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isTrue);
      expect(InnerTubeVersionManager.outdatedReason, contains('LOGIN_REQUIRED'));
    });

    test('Dismiss warning clears warning flag while preserving rotation state', () {
      InnerTubeVersionManager.inspectResponseForOutdatedClient(statusCode: 400);
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isTrue);

      InnerTubeVersionManager.dismissWarning();
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isFalse);
    });

    test('Reset clears all deprecations and re-activates primary profile', () {
      InnerTubeVersionManager.inspectResponseForOutdatedClient(statusCode: 400);
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isTrue);

      InnerTubeVersionManager.reset();
      expect(InnerTubeVersionManager.isOutdatedWarningActive, isFalse);
      expect(InnerTubeVersionManager.currentProfile.clientVersion, equals('7.02.51'));
    });
  });
}
