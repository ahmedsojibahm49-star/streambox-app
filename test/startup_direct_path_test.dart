import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';
import 'package:streambox/services/storage.dart';

/// Startup regression: EVERY path_provider call fails on the device
/// (v1.0.2: `ClassNotFoundException` for `android.content.Context` on the
/// documents, support, temp AND cache calls — path_provider_android 2.3.1
/// resolves all four through the same JNI `Context` binding, so the old
/// fallback chain was useless). Hive init must NOT depend on the platform
/// channel at all: the pure-Dart direct Android app-data path is tried
/// first, and the app must still start and route to onboarding.
///
/// FAILS on the unfixed code: every path_provider attempt throws,
/// bootstrap has no direct path, and the app lands on the startup error
/// screen instead of onboarding.
///
/// The direct candidates are injected through the
/// [debugDirectHiveCandidates] test seam (temp dirs) — tests run on a
/// Linux host where `defaultTargetPlatform` is Android, so the real
/// `/data/...` candidates must never be used here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory directDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-direct');
    // A nested path, so the test also proves recursive creation works.
    directDir = Directory('${tempDir.path}/direct/app_flutter');
    // The test seam: point the direct candidates at the temp dir.
    debugDirectHiveCandidates = [directDir.path];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async {
        // Simulate the broken path_provider layer: EVERY call throws.
        throw PlatformException(
          code: 'ClassNotFound',
          message: 'simulated path_provider failure (${call.method})',
        );
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
      'all path_provider calls failing still starts via the direct path',
      (tester) async {
    // Run the REAL bootstrap (Hive init with direct path + initStorage +
    // date symbols). runAsync is REQUIRED (real file I/O); runStreamBoxApp
    // must stay OUTSIDE runAsync so the splash's session check runs in
    // the FakeAsync zone (see test/startup_test.dart).
    final startup = await tester.runAsync(() => app.bootstrap());
    expect(startup, isNotNull);
    expect(startup!.storageReady, isTrue);

    // The boxes must live in the DIRECT path — path_provider was never
    // consulted (every one of its calls throws).
    expect(
      File('${directDir.path}/settings.hive').existsSync(),
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
