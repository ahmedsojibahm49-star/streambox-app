import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';
import 'package:streambox/services/storage.dart';

/// Startup regression: the direct Android app-data paths are unusable
/// (unwritable) but path_provider works — Hive init must fall through to
/// the path_provider chain (documents dir) instead of failing.
///
/// FAILS if the direct-path attempt throws out of [initHiveWithFallback]
/// instead of falling through: bootstrap would report a storage error
/// and the app would land on the startup error screen.
///
/// The seam points at a path whose parent is a regular FILE, so
/// `Directory.create(recursive: true)` deterministically throws even
/// when the test runs as root (permission-based unwritability would not).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-direct-fb');
    // A file where a directory should be: anything under it is
    // un-creatable, deterministically, even as root.
    await File('${tempDir.path}/blocker').writeAsString('not a directory');
    // The test seam: point the direct candidates at the unwritable path.
    debugDirectHiveCandidates = ['${tempDir.path}/blocker/app_flutter'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
    // flutter_secure_storage: fresh device — every read returns null.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  tearDownAll(() async {
    debugDirectHiveCandidates = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Pump frames until [finder] matches (or [maxPumps] is reached).
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 60,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  testWidgets(
      'unwritable direct path falls through to the path_provider documents dir',
      (tester) async {
    // Run the REAL bootstrap (Hive init with direct path + initStorage +
    // date symbols). runAsync is REQUIRED (real file I/O); runStreamBoxApp
    // must stay OUTSIDE runAsync so the splash's session check runs in
    // the FakeAsync zone (see test/startup_test.dart).
    final startup = await tester.runAsync(() => app.bootstrap());
    expect(startup, isNotNull);
    expect(startup!.storageReady, isTrue);

    // The boxes must live in the DOCUMENTS directory (the path_provider
    // fallback), not under the unwritable direct path.
    expect(
      File('${tempDir.path}/settings.hive').existsSync(),
      isTrue,
    );

    app.runStreamBoxApp(startup);
    await tester.pump();

    // First frame: the splash must be visible (not the error screen).
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('StreamBox'), findsOneWidget);

    // Splash checks the session (no account, onboarding unseen) and must
    // route to /onboarding.
    await pumpUntil(tester, find.byType(OnboardingScreen));
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
