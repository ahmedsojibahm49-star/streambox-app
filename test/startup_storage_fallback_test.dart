import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';

/// Startup regression: the documents directory is unusable on the device
/// (the path_provider call throws — seen in the wild as a
/// `ClassNotFoundException` on the documents-dir call, v1.0.1). The Hive
/// fallback chain must retry the support directory and the app must still
/// start and route to onboarding.
///
/// FAILS on the unfixed code: `Hive.initFlutter()` throws, bootstrap has
/// no fallback, and the app lands on the startup error screen instead of
/// onboarding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-fallback');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          // Simulate the broken documents-dir call on the user's phone.
          throw PlatformException(
            code: 'ClassNotFound',
            message: 'simulated documents-dir failure',
          );
        }
        if (call.method == 'getApplicationSupportDirectory') {
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
      'documents-dir failure falls back to the support dir and routes',
      (tester) async {
    // Run the REAL bootstrap (Hive init with fallback + initStorage +
    // date symbols). runAsync is REQUIRED (real file I/O); runStreamBoxApp
    // must stay OUTSIDE runAsync so the splash's session check runs in
    // the FakeAsync zone (see test/startup_test.dart).
    final startup = await tester.runAsync(() => app.bootstrap());
    expect(startup, isNotNull);
    expect(startup!.storageReady, isTrue);

    // The boxes must live in the SUPPORT directory (the fallback), not
    // the broken documents directory.
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
