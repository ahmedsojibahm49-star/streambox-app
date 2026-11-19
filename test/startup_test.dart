import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';

/// Startup regression tests (white-screen-on-launch bug, Nov 19).
///
/// These pump the REAL app through the REAL `bootstrap()` (Hive init +
/// box opening + Bangla date symbols) and the REAL `runStreamBoxApp()` —
/// the same two calls `main()` makes — with only the platform channels
/// mocked (path_provider -> temp dir, secure storage -> empty). If
/// anything in startup throws or hangs, the splash never renders or the
/// app never routes, and these tests fail.
///
/// Two harness facts matter here:
/// - `bootstrap()` does REAL file I/O (Hive opens box files), so it must
///   run inside `tester.runAsync()` — the `testWidgets` FakeAsync zone
///   never completes real I/O otherwise (the test hangs).
/// - But `runStreamBoxApp()` must run OUTSIDE runAsync, in the test's
///   FakeAsync zone: runApp triggers the warm-up frame, which runs the
///   splash's post-frame session check — if that runs in runAsync's real
///   zone, its timeouts use wall time instead of fake time.
/// - The splash shows a CircularProgressIndicator (an endless animation),
///   so `pumpAndSettle` would time out — we pump manually in a loop
///   until the expected screen appears.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-startup');
    // path_provider: Hive.initFlutter() asks for the documents dir.
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

  testWidgets('real bootstrap renders the splash, then routes to onboarding',
      (tester) async {
    // Run the REAL bootstrap (Hive init + initStorage + date symbols),
    // then attach the REAL app widget. Any throw before runApp is the
    // white screen on a real device. runAsync is REQUIRED for bootstrap
    // (real file I/O); runStreamBoxApp must stay OUTSIDE runAsync so the
    // splash's session check runs in the FakeAsync zone (see header).
    final startup = await tester.runAsync(() => app.bootstrap());
    app.runStreamBoxApp(startup!);
    await tester.pump();

    // First frame: the splash must be visible (not a blank white screen).
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('StreamBox'), findsOneWidget);

    // Splash checks the session (no account, onboarding unseen) and must
    // route to /onboarding — it must not hang on the splash forever.
    await pumpUntil(tester, find.byType(OnboardingScreen));
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
