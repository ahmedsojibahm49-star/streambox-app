import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/services/auth_service.dart';
import 'package:streambox/services/backup_service.dart';
import 'package:streambox/services/credential_storage.dart';
import 'package:streambox/services/storage.dart';
import 'package:streambox/utils/code_generator.dart';

/// In-memory [CredentialStorage] so auth tests need no platform channel.
class InMemoryCredentialStorage implements CredentialStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

void main() {
  late Directory tempDir;
  late InMemoryCredentialStorage credentials;
  late LocalAuthService auth;
  late BackupService backup;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-auth-test');
    Hive.init(tempDir.path);
    await initStorage();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    credentials = InMemoryCredentialStorage();
    backup = BackupService(credentials: credentials);
    auth = LocalAuthService(
      credentials: credentials,
      backupService: backup,
    );
    await Hive.box<UserProfile>(BoxNames.profile).clear();
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
    await Hive.box<ProviderRepo>(BoxNames.providers).clear();
    await Hive.box<ProviderItem>(BoxNames.catalog).clear();
    await Hive.box<AppSettings>(BoxNames.settings).clear();
  });

  Future<SignUpResult> signedUp({
    String name = 'Jarif Ahmed',
    String email = 'jarif@example.com',
    String password = 'correct-horse-123',
  }) =>
      auth.signUp(name: name, email: email, password: password);

  group('signUp / login', () {
    test('signUp creates the profile and returns a valid device code',
        () async {
      final result = await signedUp();
      expect(result.profile.name, 'Jarif Ahmed');
      expect(result.profile.email, 'jarif@example.com');
      expect(DeviceCode.isValid(result.deviceCode), isTrue);
      expect(auth.currentProfile?.email, 'jarif@example.com');
      // Sign-up does NOT start a session — login does.
      expect(await auth.isLoggedIn(), isFalse);
    });

    test('a second signUp on the same device fails', () async {
      await signedUp();
      expect(
        () => signedUp(email: 'other@example.com'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorAccountExists'),
        ),
      );
    });

    test('login with correct credentials passes and starts a session',
        () async {
      final result = await signedUp();
      final profile = await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      expect(profile.name, 'Jarif Ahmed');
      expect(await auth.isLoggedIn(), isTrue);
    });

    test('login is case-insensitive on email and tolerant of code spacing',
        () async {
      final result = await signedUp();
      final profile = await auth.login(
        email: '  JARIF@Example.COM ',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode.toLowerCase().replaceAll('-', ' '),
      );
      expect(profile.email, 'jarif@example.com');
    });

    test('login with wrong password fails', () async {
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

    test('login with wrong code fails', () async {
      await signedUp();
      expect(
        () => auth.login(
          email: 'jarif@example.com',
          password: 'correct-horse-123',
          deviceCode: 'SB-AAAA-BBBB-CCCC',
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorWrongCode'),
        ),
      );
      expect(await auth.isLoggedIn(), isFalse);
    });

    test('login with wrong email fails', () async {
      final result = await signedUp();
      expect(
        () => auth.login(
          email: 'someone-else@example.com',
          password: 'correct-horse-123',
          deviceCode: result.deviceCode,
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorWrongEmail'),
        ),
      );
    });

    test('login with no account fails as wrong email', () async {
      expect(
        () => auth.login(
          email: 'nobody@example.com',
          password: 'whatever-123',
          deviceCode: 'SB-AAAA-BBBB-CCCC',
        ),
        throwsA(
          isA<AuthException>()
              .having((e) => e.key, 'key', 'auth.errorWrongEmail'),
        ),
      );
    });

    test('logout clears the session but keeps the account', () async {
      final result = await signedUp();
      await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      expect(await auth.isLoggedIn(), isTrue);
      await auth.logout();
      expect(await auth.isLoggedIn(), isFalse);
      expect(auth.currentProfile, isNotNull);
      // Can log back in with the same credentials.
      await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      expect(await auth.isLoggedIn(), isTrue);
    });

    test('deleteAccount wipes profile, credentials, library and history',
        () async {
      final result = await signedUp();
      await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      final libraryBox = Hive.box<LibraryEntry>(BoxNames.library);
      final historyBox = Hive.box<HistoryEntry>(BoxNames.history);
      final entry = LibraryEntry(
        itemId: '1',
        providerId: 'sample',
        list: LibraryList.myList,
        savedAt: DateTime.now(),
      );
      await libraryBox.put(entry.boxKey, entry);
      final history = HistoryEntry(
        itemId: '1',
        providerId: 'sample',
        episodeOrChapter: 3,
        updatedAt: DateTime.now(),
      );
      await historyBox.put(history.boxKey, history);

      await auth.deleteAccount();

      expect(auth.currentProfile, isNull);
      expect(await auth.isLoggedIn(), isFalse);
      expect(libraryBox.isEmpty, isTrue);
      expect(historyBox.isEmpty, isTrue);
      expect(
        await credentials.read(CredentialKeys.passwordHash),
        isNull,
      );
      expect(
        await credentials.read(CredentialKeys.codeHash),
        isNull,
      );
      expect(
        () => auth.login(
          email: 'jarif@example.com',
          password: 'correct-horse-123',
          deviceCode: result.deviceCode,
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('verifyCode matches only the real code', () async {
      final result = await signedUp();
      expect(await auth.verifyCode(result.deviceCode), isTrue);
      expect(await auth.verifyCode('SB-AAAA-BBBB-CCCC'), isFalse);
    });

    test('onboarding flag round-trips', () async {
      expect(await auth.hasSeenOnboarding(), isFalse);
      await auth.markOnboardingSeen();
      expect(await auth.hasSeenOnboarding(), isTrue);
    });
  });

  group('backup crypto', () {
    const payload = {
      'format': 'streambox-backup',
      'version': 1,
      'profile': {'name': 'Jarif Ahmed', 'email': 'jarif@example.com'},
      'library': [
        {'itemId': '1', 'providerId': 'sample'},
      ],
    };

    test('encrypt then decrypt restores identical JSON', () {
      const code = 'SB-AAAA-BBBB-CCCC';
      final envelope = BackupCrypto.encryptPayload(payload, code);
      final restored = BackupCrypto.decryptPayload(envelope, code);
      expect(restored, payload);
    });

    test('each export uses a fresh salt and IV', () {
      const code = 'SB-AAAA-BBBB-CCCC';
      final a = BackupCrypto.encryptPayload(payload, code);
      final b = BackupCrypto.encryptPayload(payload, code);
      expect(a, isNot(b));
      expect(BackupCrypto.decryptPayload(a, code), payload);
      expect(BackupCrypto.decryptPayload(b, code), payload);
    });

    test('decrypt with the wrong code fails', () {
      const code = 'SB-AAAA-BBBB-CCCC';
      final envelope = BackupCrypto.encryptPayload(payload, code);
      expect(
        () => BackupCrypto.decryptPayload(envelope, 'SB-DDDD-EEEE-FFFF'),
        throwsA(
          isA<BackupException>()
              .having((e) => e.key, 'key', 'backup.wrongCode'),
        ),
      );
    });

    test('decrypt of a non-backup file fails as invalid', () {
      expect(
        () => BackupCrypto.decryptPayload(
          '{"hello": "world"}',
          'SB-AAAA-BBBB-CCCC',
        ),
        throwsA(
          isA<BackupException>()
              .having((e) => e.key, 'key', 'backup.invalidFile'),
        ),
      );
      expect(
        () => BackupCrypto.decryptPayload(
          'not json at all',
          'SB-AAAA-BBBB-CCCC',
        ),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('backup export/import round-trip', () {
    test('collect, encrypt, decrypt, restore returns identical data',
        () async {
      final result = await signedUp();
      final libraryBox = Hive.box<LibraryEntry>(BoxNames.library);
      final historyBox = Hive.box<HistoryEntry>(BoxNames.history);
      final providersBox = Hive.box<ProviderRepo>(BoxNames.providers);
      final catalogBox = Hive.box<ProviderItem>(BoxNames.catalog);

      final entry = LibraryEntry(
        itemId: 'last-horizon',
        providerId: 'sample',
        list: LibraryList.favorite,
        savedAt: DateTime.utc(2026, 11, 19, 10, 30),
      );
      await libraryBox.put(entry.boxKey, entry);
      final history = HistoryEntry(
        itemId: 'last-horizon',
        providerId: 'sample',
        episodeOrChapter: 5,
        positionSeconds: 742,
        updatedAt: DateTime.utc(2026, 11, 19, 10, 31),
      );
      await historyBox.put(history.boxKey, history);
      await providersBox.put(
        'sample',
        ProviderRepo(
          id: 'sample',
          name: 'Sample catalog',
          sourceUrl: 'asset://sample_catalog.json',
          isBuiltIn: true,
          itemCount: 10,
        ),
      );
      await catalogBox.put(
        'sample::last-horizon',
        ProviderItem(
          id: 'last-horizon',
          providerId: 'sample',
          type: ContentType.movie,
          title: 'Last Horizon',
          year: 2026,
          rating: 8.7,
          genres: ['Sci-Fi', 'Drama'],
        ),
      );

      // Export to a real file through the crypto layer (no file picker).
      final collected = await backup.collectData();
      final envelope = BackupCrypto.encryptPayload(
        collected,
        result.deviceCode,
      );
      final file = File('${tempDir.path}/roundtrip.sbbackup');
      await file.writeAsString(envelope);

      // Wipe everything, as a fresh device would be.
      await Hive.box<UserProfile>(BoxNames.profile).clear();
      await libraryBox.clear();
      await historyBox.clear();
      await providersBox.clear();
      await catalogBox.clear();
      await credentials.deleteAll();

      // Import from the file with the right code.
      await backup.importBackup(
        filePath: file.path,
        deviceCode: result.deviceCode,
      );

      expect(auth.currentProfile?.name, 'Jarif Ahmed');
      expect(auth.currentProfile?.email, 'jarif@example.com');
      expect(libraryBox.length, 1);
      final restoredEntry = libraryBox.values.single;
      expect(restoredEntry.itemId, 'last-horizon');
      expect(restoredEntry.list, LibraryList.favorite);
      expect(historyBox.length, 1);
      final restoredHistory = historyBox.values.single;
      expect(restoredHistory.episodeOrChapter, 5);
      expect(restoredHistory.positionSeconds, 742);
      expect(providersBox.length, 1);
      expect(providersBox.get('sample')?.itemCount, 10);
      expect(catalogBox.length, 1);
      expect(catalogBox.values.single.title, 'Last Horizon');
      expect(catalogBox.values.single.rating, 8.7);
      // Restored credentials work — the user can log in again.
      expect(await auth.verifyCode(result.deviceCode), isTrue);
      final profile = await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      expect(profile.name, 'Jarif Ahmed');
    });

    test('import with the wrong code fails and leaves data untouched',
        () async {
      final result = await signedUp();
      final collected = await backup.collectData();
      final envelope = BackupCrypto.encryptPayload(
        collected,
        result.deviceCode,
      );
      final file = File('${tempDir.path}/wrong-code.sbbackup');
      await file.writeAsString(envelope);

      expect(
        () => backup.importBackup(
          filePath: file.path,
          deviceCode: 'SB-ZZZZ-YYYY-XXXX',
        ),
        throwsA(
          isA<BackupException>()
              .having((e) => e.key, 'key', 'backup.wrongCode'),
        ),
      );
      // Nothing was wiped: the account is still there.
      expect(auth.currentProfile?.email, 'jarif@example.com');
    });

    test('import of a damaged file fails as invalid', () async {
      final file = File('${tempDir.path}/damaged.sbbackup');
      await file.writeAsString('{"version": 1, "salt": "xx"}');
      expect(
        () => backup.importBackup(
          filePath: file.path,
          deviceCode: 'SB-AAAA-BBBB-CCCC',
        ),
        throwsA(
          isA<BackupException>()
              .having((e) => e.key, 'key', 'backup.invalidFile'),
        ),
      );
    });
  });
}
