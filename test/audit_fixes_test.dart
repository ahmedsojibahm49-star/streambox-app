import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:streambox/models/models.dart';
import 'package:streambox/services/auth_service.dart';
import 'package:streambox/services/backup_service.dart';
import 'package:streambox/services/credential_storage.dart';
import 'package:streambox/services/provider_service.dart';
import 'package:streambox/services/storage.dart';

/// Regression tests for the Nov 19 full-audit fixes (Fix 4):
///
/// 1. Sign-up atomicity — a credential-write failure must not leave a
///    half-created account behind.
/// 2. Backup restore atomicity — a corrupt entry must fail BEFORE any box
///    is cleared.
/// 3. `youtubeId` episodes survive parsing (the parser used to drop them).
/// 4. Oversized repo fetches abort mid-stream (the old code downloaded the
///    whole body before the size check ran).
/// 5. `bestWritableAppDir` uses the direct Android paths first (the backup
///    export fallback depends on it on devices with broken path_provider).

/// [CredentialStorage] that throws on the Nth write (1-based), so tests
/// can fail sign-up midway through its credential writes.
class _FailingCredentialStorage implements CredentialStorage {
  _FailingCredentialStorage({this.failOnWrite = -1});

  final Map<String, String> _map = {};
  int failOnWrite;
  int writes = 0;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (writes == failOnWrite) throw StateError('simulated write failure');
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// Fake http client that streams twenty 1 MB chunks, counting how many
/// the consumer actually pulled — proves the size cap aborts the download
/// instead of consuming the whole body.
class _ChunkedClient extends http.BaseClient {
  int chunksEmitted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> stream() async* {
      for (var i = 0; i < 20; i++) {
        chunksEmitted++;
        yield List<int>.filled(1024 * 1024, 0x61);
      }
    }

    return http.StreamedResponse(stream(), 200);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-audit-test');
    Hive.init(tempDir.path);
    await initStorage();
  });

  tearDownAll(() async {
    debugDirectHiveCandidates = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    debugDirectHiveCandidates = null;
    await Hive.box<UserProfile>(BoxNames.profile).clear();
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
    await Hive.box<ProviderRepo>(BoxNames.providers).clear();
    await Hive.box<ProviderItem>(BoxNames.catalog).clear();
    await Hive.box<AppSettings>(BoxNames.settings).clear();
  });

  group('sign-up atomicity', () {
    test('a credential failure leaves no half-created account', () async {
      final credentials =
          _FailingCredentialStorage(failOnWrite: 2); // passwordHash write
      final auth = LocalAuthService(
        credentials: credentials,
        backupService: BackupService(credentials: credentials),
      );

      await expectLater(
        () => auth.signUp(
          name: 'Jarif Ahmed',
          email: 'jarif@example.com',
          password: 'correct-horse-123',
        ),
        throwsStateError,
      );

      // No profile was written, so a retry is possible (the old order
      // wrote the profile first and the retry failed with
      // auth.errorAccountExists while login could never succeed).
      expect(
        Hive.box<UserProfile>(BoxNames.profile).containsKey('current'),
        isFalse,
      );

      credentials.failOnWrite = -1;
      final result = await auth.signUp(
        name: 'Jarif Ahmed',
        email: 'jarif@example.com',
        password: 'correct-horse-123',
      );
      final profile = await auth.login(
        email: 'jarif@example.com',
        password: 'correct-horse-123',
        deviceCode: result.deviceCode,
      );
      expect(profile.email, 'jarif@example.com');
    });
  });

  group('backup restore atomicity', () {
    test('a corrupt entry fails before any data is wiped', () async {
      final credentials = _FailingCredentialStorage();
      final backup = BackupService(credentials: credentials);
      final auth = LocalAuthService(
        credentials: credentials,
        backupService: backup,
      );
      await auth.signUp(
        name: 'Jarif Ahmed',
        email: 'jarif@example.com',
        password: 'correct-horse-123',
      );
      await Hive.box<LibraryEntry>(BoxNames.library).put(
        'myList::sample::show-1',
        LibraryEntry(
          itemId: 'show-1',
          providerId: 'sample',
          list: LibraryList.myList,
          savedAt: DateTime.utc(2026, 11, 19),
        ),
      );

      final payload = await backup.collectData();
      // Corrupt one library entry — an invalid `list` value.
      final library = payload['library'] as List;
      (library.first as Map<String, dynamic>)['list'] = 'not-a-list';

      await expectLater(
        () => backup.restoreData(payload),
        throwsA(
          isA<BackupException>()
              .having((e) => e.key, 'key', 'backup.invalidFile'),
        ),
      );

      // The old data is untouched: the restore failed BEFORE clearing.
      expect(
        Hive.box<UserProfile>(BoxNames.profile).get('current')?.email,
        'jarif@example.com',
      );
      expect(
        Hive.box<LibraryEntry>(BoxNames.library).length,
        1,
      );
    });

    test('a valid payload still restores after the refactor', () async {
      final credentials = _FailingCredentialStorage();
      final backup = BackupService(credentials: credentials);
      final auth = LocalAuthService(
        credentials: credentials,
        backupService: backup,
      );
      await auth.signUp(
        name: 'Jarif Ahmed',
        email: 'jarif@example.com',
        password: 'correct-horse-123',
      );
      final payload = await backup.collectData();

      await Hive.box<UserProfile>(BoxNames.profile).clear();
      await backup.restoreData(payload);

      expect(
        Hive.box<UserProfile>(BoxNames.profile).get('current')?.email,
        'jarif@example.com',
      );
    });
  });

  group('youtubeId episodes', () {
    HiveProviderService parseOnlyService() => HiveProviderService(
          Hive.box<ProviderRepo>(BoxNames.providers),
          Hive.box<ProviderItem>(BoxNames.catalog),
          httpClient: _ChunkedClient(), // never called by parse tests
        );

    test('youtubeId survives parsing', () {
      final parsed = parseOnlyService().parseRepoDocument(
        jsonEncode({
          'name': 'YT Catalog',
          'items': [
            {
              'id': 'show-1',
              'type': 'anime',
              'title': 'YT Show',
              'episodes': [
                {
                  'number': 1,
                  'title': 'Pilot',
                  'youtubeId': 'dQw4w9WgXcQ',
                  'durationSeconds': 1400,
                },
                {
                  'number': 2,
                  'title': 'Second',
                  'youtubeId': 'dQw4w9WgXcQ',
                  'videoUrl': 'https://example.com/e2.mp4',
                },
              ],
            },
          ],
        }),
        providerId: 'yt-repo',
        sourceUrl: 'https://example.com/repo.json',
      );
      expect(parsed.items.length, 1);
      final episodes = parsed.items.single.episodes;
      expect(episodes[0]['youtubeId'], 'dQw4w9WgXcQ');
      // Both sources survive when an episode carries both.
      expect(episodes[1]['youtubeId'], 'dQw4w9WgXcQ');
      expect(episodes[1]['videoUrl'], 'https://example.com/e2.mp4');
    });

    test('a non-string youtubeId is rejected with a specific error', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          jsonEncode({
            'name': 'Bad Catalog',
            'items': [
              {
                'id': 'show-1',
                'type': 'anime',
                'title': 'Bad Show',
                'episodes': [
                  {'number': 1, 'youtubeId': 12345},
                ],
              },
            ],
          }),
          providerId: 'bad-repo',
          sourceUrl: 'https://example.com/repo.json',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('youtubeId'),
          ),
        ),
      );
    });
  });

  group('streamed repo fetch', () {
    test('an oversized body aborts mid-stream instead of downloading all',
        () async {
      final client = _ChunkedClient();
      final service = HiveProviderService(
        Hive.box<ProviderRepo>(BoxNames.providers),
        Hive.box<ProviderItem>(BoxNames.catalog),
        httpClient: client,
      );

      await expectLater(
        () => service.fetchRepo('https://example.com/huge.json'),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      // 5 MB cap / 1 MB chunks: the 6th chunk trips the cap, so only 6 of
      // the 20 chunks are ever pulled. The old whole-body download would
      // have consumed all 20 (20 MB) before checking.
      expect(client.chunksEmitted, 6);
    });
  });

  group('bestWritableAppDir', () {
    test('uses the direct candidates before path_provider', () async {
      final direct = await Directory.systemTemp.createTemp(
        'streambox-audit-direct',
      );
      addTearDown(() => direct.delete(recursive: true));
      debugDirectHiveCandidates = [direct.path];

      final dir = await bestWritableAppDir();
      expect(dir.path, direct.path);
      // The directory was proven writable (probe file written + deleted).
      expect(dir.existsSync(), isTrue);
      expect(
        File('${dir.path}/.streambox-write-probe').existsSync(),
        isFalse,
      );
    });

    test('skips an unwritable direct candidate', () async {
      final direct = await Directory.systemTemp.createTemp(
        'streambox-audit-direct2',
      );
      addTearDown(() => direct.delete(recursive: true));
      // A path under a regular FILE cannot be created as a directory.
      final blocker = File('${direct.path}/blocker');
      await blocker.writeAsString('x');
      debugDirectHiveCandidates = [
        '${blocker.path}/child',
        direct.path,
      ];

      final dir = await bestWritableAppDir();
      expect(dir.path, direct.path);
    });
  });
}
