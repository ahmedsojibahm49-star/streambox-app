import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/data/sample_provider.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/services/provider_service.dart';
import 'package:streambox/services/storage.dart';

/// Provider parsing / fetching / persistence tests. No real network is
/// touched — every fetch test uses a fake http client (MockClient).
void main() {
  late Directory tempDir;
  late Box<ProviderRepo> reposBox;
  late Box<ProviderItem> catalogBox;

  HiveProviderService serviceWithClient(
    http.Client client, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      HiveProviderService(
        reposBox,
        catalogBox,
        httpClient: client,
        fetchTimeout: timeout,
      );

  /// Service whose client must never be called (parse-only tests).
  HiveProviderService parseOnlyService() => serviceWithClient(
        MockClient((_) async => throw StateError('no network in this test')),
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-provider-test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProviderItemAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProviderRepoAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(ContentTypeAdapter());
    }
    reposBox = await Hive.openBox<ProviderRepo>(BoxNames.providers);
    catalogBox = await Hive.openBox<ProviderItem>(BoxNames.catalog);
  });

  setUp(() async {
    await reposBox.clear();
    await catalogBox.clear();
  });

  tearDownAll(() async {
    await reposBox.close();
    await catalogBox.close();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  String repoJson({
    String? name = 'Test Catalog',
    Object? items,
    bool includeName = true,
    bool includeItems = true,
  }) {
    final doc = <String, Object?>{
      if (includeName) 'name': name,
      'version': 1,
      if (includeItems)
        'items': items ??
            [
              {
                'id': 'show-1',
                'type': 'anime',
                'title': 'Test Show',
                'year': 2025,
                'rating': 8.5,
                'genres': ['Action'],
                'episodes': [
                  {
                    'number': 1,
                    'title': 'Pilot',
                    'videoUrl': 'https://example.com/e1.mp4',
                    'durationSeconds': 1400,
                  },
                ],
              },
            ],
    };
    return jsonEncode(doc);
  }

  Map<String, dynamic> itemJson({
    String? id = 'show-1',
    String? title = 'Test Show',
    String? type = 'anime',
    Object? episodes,
    Object? chapters,
    bool includeId = true,
    bool includeTitle = true,
    bool includeType = true,
  }) {
    final map = <String, dynamic>{
      if (includeId) 'id': id,
      if (includeType) 'type': type,
      if (includeTitle) 'title': title,
      'episodes': ?episodes,
      'chapters': ?chapters,
    };
    return map;
  }

  group('parseRepoDocument', () {
    test('valid repo parses: repo row + items', () {
      final parsed = parseOnlyService().parseRepoDocument(
        repoJson(),
        providerId: 'test',
        sourceUrl: 'https://example.com/catalog.json',
      );
      expect(parsed.repo.name, 'Test Catalog');
      expect(parsed.repo.itemCount, 1);
      expect(parsed.items, hasLength(1));
      final item = parsed.items.first;
      expect(item.id, 'show-1');
      expect(item.providerId, 'test');
      expect(item.type, ContentType.anime);
      expect(item.title, 'Test Show');
      expect(item.year, 2025);
      expect(item.rating, 8.5);
      expect(item.genres, ['Action']);
      expect(item.episodes, hasLength(1));
      expect(item.episodes.first['videoUrl'], 'https://example.com/e1.mp4');
    });

    test('sample repo parses: 24 fictional items, 7/7/5/5 mix', () {
      final parsed = parseOnlyService().parseRepoDocument(
        sampleRepoJsonString,
        providerId: sampleRepoId,
        sourceUrl: sampleRepoSourceUrl,
      );
      expect(parsed.repo.name, sampleRepoName);
      expect(parsed.items, hasLength(24));
      final counts = <ContentType, int>{};
      for (final item in parsed.items) {
        counts[item.type] = (counts[item.type] ?? 0) + 1;
      }
      expect(counts[ContentType.anime], 7);
      expect(counts[ContentType.movie], 7);
      expect(counts[ContentType.manga], 5);
      expect(counts[ContentType.manhwa], 5);
      // Every video item has a playable episode; every comic has chapters.
      for (final item in parsed.items) {
        if (item.type == ContentType.anime ||
            item.type == ContentType.movie) {
          expect(item.episodes, isNotEmpty, reason: item.title);
          expect(
            item.episodes.first['videoUrl'],
            startsWith('https://commondatastorage.googleapis.com/'),
            reason: item.title,
          );
        } else {
          expect(item.chapters, isNotEmpty, reason: item.title);
          expect(
            (item.chapters.first['pageUrls'] as List).first as String,
            startsWith('https://picsum.photos/seed/'),
            reason: item.title,
          );
        }
      }
    });

    test('sampleRepoItems() matches the parsed sample JSON', () {
      final parsed = parseOnlyService().parseRepoDocument(
        sampleRepoJsonString,
        providerId: sampleRepoId,
        sourceUrl: sampleRepoSourceUrl,
      );
      final built = sampleRepoItems();
      expect(built, hasLength(parsed.items.length));
      final parsedIds = parsed.items.map((i) => i.id).toSet();
      final builtIds = built.map((i) => i.id).toSet();
      expect(builtIds, parsedIds);
      for (final item in built) {
        final match = parsed.items.firstWhere((p) => p.id == item.id);
        expect(item.title, match.title);
        expect(item.type, match.type);
        expect(item.episodes.length, match.episodes.length);
        expect(item.chapters.length, match.chapters.length);
      }
    });

    test('missing name errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(includeName: false),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('empty name errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(name: '   '),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(isA<RepoException>()),
      );
    });

    test('items not a list errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: {'id': 'x'}),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"items"'),
          ),
        ),
      );
    });

    test('missing items errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(includeItems: false),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(isA<RepoException>()),
      );
    });

    test('item missing id errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(includeId: false)]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"id"'),
          ),
        ),
      );
    });

    test('item missing title errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(includeTitle: false)]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"title"'),
          ),
        ),
      );
    });

    test('bad type errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(type: 'series')]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('unknown type "series"'),
          ),
        ),
      );
    });

    test('missing type errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(includeType: false)]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(isA<RepoException>()),
      );
    });

    test('malformed episode errors: episode not an object', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(episodes: ['nope'])]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('episode'),
          ),
        ),
      );
    });

    test('malformed episode errors: missing number', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [
            itemJson(episodes: [
              {'title': 'No number'},
            ]),
          ]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"number"'),
          ),
        ),
      );
    });

    test('malformed episode errors: videoUrl wrong type', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [
            itemJson(episodes: [
              {'number': 1, 'videoUrl': 42},
            ]),
          ]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"videoUrl"'),
          ),
        ),
      );
    });

    test('malformed chapter errors: pageUrls not a string list', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [
            itemJson(type: 'manga', chapters: [
              {'number': 1, 'pageUrls': 'not-a-list'},
            ]),
          ]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"pageUrls"'),
          ),
        ),
      );
    });

    test('duplicate item ids error', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(), itemJson()]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('share the id'),
          ),
        ),
      );
    });

    test('invalid JSON errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          '{not json',
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('root not an object errors', () {
      expect(
        () => parseOnlyService().parseRepoDocument(
          '[]',
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(isA<RepoException>()),
      );
    });

    test('item cap exceeded errors (1001 items)', () {
      final items = [
        for (var i = 0; i < 1001; i++) itemJson(id: 'item-$i'),
      ];
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: items),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('1000'),
          ),
        ),
      );
    });

    test('episode cap exceeded errors (1001 episodes)', () {
      final episodes = [
        for (var i = 1; i <= 1001; i++) {'number': i},
      ];
      expect(
        () => parseOnlyService().parseRepoDocument(
          repoJson(items: [itemJson(episodes: episodes)]),
          providerId: 't',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('1000'),
          ),
        ),
      );
    });

    test('parseRepo (legacy signature) returns items only', () {
      final items = parseOnlyService().parseRepo(repoJson(), 'test');
      expect(items, hasLength(1));
      expect(items.first.id, 'show-1');
    });
  });

  group('fetchRepo', () {
    const url = 'https://example.com/catalog.json';

    test('rejects non-200 with the status code', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response('Not found', 404)),
      );
      await expectLater(
        service.fetchRepo(url),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('network failure gives a reachability error', () async {
      final service = serviceWithClient(
        MockClient((_) async => throw http.ClientException('boom')),
      );
      await expectLater(
        service.fetchRepo(url),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
    });

    test('timeout gives a timeout error', () async {
      final service = serviceWithClient(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response(repoJson(), 200);
        }),
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        service.fetchRepo(url),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('oversize body is rejected', () async {
      final big = 'x' * (HiveProviderService.maxRepoBytes + 1);
      final service = serviceWithClient(
        MockClient((_) async => http.Response(big, 200)),
      );
      await expectLater(
        service.fetchRepo(url),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('non-json URL is rejected', () async {
      final service = parseOnlyService();
      await expectLater(
        service.fetchRepo('https://example.com/catalog.xml'),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('.json'),
          ),
        ),
      );
    });

    test('invalid JSON from server errors', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response('{bad json', 200)),
      );
      await expectLater(
        service.fetchRepo(url),
        throwsA(isA<RepoException>()),
      );
    });

    test('success persists repo + items; re-fetch updates in place', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response(repoJson(), 200)),
      );
      final repo = await service.fetchRepo(url);
      expect(repo.name, 'Test Catalog');
      expect(repo.itemCount, 1);
      expect(reposBox.get(repo.id), isNotNull);
      expect(
        catalogBox.get('${repo.id}::show-1')?.title,
        'Test Show',
      );

      // Same URL again: same repo id, items replaced not duplicated.
      final again = await service.fetchRepo(url);
      expect(again.id, repo.id);
      expect(catalogBox.length, 1);
    });

    test('validateRepo returns true/false without persisting', () async {
      final okService = serviceWithClient(
        MockClient((_) async => http.Response(repoJson(), 200)),
      );
      expect(await okService.validateRepo(url), isTrue);
      expect(reposBox.isEmpty, isTrue);

      final badService = serviceWithClient(
        MockClient((_) async => http.Response('nope', 404)),
      );
      expect(await badService.validateRepo(url), isFalse);
    });
  });

  group('repo management', () {
    test('seedBuiltIn inserts sample repo + 24 items, idempotent', () async {
      await parseOnlyService().seedBuiltIn();
      final repo = reposBox.get(sampleRepoId);
      expect(repo, isNotNull);
      expect(repo!.isBuiltIn, isTrue);
      expect(repo.itemCount, 24);
      expect(
        catalogBox.values.where((i) => i.providerId == sampleRepoId),
        hasLength(24),
      );

      await parseOnlyService().seedBuiltIn();
      expect(catalogBox.length, 24);
    });

    test('addRepoFromJson + deleteRepo removes repo and items', () async {
      final repo = await parseOnlyService().addRepoFromJson(repoJson());
      expect(repo.sourceUrl, startsWith('pasted://'));
      expect(catalogBox.length, 1);

      await parseOnlyService().deleteRepo(repo.id);
      expect(reposBox.get(repo.id), isNull);
      expect(catalogBox.isEmpty, isTrue);
    });

    test('deleteRepo refuses the built-in catalog', () async {
      await parseOnlyService().seedBuiltIn();
      await expectLater(
        parseOnlyService().deleteRepo(sampleRepoId),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('can’t be removed'),
          ),
        ),
      );
      expect(reposBox.get(sampleRepoId), isNotNull);
    });

    test('toggleRepo hides items from search/itemsByType', () async {
      await parseOnlyService().seedBuiltIn();
      expect(
        parseOnlyService().itemsByType(ContentType.anime),
        hasLength(7),
      );
      expect(parseOnlyService().searchItems('horizon'), hasLength(1));

      await parseOnlyService().toggleRepo(sampleRepoId, false);
      expect(parseOnlyService().itemsByType(ContentType.anime), isEmpty);
      expect(parseOnlyService().searchItems('horizon'), isEmpty);
      // Items stay cached.
      expect(catalogBox.length, 24);
    });

    test('refreshRepo replaces that repo’s items only', () async {
      const url = 'https://example.com/catalog.json';
      final v1Service = serviceWithClient(
        MockClient((_) async => http.Response(repoJson(), 200)),
      );
      final repo = await v1Service.fetchRepo(url);
      await parseOnlyService().seedBuiltIn();
      expect(catalogBox.length, 25);

      final v2 = repoJson(
        items: [
          itemJson(id: 'show-2', title: 'Second Show'),
          itemJson(id: 'show-3', title: 'Third Show'),
        ],
      );
      final v2Service = serviceWithClient(
        MockClient((_) async => http.Response(v2, 200)),
      );

      await v2Service.refreshRepo(repo);
      expect(
        catalogBox.values.where((i) => i.providerId == repo.id),
        hasLength(2),
      );
      expect(catalogBox.get('${repo.id}::show-1'), isNull);
      expect(catalogBox.get('${repo.id}::show-2'), isNotNull);
      // Sample items untouched.
      expect(
        catalogBox.values.where((i) => i.providerId == sampleRepoId),
        hasLength(24),
      );
    });

    test('refreshRepo refuses pasted repos', () async {
      final repo = await parseOnlyService().addRepoFromJson(repoJson());
      await expectLater(
        parseOnlyService().refreshRepo(repo),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('can’t be refreshed'),
          ),
        ),
      );
    });

    test('searchItems matches title + genre, case-insensitive', () async {
      await parseOnlyService().seedBuiltIn();
      expect(
        parseOnlyService().searchItems('HORIZON').map((i) => i.id),
        ['last-horizon'],
      );
      expect(
        parseOnlyService().searchItems('cyberpunk').map((i) => i.id),
        ['neon-frontier'],
      );
      expect(
        parseOnlyService().searchItems(
          'the',
          type: ContentType.manga,
        ),
        isNotEmpty,
      );
      expect(parseOnlyService().searchItems('zzz-no-match'), isEmpty);
      expect(parseOnlyService().searchItems('   '), isEmpty);
    });

    test('listRepos sorts built-in first', () async {
      await parseOnlyService().addRepoFromJson(
        repoJson(name: 'Aaa First Alphabetically'),
      );
      await parseOnlyService().seedBuiltIn();
      final repos = parseOnlyService().listRepos();
      expect(repos.first.id, sampleRepoId);
      expect(repos, hasLength(2));
    });
  });
}
