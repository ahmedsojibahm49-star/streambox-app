import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/services/auth_service.dart';
import 'package:streambox/services/credential_storage.dart';
import 'package:streambox/services/storage.dart';
import 'package:streambox/utils/code_generator.dart';

/// Auth regression: flutter_secure_storage THROWS on the device (broken
/// KeyStore — the same broken-platform-layer family as the v1.0.2 Hive
/// failure). Sign-up, login, session and onboarding must still work via
/// the Hive fallback box ([ResilientCredentialStorage]) — before this fix
/// the user could never log in on such a device.
///
/// FAILS on the unfixed code: sign-up throws (the credential write has no
/// fallback), login always fails with `auth.errorWrongPassword` (the hash
/// reads throw), and the session flag can never be stored.
///
/// These tests use the REAL [LocalAuthService] with its default
/// credentials (no in-memory fake): the secure-storage platform channel
/// is mocked to throw, so every primary call fails and the fallback box
/// is the only store that works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalAuthService auth;

  /// Backing map for the stateful "working secure storage" mock (used by
  /// the recovery test only).
  final secureStore = <String, String>{};

  /// Mock secure storage to throw on every call (broken KeyStore).
  void mockSecureStorageThrowing() {
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
  }

  /// Mock secure storage to work again — but EMPTY (no keys stored). The
  /// recovery scenario: credentials live only in the fallback box, and
  /// reads must fall through to it. Unlike the throwing mock, this one
  /// persists writes in [secureStore], like a real keystore would.
  void mockSecureStorageWorking() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = call.arguments;
        final key = args is Map ? args['key'] as String? : null;
        switch (call.method) {
          case 'read':
            return key == null ? null : secureStore[key];
          case 'write':
            final value = args is Map ? args['value'] as String? : null;
            if (key != null && value != null) secureStore[key] = value;
            return null;
          case 'delete':
            if (key != null) secureStore.remove(key);
            return null;
          case 'deleteAll':
            secureStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secureStore);
          default:
            return null;
        }
      },
    );
  }

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('streambox-auth-fallback');
    Hive.init(tempDir.path);
    await initStorage();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    // Every test starts with broken secure storage (the recovery test
    // swaps the mock itself, mid-test).
    mockSecureStorageThrowing();
    secureStore.clear();
    auth = LocalAuthService();
    await Hive.box<UserProfile>(BoxNames.profile).clear();
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
    await Hive.box<String>(BoxNames.authFallback).clear();
  });

  Box<String> fallbackBox() => Hive.box<String>(BoxNames.authFallback);

  Future<SignUpResult> signedUp({
    String name = 'Jarif Ahmed',
    String email = 'jarif@example.com',
    String password = 'correct-horse-123',
  }) =>
      auth.signUp(name: name, email: email, password: password);

  Future<UserProfile> loggedIn(SignUpResult result) => auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );

  group('sign-up / login with broken secure storage', () {
    test('sign-up works while secure storage throws', () async {
      final result = await signedUp();
      expect(result.profile.email, 'jarif@example.com');
      expect(DeviceCode.isValid(result.deviceCode), isTrue);
      // The hashes landed in the FALLBACK box (secure storage threw).
      expect(fallbackBox().containsKey(CredentialKeys.passwordSalt), isTrue);
      expect(fallbackBox().containsKey(CredentialKeys.passwordHash), isTrue);
      expect(fallbackBox().containsKey(CredentialKeys.codeHash), isTrue);
      // The fallback holds HASHES, never plaintext secrets.
      expect(
        fallbackBox().get(CredentialKeys.passwordHash),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        fallbackBox().get(CredentialKeys.codeHash),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        fallbackBox().values
            .any((v) => v.contains('correct-horse-123')),
        isFalse,
      );
      expect(
        fallbackBox().values.any((v) => v.contains(result.deviceCode)),
        isFalse,
      );
      // Sign-up does NOT start a session — login does.
      expect(await auth.isLoggedIn(), isFalse);
    });

    test('login works via the fallback and starts a session', () async {
      final result = await signedUp();
      final profile = await loggedIn(result);
      expect(profile.name, 'Jarif Ahmed');
      expect(await auth.isLoggedIn(), isTrue);
      expect(fallbackBox().get(CredentialKeys.sessionActive), '1');
    });

    test('session survives a fresh AuthService instance (relaunch)',
        () async {
      final result = await signedUp();
      await loggedIn(result);
      // A new service instance reads the same boxes — like a relaunch.
      final freshAuth = LocalAuthService();
      expect(await freshAuth.isLoggedIn(), isTrue);
      expect(freshAuth.currentProfile?.email, 'jarif@example.com');
    });

    test('logout clears the fallback session', () async {
      final result = await signedUp();
      await loggedIn(result);
      await auth.logout();
      expect(await auth.isLoggedIn(), isFalse);
      expect(
        fallbackBox().containsKey(CredentialKeys.sessionActive),
        isFalse,
      );
    });

    test('verifyCode works via the fallback', () async {
      final result = await signedUp();
      expect(await auth.verifyCode(result.deviceCode), isTrue);
      expect(await auth.verifyCode('SB-AAAA-AAAA-AAAA'), isFalse);
    });

    test('wrong password still fails via the fallback', () async {
      final result = await signedUp();
      expect(
        () => auth.login(
          email: 'jarif@example.com',
          password: 'wrong-password',
          deviceCode: result.deviceCode,
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorWrongPassword'),
        ),
      );
      expect(await auth.isLoggedIn(), isFalse);
    });

    test('wrong device code still fails via the fallback', () async {
      await signedUp();
      expect(
        () => auth.login(
          email: 'jarif@example.com',
          password: 'correct-horse-123',
          deviceCode: 'SB-AAAA-AAAA-AAAA',
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorWrongCode'),
        ),
      );
      expect(await auth.isLoggedIn(), isFalse);
    });
  });

  group('onboarding flag with broken secure storage', () {
    test('mark/hasSeenOnboarding work via the fallback', () async {
      expect(await auth.hasSeenOnboarding(), isFalse);
      await auth.markOnboardingSeen();
      expect(await auth.hasSeenOnboarding(), isTrue);
      expect(fallbackBox().get(CredentialKeys.onboardingSeen), '1');
    });
  });

  group('secure storage recovers', () {
    test('login still works after secure storage recovers (read-through)',
        () async {
      final result = await signedUp();
      // Secure storage works again — but it is EMPTY (the hashes only
      // exist in the fallback box). Reads must fall through to it, and
      // the session write must land in the (now working) primary store.
      mockSecureStorageWorking();
      final profile = await loggedIn(result);
      expect(profile.email, 'jarif@example.com');
      expect(await auth.isLoggedIn(), isTrue);
      expect(secureStore[CredentialKeys.sessionActive], '1');
    });

    test('logout after recovery clears both stores', () async {
      final result = await signedUp();
      await loggedIn(result);
      mockSecureStorageWorking();
      // Re-login now that the primary works: the session moves to the
      // primary store (the fallback still holds the stale '1' from the
      // broken period).
      await loggedIn(result);
      await auth.logout();
      expect(await auth.isLoggedIn(), isFalse);
      expect(secureStore.containsKey(CredentialKeys.sessionActive), isFalse);
      expect(
        fallbackBox().containsKey(CredentialKeys.sessionActive),
        isFalse,
      );
    });
  });
}
