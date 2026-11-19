import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Hive box names. Single source of truth — every service and screen uses
/// these constants, never string literals.
class BoxNames {
  BoxNames._();

  /// [ProviderRepo] rows, keyed by repo id.
  static const String providers = 'providers';

  /// [ProviderItem] rows, keyed by `"$providerId::$id"`.
  static const String catalog = 'catalog';

  /// [LibraryEntry] rows, keyed by `"${list.name}::$providerId::$itemId"`.
  static const String library = 'library';

  /// [HistoryEntry] rows, keyed by `"$providerId::$itemId"`.
  static const String history = 'history';

  /// Single [UserProfile] under key `current`.
  static const String profile = 'profile';

  /// Single [AppSettings] under key `current`.
  static const String settings = 'settings';

  /// Auth fallback store (see `ResilientCredentialStorage` in
  /// credential_storage.dart): credential hashes + session/onboarding
  /// flags as plain strings, keyed by CredentialKeys. ONLY written when
  /// flutter_secure_storage throws — on a healthy device this box stays
  /// empty.
  static const String authFallback = 'auth_fallback';
}

/// Android application id. Single constant — the direct Hive candidates
/// below are built from it, never duplicated as literals.
const String _androidPackage = 'com.kizoo.streambox';

/// Direct Android app-data directories, tried FIRST on Android before any
/// platform-channel call (see [initHiveWithFallback]).
///
/// Verified against the path_provider_android 2.3.1 source in the pub
/// cache: `getApplicationDocumentsDirectory()` on Android is
/// `Context.getDir('flutter', MODE_PRIVATE)`, and Android's `getDir(name)`
/// returns `<dataDir>/app_<name>` — so the TRUE `Hive.initFlutter()`
/// location is `<dataDir>/app_flutter`, NOT `<dataDir>/files`. The first
/// candidate is exactly that location, so boxes written through the direct
/// path are found in the same place if the platform channel later works
/// again — no migration issue. The `files` variants are the support
/// directory (`Context.getFilesDir()`). `/data/data/<pkg>` is the legacy
/// data-dir spelling; `/data/user/0/<pkg>` is the modern one (usually the
/// same directory via a symlink, but not on every device).
List<String> get _defaultDirectHiveCandidates => [
      '/data/user/0/$_androidPackage/app_flutter',
      '/data/user/0/$_androidPackage/files',
      '/data/data/$_androidPackage/app_flutter',
      '/data/data/$_androidPackage/files',
    ];

/// Test-only override for the direct Hive candidate list.
///
/// Tests run on a Linux host where `defaultTargetPlatform` is Android, so
/// the real `/data/...` candidates must NEVER be used there — tests set
/// this to temp directories instead (see
/// `test/startup_direct_path_test.dart`). Null (the default) means "use
/// the real Android candidates, on Android only". An empty list disables
/// the direct attempts entirely.
@visibleForTesting
List<String>? debugDirectHiveCandidates;

/// The direct candidates to try on this platform, or empty when the
/// direct path must not be used (non-Android, or web).
///
/// The `Platform.isAndroid` check is load-bearing: `defaultTargetPlatform`
/// is Android inside `flutter_test` on a Linux host, and a test VM can
/// run as root, so a `defaultTargetPlatform`-only guard would create real
/// `/data/...` directories on the test host. `Platform.isAndroid` is true
/// only on a real Android runtime. The test seam bypasses the platform
/// check — tests set [debugDirectHiveCandidates] to temp dirs.
List<String> _directCandidates() {
  final override = debugDirectHiveCandidates;
  if (override != null) return override;
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      !Platform.isAndroid) {
    return const [];
  }
  return _defaultDirectHiveCandidates;
}

/// Create [path] (recursively) and prove it is writable with a probe file
/// (written then deleted). Returns the directory. Throws when the
/// directory cannot be created or is not writable.
Future<Directory> _writableDirectory(String path) async {
  final dir = Directory(path);
  await dir.create(recursive: true);
  final probe = File('${dir.path}/.streambox-write-probe');
  await probe.writeAsString('ok');
  try {
    await probe.delete();
  } catch (_) {
    // A leftover probe file is harmless — writability is already proven.
  }
  return dir;
}

/// Try one direct candidate: create the directory, prove writability with
/// a probe file (written then deleted), then `Hive.init(path)`.
///
/// Throws when the directory cannot be created or is not writable — the
/// caller moves on to the next candidate.
Future<void> _tryDirectHivePath(String path) async {
  final dir = await _writableDirectory(path);
  Hive.init(dir.path);
}

/// A writable app directory, WITHOUT relying on path_provider.
///
/// Tries the pure-Dart direct Android app-data paths first (same list as
/// [initHiveWithFallback] — see [_directCandidates]), then falls back to
/// the documents directory via path_provider. Used by the backup export
/// fallback (when the platform save dialog is unavailable): on a device
/// whose path_provider layer is broken, the direct paths still work, so
/// the export does not fail outright.
///
/// Throws when no writable directory can be found — callers must catch
/// and surface a user-facing error.
Future<Directory> bestWritableAppDir() async {
  for (final candidate in _directCandidates()) {
    try {
      return await _writableDirectory(candidate);
    } catch (_) {
      // Not usable — try the next candidate.
    }
  }
  if (kIsWeb) {
    throw StateError('No writable app directory on web.');
  }
  return getApplicationDocumentsDirectory();
}

/// Initialize Hive's storage directory with a fallback chain.
///
/// Order:
/// 0. Pure-Dart direct Android app-data paths (no platform channel —
///    `dart:io` talks to the filesystem directly). This is what saves a
///    device whose whole path_provider layer is broken: v1.0.2 failed on
///    a phone with `ClassNotFoundException` for `android.content.Context`
///    on EVERY directory call, because path_provider_android 2.3.1
///    resolves all four directories through the same JNI `Context`
///    binding — the old documents → support → temp → cache chain was
///    useless for that failure mode.
/// 1. `Hive.initFlutter()` (the documents directory).
/// 2. Support, temp, then cache via path_provider's Dart API.
///
/// Each attempt is guarded: a failure on one directory never kills the
/// next attempt. `Hive.init()` is safe to call repeatedly (it just
/// re-sets the path), so a failed attempt leaves nothing behind that
/// breaks the next one.
///
/// Throws a [HiveInitException] listing every attempt's error when all
/// directories fail — the startup error screen shows the full text, so
/// the user can send us the complete diagnosis.
Future<void> initHiveWithFallback() async {
  final failures = <String, Object>{};

  // Attempt 0: pure-Dart direct paths (Android only; no platform channel
  // involved). First writable candidate wins.
  for (final candidate in _directCandidates()) {
    try {
      await _tryDirectHivePath(candidate);
      return;
    } catch (e) {
      failures['direct:$candidate'] = e;
    }
  }

  // Attempt 1: the standard documents directory. On web this is a no-op
  // (initFlutter returns early; Hive uses IndexedDB there).
  try {
    await Hive.initFlutter();
    return;
  } catch (e) {
    failures['documents'] = e;
  }

  if (kIsWeb) {
    // No path_provider directories exist on web — nothing else to try.
    throw HiveInitException(failures);
  }

  // Attempts 2–4: support, temp, cache directories via path_provider's
  // Dart API directly. Temp/cache are less durable (the OS may clear
  // them), but a working app in a temp directory beats no app at all —
  // and the user can export a backup from Settings at any time.
  final attempts = <String, Future<Directory> Function()>{
    'support': getApplicationSupportDirectory,
    'temp': getTemporaryDirectory,
    'cache': getApplicationCacheDirectory,
  };
  for (final entry in attempts.entries) {
    try {
      final dir = await entry.value();
      Hive.init(dir.path);
      return;
    } catch (e) {
      failures[entry.key] = e;
    }
  }

  throw HiveInitException(failures);
}

/// Thrown when Hive could not be initialized in any directory. Carries
/// every attempt's error so the startup error screen can show the full
/// diagnosis (not just the last failure).
class HiveInitException implements Exception {
  HiveInitException(this.failures);

  /// Directory label -> error, in attempt order.
  final Map<String, Object> failures;

  @override
  String toString() {
    final lines =
        failures.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return 'Hive init failed in all directories:\n$lines';
  }
}

/// Register all Hive adapters and open every box. Called once from main()
/// before runApp. Adapters are generated by hive_generator
/// (`flutter pub run build_runner build`).
///
/// Idempotent: adapter registration is guarded so the startup Retry path
/// (which re-runs the bootstrap) never throws a duplicate-typeId error,
/// and [Hive.openBox] returns an already-open box instead of re-opening.
bool _adaptersRegistered = false;

Future<void> initStorage() async {
  if (!_adaptersRegistered) {
    Hive
      ..registerAdapter(ProviderItemAdapter())
      ..registerAdapter(ProviderRepoAdapter())
      ..registerAdapter(LibraryEntryAdapter())
      ..registerAdapter(HistoryEntryAdapter())
      ..registerAdapter(UserProfileAdapter())
      ..registerAdapter(AppSettingsAdapter())
      ..registerAdapter(ContentTypeAdapter())
      ..registerAdapter(LibraryListAdapter());
    _adaptersRegistered = true;
  }

  await _openAllBoxes();
}

Future<void> _openAllBoxes() async {
  await Future.wait([
    Hive.openBox<ProviderRepo>(BoxNames.providers),
    Hive.openBox<ProviderItem>(BoxNames.catalog),
    Hive.openBox<LibraryEntry>(BoxNames.library),
    Hive.openBox<HistoryEntry>(BoxNames.history),
    Hive.openBox<UserProfile>(BoxNames.profile),
    Hive.openBox<AppSettings>(BoxNames.settings),
    Hive.openBox<String>(BoxNames.authFallback),
  ]);
}

/// Last-resort recovery when opening a box fails (corrupt box file on
/// disk): close everything, delete the box files, re-open fresh boxes.
/// Only called when open already failed — the data in a corrupt box is
/// unrecoverable anyway, so deleting it loses nothing that was readable.
/// Throws if the fresh open fails too (the startup gate then shows the
/// error screen instead of a white screen).
Future<void> recoverStorage() async {
  await Hive.close();
  for (final name in [
    BoxNames.providers,
    BoxNames.catalog,
    BoxNames.library,
    BoxNames.history,
    BoxNames.profile,
    BoxNames.settings,
    BoxNames.authFallback,
  ]) {
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {
      // Missing file / already gone — nothing to delete.
    }
  }
  await _openAllBoxes();
}
