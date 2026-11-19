import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';
import '../utils/code_generator.dart';
import 'backup_service.dart';
import 'credential_storage.dart';
import 'storage.dart';

/// Auth error. [key] is an i18n key — screens show it with
/// `tr(context, key)`.
///
/// Login failures are SPECIFIC by design (the user asked for clear
/// feedback): wrong email / wrong password / wrong code each get their own
/// message. This is a local-only, single-user-per-device app, so the usual
/// "don't reveal which field failed" concern does not apply the way it
/// would for a server.
class AuthException implements Exception {
  const AuthException(this.key);

  final String key;

  @override
  String toString() => 'AuthException($key)';
}

/// Result of [AuthService.signUp]: the created profile plus the device
/// code, which is shown ONCE in the code popup and never stored in
/// plaintext.
class SignUpResult {
  const SignUpResult({required this.profile, required this.deviceCode});

  final UserProfile profile;

  /// `SB-XXXX-XXXX-XXXX`. Show it in the code popup immediately — after
  /// this call the code exists only as a hash in secure storage.
  final String deviceCode;
}

/// Whether a user is signed in on this device. The router watches this
/// provider and redirects (logged out → /welcome, logged in → /home).
///
/// The state starts `false`; the splash screen calls [refresh] once at
/// startup so a returning user auto-logs-in (the session flag survives
/// relaunches until sign-out). Screens flip it directly with
/// [setLoggedIn] after login / logout.
final authStateProvider =
    NotifierProvider<AuthStateNotifier, bool>(AuthStateNotifier.new);

class AuthStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoggedIn(bool value) => state = value;

  /// Re-read the real session (profile + session flag) and update state.
  /// Returns the new value.
  Future<bool> refresh() async {
    final loggedIn = await ref.read(authServiceProvider).isLoggedIn();
    state = loggedIn;
    return loggedIn;
  }
}

/// Auth interface. Implemented by [LocalAuthService].
///
/// All data is local: the profile lives in the `profile` Hive box, the
/// password hash + device-code hash live in flutter_secure_storage, with
/// a Hive fallback box when secure storage throws on a device (see
/// [ResilientCredentialStorage]). There is NO server, NO demo account, NO
/// third-party auth.
///
/// Flow: sign-up generates the device code (shown once in the popup) and
/// stores the account WITHOUT starting a session; the user then logs in
/// with email + password + code (Sign Up → Code → Login → Success → Home).
abstract class AuthService {
  /// Create a local account. Generates the device code and stores the
  /// profile + credential hashes. Does NOT log the user in.
  ///
  /// Throws [AuthException] `auth.errorAccountExists` when this device
  /// already has an account (one local account per device).
  Future<SignUpResult> signUp({
    required String name,
    required String email,
    required String password,
  });

  /// Log in with email + password + device code. Starts the session.
  ///
  /// Throws [AuthException] with `auth.errorWrongEmail`,
  /// `auth.errorWrongPassword` or `auth.errorWrongCode`.
  Future<UserProfile> login({
    required String email,
    required String password,
    required String deviceCode,
  });

  /// Sign out on this device. Does NOT delete the profile — the user can
  /// log back in with email + password + code.
  Future<void> logout();

  /// Delete the account: wipes the profile, credential hashes, session,
  /// library and history from this device. Cannot be undone.
  Future<void> deleteAccount();

  /// True when a profile exists and a session is active.
  Future<bool> isLoggedIn();

  /// The signed-in (or last signed-up) profile, or null when no account
  /// exists on this device. Synchronous — reads the profile box.
  UserProfile? get currentProfile;

  /// Generate a fresh device code (`SB-XXXX-XXXX-XXXX`, see
  /// `lib/utils/code_generator.dart`), seeded with the device id.
  Future<String> generateCode();

  /// True when [code] matches the stored device-code hash.
  Future<bool> verifyCode(String code);

  /// True once onboarding has been finished (or skipped).
  Future<bool> hasSeenOnboarding();

  /// Remember that onboarding was finished (or skipped).
  Future<void> markOnboardingSeen();

  /// Export an encrypted backup file (profile + library + history +
  /// providers + catalog + settings) locked by [deviceCode]. Returns the
  /// written file path (or file name on web).
  Future<String> exportBackup({required String deviceCode});

  /// Import a backup file produced by [exportBackup], unlocked by
  /// [deviceCode]. Replaces local data — the caller must have confirmed
  /// first. Clears the session: the user logs in again with the restored
  /// account.
  Future<void> importBackup({
    required String filePath,
    required String deviceCode,
  });
}

/// Local-first [AuthService] implementation.
///
/// Passwords are stored as SHA-256 iterated 1,000 times over
/// (salt + password) with a random 16-byte salt; the device code is
/// stored as a plain SHA-256 hash (12 chars × 5 bits of entropy). Neither
/// plaintext ever touches disk.
///
/// The default credential store is [ResilientCredentialStorage]:
/// flutter_secure_storage first, a Hive fallback box when secure storage
/// throws on a device — without it, a broken KeyStore meant the user
/// could never log in on that device (v1.0.2).
class LocalAuthService implements AuthService {
  LocalAuthService({
    CredentialStorage? credentials,
    BackupService? backupService,
  })  : _credentials =
            credentials ?? ResilientCredentialStorage(),
        _backup = backupService ??
            BackupService(
              credentials:
                  credentials ?? ResilientCredentialStorage(),
            );

  final CredentialStorage _credentials;
  final BackupService _backup;

  Box<UserProfile> get _profileBox =>
      Hive.box<UserProfile>(BoxNames.profile);

  @override
  Future<SignUpResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_profileBox.containsKey('current')) {
      throw const AuthException('auth.errorAccountExists');
    }
    final code = await generateCode();
    final salt = _randomSalt();
    final profile = UserProfile(
      name: name.trim(),
      email: email.trim().toLowerCase(),
      createdAt: DateTime.now(),
    );
    // Credentials FIRST, profile LAST (audit fix, Nov 19): the old order
    // wrote the profile first, so a credential-write failure left a
    // half-created account — the profile existed (blocking a re-sign-up
    // with `auth.errorAccountExists`) but no password/code hash existed,
    // so login could never succeed either. With this order a failure
    // leaves no profile behind and sign-up can simply be retried (the
    // orphaned hashes are overwritten by the retry).
    await _credentials.write(
      CredentialKeys.passwordSalt,
      salt,
    );
    await _credentials.write(
      CredentialKeys.passwordHash,
      _hashPassword(password, salt),
    );
    await _credentials.write(CredentialKeys.codeHash, _hashCode(code));
    await _profileBox.put('current', profile);
    // No session yet: the user logs in with the code after the popup.
    return SignUpResult(profile: profile, deviceCode: code);
  }

  @override
  Future<UserProfile> login({
    required String email,
    required String password,
    required String deviceCode,
  }) async {
    final profile = _profileBox.get('current');
    final emailNorm = email.trim().toLowerCase();
    if (profile == null || profile.email.toLowerCase() != emailNorm) {
      throw const AuthException('auth.errorWrongEmail');
    }
    final salt = await _credentials.read(CredentialKeys.passwordSalt);
    final storedHash = await _credentials.read(CredentialKeys.passwordHash);
    if (salt == null ||
        storedHash == null ||
        _hashPassword(password, salt) != storedHash) {
      throw const AuthException('auth.errorWrongPassword');
    }
    if (!await verifyCode(deviceCode)) {
      throw const AuthException('auth.errorWrongCode');
    }
    await _credentials.write(CredentialKeys.sessionActive, '1');
    return profile;
  }

  @override
  Future<void> logout() async {
    await _credentials.delete(CredentialKeys.sessionActive);
  }

  @override
  Future<void> deleteAccount() async {
    await _profileBox.clear();
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
    await _credentials.delete(CredentialKeys.passwordSalt);
    await _credentials.delete(CredentialKeys.passwordHash);
    await _credentials.delete(CredentialKeys.codeHash);
    await _credentials.delete(CredentialKeys.sessionActive);
  }

  @override
  Future<bool> isLoggedIn() async {
    if (!_profileBox.containsKey('current')) return false;
    try {
      final session = await _credentials.read(CredentialKeys.sessionActive);
      return session == '1';
    } catch (_) {
      // Defense-in-depth only: the resilient store already falls back to
      // the Hive box and returns null on total failure, so this catch
      // only fires for a custom CredentialStorage that throws. Treat as
      // logged out instead of crashing startup.
      return false;
    }
  }

  @override
  UserProfile? get currentProfile => _profileBox.get('current');

  @override
  Future<String> generateCode() async {
    String? seed;
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      seed = info.data['id']?.toString() ??
          info.data['identifierForVendor']?.toString();
    } catch (_) {
      // No device id available (tests, unsupported platform) — the code
      // is still fully random without a seed.
      seed = null;
    }
    return DeviceCode.generate(seed: seed);
  }

  @override
  Future<bool> verifyCode(String code) async {
    try {
      final storedHash = await _credentials.read(CredentialKeys.codeHash);
      if (storedHash == null) return false;
      return _hashCode(code) == storedHash;
    } catch (_) {
      // Defense-in-depth only (see isLoggedIn) — report the code as wrong
      // instead of crashing the login flow.
      return false;
    }
  }

  @override
  Future<bool> hasSeenOnboarding() async {
    try {
      final seen = await _credentials.read(CredentialKeys.onboardingSeen);
      return seen == '1';
    } catch (_) {
      // Defense-in-depth only (see isLoggedIn) — show onboarding instead
      // of crashing startup. The flag is re-written when onboarding
      // finishes.
      return false;
    }
  }

  @override
  Future<void> markOnboardingSeen() async {
    await _credentials.write(CredentialKeys.onboardingSeen, '1');
  }

  @override
  Future<String> exportBackup({required String deviceCode}) =>
      _backup.exportBackup(deviceCode: deviceCode);

  @override
  Future<void> importBackup({
    required String filePath,
    required String deviceCode,
  }) =>
      _backup.importBackup(
        filePath: filePath,
        deviceCode: deviceCode,
      );

  // -- Hashing ---------------------------------------------------------------

  static String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Iterated SHA-256: `H^1000(salt + ':' + password)`, hex-encoded.
  static String _hashPassword(String password, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$password'));
    for (var i = 1; i < 1000; i++) {
      digest = sha256.convert(digest.bytes);
    }
    return digest.toString();
  }

  /// SHA-256 of the normalised code, hex-encoded.
  static String _hashCode(String code) =>
      sha256.convert(utf8.encode(DeviceCode.normalize(code))).toString();
}

final authServiceProvider = Provider<AuthService>(
  (ref) => LocalAuthService(),
);
