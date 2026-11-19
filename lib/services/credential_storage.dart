import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure-storage keys for auth data.
///
/// Defined here (not in auth_service.dart) so both [AuthService] and
/// [BackupService] can read/write credentials without a circular import.
///
/// Credentials live in flutter_secure_storage ONLY — never in a Hive box
/// (CONTRACT.md). The password is stored as a salted SHA-256 hash and the
/// device code as a SHA-256 hash; the plaintext code is never stored — it
/// is shown once at sign-up and typed back by the user at login / backup.
abstract final class CredentialKeys {
  static const String passwordSalt = 'sb.password.salt';
  static const String passwordHash = 'sb.password.hash';
  static const String codeHash = 'sb.code.hash';

  /// `'1'` while a session is active (set on login, cleared on logout).
  /// Auto-login on relaunch reads this flag.
  static const String sessionActive = 'sb.session.active';

  /// `'1'` once the user has finished (or skipped) onboarding.
  static const String onboardingSeen = 'sb.onboarding.seen';
}

/// Minimal key/value credential store.
///
/// The real implementation wraps flutter_secure_storage; tests inject an
/// in-memory fake so no platform channel is needed.
abstract class CredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// [CredentialStorage] backed by flutter_secure_storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android).
class FlutterSecureCredentialStorage implements CredentialStorage {
  FlutterSecureCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
