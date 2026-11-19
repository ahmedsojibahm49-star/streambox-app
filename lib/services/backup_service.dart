import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../utils/code_generator.dart';
import 'credential_storage.dart';
import 'storage.dart';

/// Error from backup export/import. [key] is an i18n key — screens show it
/// with `tr(context, key)`.
class BackupException implements Exception {
  const BackupException(this.key);

  final String key;

  @override
  String toString() => 'BackupException($key)';
}

/// Pure backup crypto — no Hive, no platform channels, fully unit-testable.
///
/// File format (JSON envelope, `.sbbackup`):
/// ```json
/// {"version": 1, "salt": "<base64>", "iv": "<base64>",
///  "ciphertext": "<base64>"}
/// ```
/// Key derivation: `SHA-256(utf8(deviceCode) + salt)` (32-byte AES-256 key,
/// random 16-byte salt per export). Cipher: AES-CBC with a random 16-byte
/// IV. The plaintext is the backup payload JSON, which always starts with
/// `{"format": "streambox-backup", "version": 1, ...}` — that marker is how
/// a wrong code is detected (a wrong key decrypts to garbage that fails the
/// marker check).
class BackupCrypto {
  BackupCrypto._();

  static const int version = 1;
  static const String format = 'streambox-backup';

  /// Encrypt [payload] with [deviceCode] and return the envelope JSON.
  static String encryptPayload(
    Map<String, dynamic> payload,
    String deviceCode,
  ) {
    final code = DeviceCode.normalize(deviceCode);
    final salt = _randomBytes(16);
    final key = _deriveKey(code, salt);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final ciphertext =
        encrypter.encrypt(jsonEncode(payload), iv: iv);
    return jsonEncode({
      'version': version,
      'salt': base64Encode(salt),
      'iv': iv.base64,
      'ciphertext': ciphertext.base64,
    });
  }

  /// Decrypt an envelope produced by [encryptPayload].
  ///
  /// Throws [BackupException] with `backup.invalidFile` when the envelope
  /// is not a StreamBox backup at all, and `backup.wrongCode` when the
  /// code cannot unlock it (a wrong key decrypts to garbage; a damaged
  /// file fails the same way, which the copy covers).
  static Map<String, dynamic> decryptPayload(
    String envelopeJson,
    String deviceCode,
  ) {
    final envelope = _parseEnvelope(envelopeJson);
    try {
      final salt = base64Decode(envelope['salt'] as String);
      final iv = enc.IV.fromBase64(envelope['iv'] as String);
      final ciphertext =
          enc.Encrypted.fromBase64(envelope['ciphertext'] as String);
      final code = DeviceCode.normalize(deviceCode);
      final key = _deriveKey(code, salt);
      final encrypter =
          enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
      final plain = encrypter.decrypt(ciphertext, iv: iv);
      final decoded = jsonDecode(plain);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != format ||
          decoded['version'] != version) {
        throw const BackupException('backup.wrongCode');
      }
      return decoded;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('backup.wrongCode');
    }
  }

  /// Key = SHA-256(code bytes + salt bytes), 32 bytes for AES-256.
  static Uint8List _deriveKey(String code, List<int> salt) =>
      Uint8List.fromList(
        sha256.convert([...utf8.encode(code), ...salt]).bytes,
      );

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Map<String, dynamic> _parseEnvelope(String envelopeJson) {
    try {
      final decoded = jsonDecode(envelopeJson);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != version ||
          decoded['salt'] is! String ||
          decoded['iv'] is! String ||
          decoded['ciphertext'] is! String) {
        throw const BackupException('backup.invalidFile');
      }
      return decoded;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('backup.invalidFile');
    }
  }
}

/// Backup export/import.
///
/// Collects profile + library + history + provider repos + cached catalog
/// + settings from Hive, encrypts with the device code (see [BackupCrypto])
/// and writes a `.sbbackup` file; imports reverse the process.
///
/// Honest limit (also stated in the UI): there is no server, so the code
/// alone cannot fetch data on a new device — the backup FILE is the
/// carrier. The code only unlocks a file the user already has.
///
/// The payload also carries the credential hashes (password salt/hash +
/// code hash) so a restored backup can be logged into with the same
/// password + code. Import clears the session — the user logs in again
/// with the restored account.
class BackupService {
  BackupService({CredentialStorage? credentials})
      : _credentials =
            credentials ?? ResilientCredentialStorage();

  final CredentialStorage _credentials;

  // -- Export ---------------------------------------------------------------

  /// Collect, encrypt and save a backup. Returns the saved file path
  /// (or the file name on web, where the save dialog downloads directly).
  ///
  /// Throws [BackupException] with `backup.exportCancelled` when the user
  /// dismisses the save dialog.
  Future<String> exportBackup({required String deviceCode}) async {
    final payload = await collectData();
    final envelope = BackupCrypto.encryptPayload(payload, deviceCode);
    return writeBackupFile(envelopeJson: envelope);
  }

  /// Collect everything that belongs in a backup payload.
  Future<Map<String, dynamic>> collectData() async {
    final profileBox = Hive.box<UserProfile>(BoxNames.profile);
    final profile = profileBox.get('current');
    return {
      'format': BackupCrypto.format,
      'version': BackupCrypto.version,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': profile == null ? null : _profileToJson(profile),
      'credentials': {
        'passwordSalt':
            await _credentials.read(CredentialKeys.passwordSalt),
        'passwordHash':
            await _credentials.read(CredentialKeys.passwordHash),
        'codeHash': await _credentials.read(CredentialKeys.codeHash),
      },
      'library': Hive.box<LibraryEntry>(BoxNames.library).values
          .map(_libraryToJson)
          .toList(),
      'history': Hive.box<HistoryEntry>(BoxNames.history).values
          .map(_historyToJson)
          .toList(),
      'providers': Hive.box<ProviderRepo>(BoxNames.providers).values
          .map(_repoToJson)
          .toList(),
      'catalog': Hive.box<ProviderItem>(BoxNames.catalog).values
          .map(_itemToJson)
          .toList(),
      'settings': _settingsToJson(
        Hive.box<AppSettings>(BoxNames.settings).get('current') ??
            AppSettings(),
      ),
    };
  }

  /// Write an envelope to a `.sbbackup` file via the platform save dialog.
  /// Falls back to the documents directory + share sheet where no save
  /// dialog exists.
  Future<String> writeBackupFile({required String envelopeJson}) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final fileName = 'streambox-backup-$stamp.sbbackup';
    final bytes = Uint8List.fromList(utf8.encode(envelopeJson));
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save backup',
        fileName: fileName,
        bytes: bytes,
      );
      if (uri == null) throw const BackupException('backup.exportCancelled');
      return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    } on BackupException {
      rethrow;
    } catch (_) {
      // No save dialog on this platform (or it failed — e.g. a broken
      // platform channel on the device): write into the app's own
      // directory and open the share sheet instead. The directory lookup
      // uses the direct Android paths first, so it still works on a
      // device whose path_provider layer is broken (the old code called
      // getApplicationDocumentsDirectory() here unguarded — on such a
      // device the fallback itself threw a raw error instead of a
      // BackupException). The share sheet is best-effort: the file is
      // saved either way and the returned path tells the user where.
      try {
        final dir = await bestWritableAppDir();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        try {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)]),
          );
        } catch (_) {
          // Share sheet unavailable — the file is still saved.
        }
        return file.path;
      } catch (_) {
        throw const BackupException('backup.failed');
      }
    }
  }

  // -- Import ---------------------------------------------------------------

  /// Read + decrypt a backup file WITHOUT changing any data. The caller
  /// shows a confirmation dialog and then calls [applyImport].
  Future<Map<String, dynamic>> prepareImport({
    required String filePath,
    required String deviceCode,
  }) async {
    final envelope = await _readBackupFile(filePath);
    return prepareImportFromContent(
      envelopeJson: envelope,
      deviceCode: deviceCode,
    );
  }

  /// Same as [prepareImport] but from already-read envelope text — used
  /// on web, where the picked file has bytes but no path.
  Future<Map<String, dynamic>> prepareImportFromContent({
    required String envelopeJson,
    required String deviceCode,
  }) async {
    final payload = BackupCrypto.decryptPayload(envelopeJson, deviceCode);
    _validatePayload(payload);
    return payload;
  }

  /// Decrypt + restore in one step (used by [AuthService.importBackup]).
  /// The caller must already have confirmed the replacement.
  Future<void> importBackup({
    required String filePath,
    required String deviceCode,
  }) async {
    final payload = await prepareImport(
      filePath: filePath,
      deviceCode: deviceCode,
    );
    await applyImport(payload);
  }

  /// Restore a payload produced by [prepareImport], replacing all local
  /// data. Restores the credential hashes too and clears the session, so
  /// the user logs in again with the restored account.
  Future<void> applyImport(Map<String, dynamic> payload) async {
    _validatePayload(payload);
    await restoreData(payload);
    final creds = payload['credentials'];
    if (creds is Map<String, dynamic>) {
      await _restoreCredential(
        CredentialKeys.passwordSalt,
        creds['passwordSalt'],
      );
      await _restoreCredential(
        CredentialKeys.passwordHash,
        creds['passwordHash'],
      );
      await _restoreCredential(CredentialKeys.codeHash, creds['codeHash']);
    }
    await _credentials.delete(CredentialKeys.sessionActive);
  }

  /// Replace the Hive boxes with the payload's data (no credential work).
  ///
  /// ATOMIC (audit fix, Nov 19): every entry is parsed FIRST, and the
  /// boxes are only cleared once all of them parse cleanly. The old code
  /// cleared the boxes first and parsed while restoring — a single corrupt
  /// entry (e.g. a bad `list` value in one library row) threw midway and
  /// left the user with NO data at all: the old data was already wiped
  /// and the restore had failed.
  Future<void> restoreData(Map<String, dynamic> payload) async {
    _validatePayload(payload);

    // Parse everything before touching any box — every _fromJson below
    // throws BackupException('backup.invalidFile') on bad data, and at
    // this point nothing has been deleted yet.
    final profileJson = payload['profile'];
    final profile = profileJson is Map<String, dynamic>
        ? _profileFromJson(profileJson)
        : null;
    final library =
        _jsonList(payload['library']).map(_libraryFromJson).toList();
    final history =
        _jsonList(payload['history']).map(_historyFromJson).toList();
    final providers =
        _jsonList(payload['providers']).map(_repoFromJson).toList();
    final catalog = _jsonList(payload['catalog']).map(_itemFromJson).toList();
    final settingsJson = payload['settings'];
    final settings = settingsJson is Map<String, dynamic>
        ? _settingsFromJson(settingsJson)
        : AppSettings();

    final profileBox = Hive.box<UserProfile>(BoxNames.profile);
    final libraryBox = Hive.box<LibraryEntry>(BoxNames.library);
    final historyBox = Hive.box<HistoryEntry>(BoxNames.history);
    final providersBox = Hive.box<ProviderRepo>(BoxNames.providers);
    final catalogBox = Hive.box<ProviderItem>(BoxNames.catalog);
    final settingsBox = Hive.box<AppSettings>(BoxNames.settings);

    await Future.wait([
      profileBox.clear(),
      libraryBox.clear(),
      historyBox.clear(),
      providersBox.clear(),
      catalogBox.clear(),
      settingsBox.clear(),
    ]);

    if (profile != null) {
      await profileBox.put('current', profile);
    }
    await libraryBox.putAll({
      for (final e in library) e.boxKey: e,
    });
    await historyBox.putAll({
      for (final e in history) e.boxKey: e,
    });
    await providersBox.putAll({
      for (final r in providers) r.id: r,
    });
    await catalogBox.putAll({
      for (final i in catalog) i.boxKey: i,
    });
    await settingsBox.put('current', settings);
  }

  // -- Helpers ---------------------------------------------------------------

  Future<void> _restoreCredential(String key, Object? value) async {
    if (value is String && value.isNotEmpty) {
      await _credentials.write(key, value);
    } else {
      await _credentials.delete(key);
    }
  }

  Future<String> _readBackupFile(String filePath) async {
    try {
      return await File(filePath).readAsString();
    } catch (_) {
      throw const BackupException('backup.invalidFile');
    }
  }

  /// A usable payload must carry the format marker and a profile — a
  /// backup without an account cannot be logged into.
  void _validatePayload(Map<String, dynamic> payload) {
    if (payload['format'] != BackupCrypto.format ||
        payload['version'] != BackupCrypto.version ||
        payload['profile'] is! Map<String, dynamic>) {
      throw const BackupException('backup.invalidFile');
    }
  }

  static List<Map<String, dynamic>> _jsonList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  // -- Model <-> JSON (kept here so models stay untouched) -------------------

  static Map<String, dynamic> _profileToJson(UserProfile p) => {
        'name': p.name,
        'email': p.email,
        'createdAt': p.createdAt.toIso8601String(),
      };

  static UserProfile _profileFromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final email = json['email'];
    final createdAt = json['createdAt'];
    if (name is! String || email is! String || createdAt is! String) {
      throw const BackupException('backup.invalidFile');
    }
    return UserProfile(
      name: name,
      email: email,
      createdAt: DateTime.tryParse(createdAt) ?? DateTime.now(),
    );
  }

  static Map<String, dynamic> _libraryToJson(LibraryEntry e) => {
        'itemId': e.itemId,
        'providerId': e.providerId,
        'list': e.list.name,
        'savedAt': e.savedAt.toIso8601String(),
      };

  static LibraryEntry _libraryFromJson(Map<String, dynamic> json) {
    final itemId = json['itemId'];
    final providerId = json['providerId'];
    final list = json['list'];
    final savedAt = json['savedAt'];
    if (itemId is! String ||
        providerId is! String ||
        list is! String ||
        savedAt is! String) {
      throw const BackupException('backup.invalidFile');
    }
    LibraryList listValue;
    try {
      listValue = LibraryList.values.byName(list);
    } catch (_) {
      throw const BackupException('backup.invalidFile');
    }
    return LibraryEntry(
      itemId: itemId,
      providerId: providerId,
      list: listValue,
      savedAt: DateTime.tryParse(savedAt) ?? DateTime.now(),
    );
  }

  static Map<String, dynamic> _historyToJson(HistoryEntry e) => {
        'itemId': e.itemId,
        'providerId': e.providerId,
        'episodeOrChapter': e.episodeOrChapter,
        'positionSeconds': e.positionSeconds,
        'page': e.page,
        'updatedAt': e.updatedAt.toIso8601String(),
      };

  static HistoryEntry _historyFromJson(Map<String, dynamic> json) {
    final itemId = json['itemId'];
    final providerId = json['providerId'];
    final episodeOrChapter = json['episodeOrChapter'];
    final updatedAt = json['updatedAt'];
    if (itemId is! String ||
        providerId is! String ||
        episodeOrChapter is! int ||
        updatedAt is! String) {
      throw const BackupException('backup.invalidFile');
    }
    return HistoryEntry(
      itemId: itemId,
      providerId: providerId,
      episodeOrChapter: episodeOrChapter,
      positionSeconds: json['positionSeconds'] is int
          ? json['positionSeconds'] as int
          : 0,
      page: json['page'] is int ? json['page'] as int : 0,
      updatedAt: DateTime.tryParse(updatedAt) ?? DateTime.now(),
    );
  }

  static Map<String, dynamic> _repoToJson(ProviderRepo r) => {
        'id': r.id,
        'name': r.name,
        'sourceUrl': r.sourceUrl,
        'isBuiltIn': r.isBuiltIn,
        'enabled': r.enabled,
        'itemCount': r.itemCount,
        'lastFetchedAt': r.lastFetchedAt?.toIso8601String(),
        'rawJson': r.rawJson,
      };

  static ProviderRepo _repoFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final sourceUrl = json['sourceUrl'];
    if (id is! String || name is! String || sourceUrl is! String) {
      throw const BackupException('backup.invalidFile');
    }
    final lastFetchedAt = json['lastFetchedAt'];
    return ProviderRepo(
      id: id,
      name: name,
      sourceUrl: sourceUrl,
      isBuiltIn: json['isBuiltIn'] is bool ? json['isBuiltIn'] as bool : false,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      itemCount: json['itemCount'] is int ? json['itemCount'] as int : 0,
      lastFetchedAt: lastFetchedAt is String
          ? DateTime.tryParse(lastFetchedAt)
          : null,
      rawJson: json['rawJson'] is String ? json['rawJson'] as String : null,
    );
  }

  static Map<String, dynamic> _itemToJson(ProviderItem i) => {
        'id': i.id,
        'providerId': i.providerId,
        'type': i.type.name,
        'title': i.title,
        'posterUrl': i.posterUrl,
        'backdropUrl': i.backdropUrl,
        'year': i.year,
        'rating': i.rating,
        'genres': i.genres,
        'overview': i.overview,
        'status': i.status,
        'episodesJson': i.episodesJson,
        'chaptersJson': i.chaptersJson,
      };

  static ProviderItem _itemFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final providerId = json['providerId'];
    final type = json['type'];
    final title = json['title'];
    if (id is! String ||
        providerId is! String ||
        type is! String ||
        title is! String) {
      throw const BackupException('backup.invalidFile');
    }
    ContentType typeValue;
    try {
      typeValue = ContentType.values.byName(type);
    } catch (_) {
      throw const BackupException('backup.invalidFile');
    }
    return ProviderItem(
      id: id,
      providerId: providerId,
      type: typeValue,
      title: title,
      posterUrl:
          json['posterUrl'] is String ? json['posterUrl'] as String : null,
      backdropUrl: json['backdropUrl'] is String
          ? json['backdropUrl'] as String
          : null,
      year: json['year'] is int ? json['year'] as int : null,
      rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
      genres: json['genres'] is List
          ? (json['genres'] as List).whereType<String>().toList()
          : const [],
      overview: json['overview'] is String ? json['overview'] as String : null,
      status: json['status'] is String ? json['status'] as String : null,
      episodesJson: json['episodesJson'] is String
          ? json['episodesJson'] as String
          : null,
      chaptersJson: json['chaptersJson'] is String
          ? json['chaptersJson'] as String
          : null,
    );
  }

  static Map<String, dynamic> _settingsToJson(AppSettings s) => {
        'themeMode': s.themeMode,
        'localeCode': s.localeCode,
        'notificationsEnabled': s.notificationsEnabled,
      };

  static AppSettings _settingsFromJson(Map<String, dynamic> json) =>
      AppSettings(
        themeMode:
            json['themeMode'] is String ? json['themeMode'] as String : 'system',
        localeCode:
            json['localeCode'] is String ? json['localeCode'] as String : 'en',
        notificationsEnabled: json['notificationsEnabled'] is bool
            ? json['notificationsEnabled'] as bool
            : true,
      );
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(),
);
