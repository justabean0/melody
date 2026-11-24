import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:melody/services/update_service.dart';
import 'package:melody/ui/components/update_dialog.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUrlLauncher mockLauncher;

  setUp(() {
    mockLauncher = MockUrlLauncher();
    UrlLauncherPlatform.instance = mockLauncher;
  });

  const testInfo = UpdateInfo(
    currentVersion: '1.1.10',
    latestVersion: '1.1.11',
    changelog: 'Fixed Google Play Protect warnings and streamlined updates.',
    downloadUrl: 'https://github.com/justabean0/melody/releases/download/v1.1.11/app-release.apk',
    apkSize: 31457280, // ~30 MB
    hasUpdate: true,
    releaseName: 'v1.1.11',
  );

  group('UpdateDialog Widget & Browser Download Trigger Tests', () {
    testWidgets('Renders update details, changelog, and browser-opening copy', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpdateDialog(updateInfo: testInfo),
          ),
        ),
      );

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('v1.1.10 ➔ v1.1.11'), findsOneWidget);
      expect(find.text("What's New:"), findsOneWidget);
      expect(find.text('Fixed Google Play Protect warnings and streamlined updates.'), findsOneWidget);
      expect(find.text('Size: 30.0 MB'), findsOneWidget);
      expect(find.text('Opens download in external browser'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Download Update'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_browser_rounded), findsNWidgets(2));
    });

    testWidgets('Tapping Later dismisses dialog', (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await UpdateDialog.show(context, testInfo);
                  popped = true;
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(UpdateDialog), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.byType(UpdateDialog), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets('Tapping Download Update triggers external browser launch with downloadUrl', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UpdateDialog.show(context, testInfo),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download Update'));
      await tester.pumpAndSettle();

      expect(mockLauncher.launchedUrl, equals(testInfo.downloadUrl));
      expect(mockLauncher.launchMode, equals(PreferredLaunchMode.externalApplication));
      // Upon successful launch, dialog pops
      expect(find.byType(UpdateDialog), findsNothing);
    });

    testWidgets('Launch failure shows SnackBar and error message without crashing', (tester) async {
      mockLauncher.returnSuccess = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UpdateDialog.show(context, testInfo),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download Update'));
      await tester.pumpAndSettle();

      expect(mockLauncher.launchedUrl, equals(testInfo.downloadUrl));
      // Dialog remains open showing error state
      expect(find.byType(UpdateDialog), findsOneWidget);
      expect(find.text('Could not open browser to download update.'), findsAtLeastNWidgets(1));
    });
  });
}
