import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'storage.dart';

/// Secure-storage keys for auth data.
///
/// Defined here (not in auth_service.dart) so both [AuthService] and
/// [BackupService] can read/write credentials without a circular import.
///
/// Credentials normally live in flutter_secure_storage ONLY. The ONE
/// exception is the degraded fallback: when secure storage throws on a
/// device (broken KeyStore — seen in the wild, v1.0.2), the same hashes
/// are stored in the `authFallback` Hive box instead (see
/// [ResilientCredentialStorage]). The password is stored as a salted
/// SHA-256 hash and the device code as a SHA-256 hash; the plaintext code
/// is never stored — it is shown once at sign-up and typed back by the
/// user at login / backup.
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

/// [CredentialStorage] that survives a broken secure-storage channel.
///
/// Primary store is flutter_secure_storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android). On ANY exception from the
/// primary, reads and writes fall back to the `authFallback` Hive box
/// (opened by [initStorage] before any auth call runs):
///
/// * read: secure storage first; when it throws OR returns null, the
///   fallback box. (The null fall-through matters when secure storage
///   recovers after credentials were written to the fallback — the hashes
///   are still found.) When both stores fail, read returns null instead
///   of throwing: auth flows degrade to "no credential" rather than
///   crashing.
/// * write: secure storage; on ANY exception, the fallback box. If the
///   fallback write ALSO fails, the exception propagates — sign-up must
///   fail visibly rather than pretend the account was created.
/// * delete: BOTH stores (best-effort each). Required by the null
///   fall-through on read: a stale fallback value must never resurrect a
///   deleted session after logout.
/// * deleteAll: both stores, best-effort.
///
/// Security note: the fallback box holds exactly what secure storage
/// holds — salted SHA-256 password hashes, SHA-256 code hashes, and `'1'`
/// flags. No plaintext password or device code is ever stored in either
/// place, so the fallback introduces no new secret — only a weaker
/// container (a plain Hive file instead of the OS keystore) on devices
/// whose keystore is broken anyway. On a healthy device the fallback box
/// stays empty.
///
/// A HANGING secure-storage call (as opposed to a throwing one) is NOT
/// rescued here — the read awaits the primary. Startup is still safe:
/// the splash wraps its session check in an 8s timeout.
class ResilientCredentialStorage implements CredentialStorage {
  ResilientCredentialStorage({CredentialStorage? primary})
      : _primary = primary ?? FlutterSecureCredentialStorage();

  final CredentialStorage _primary;

  /// The fallback box, resolved lazily: it is opened by [initStorage]
  /// before any auth call runs, but resolving it in the constructor would
  /// throw during provider setup on a cold start.
  Box<String> get _fallbackBox => Hive.box<String>(BoxNames.authFallback);

  @override
  Future<String?> read(String key) async {
    try {
      final value = await _primary.read(key);
      if (value != null) return value;
    } catch (_) {
      // Broken secure storage — fall through to the Hive box below.
    }
    try {
      return _fallbackBox.get(key);
    } catch (_) {
      // Fallback box unavailable too (not opened / corrupt) — degrade to
      // "no credential" instead of crashing the caller.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _primary.write(key, value);
      return;
    } catch (_) {
      // Broken secure storage — write to the Hive fallback box instead.
    }
    await _fallbackBox.put(key, value);
  }

  @override
  Future<void> delete(String key) async {
    Object? primaryError;
    try {
      await _primary.delete(key);
    } catch (e) {
      primaryError = e;
    }
    try {
      await _fallbackBox.delete(key);
    } catch (_) {
      // Only fail when BOTH stores failed: if the primary delete worked,
      // a fallback failure is harmless (the box may simply be unavailable
      // in a test), and if the primary failed but the fallback delete
      // worked, the value is gone from every store a read could reach.
      if (primaryError != null) throw primaryError;
    }
  }

  @override
  Future<void> deleteAll() async {
    Object? primaryError;
    try {
      await _primary.deleteAll();
    } catch (e) {
      primaryError = e;
    }
    try {
      await _fallbackBox.clear();
    } catch (_) {
      if (primaryError != null) throw primaryError;
    }
  }
}
