import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/main.dart' as app;
import 'package:streambox/screens/auth/splash_screen.dart';
import 'package:streambox/screens/onboarding_screen.dart';

/// Startup regression: secure storage THROWS on a real device (broken
/// Android KeyStore / corrupted EncryptedSharedPreferences is a known
/// Android failure mode). The splash must still route to onboarding —
/// it must never strand the user on the splash (or a white screen).
///
/// FAILS on the unfixed code: the throw escapes `_route()` unhandled and
/// the app never navigates.
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
    // Simulate a broken KeyStore: every secure-storage call throws.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        throw PlatformException(
          code: 'KeyStore',
          message: 'simulated KeyStore failure',
        );
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
    int maxPumps = 60,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('secure-storage failure still routes to onboarding',
      (tester) async {
    final startup = await tester.runAsync(() => app.bootstrap());
    app.runStreamBoxApp(startup!);
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);

    await pumpUntil(tester, find.byType(OnboardingScreen));
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
