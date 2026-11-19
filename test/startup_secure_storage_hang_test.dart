import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';

/// Startup regression: secure storage NEVER RESPONDS on a real device
/// (KeyStore deadlock / slow first access). The splash must still route
/// to onboarding via its timeout — it must never hang forever.
///
/// FAILS on the unfixed code: `_route()` awaits the read forever and the
/// app never navigates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-startup');
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
    // Simulate a hung KeyStore: the read never completes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        await Completer<void>().future;
        return null;
      },
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 200,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('secure-storage hang still routes to onboarding (via timeout)',
      (tester) async {
    final startup = await tester.runAsync(() => app.bootstrap());
    app.runStreamBoxApp(startup!);
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);

    // The 8s session-check timeout must fire and route anyway.
    await pumpUntil(tester, find.byType(OnboardingScreen));
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
