import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/services/provider_service.dart';
import 'package:streambox/services/storage.dart';

/// Multi-catalog provider tests (v1.0.4): one JSON file may hold several
/// providers — `{"providers": [...]}`, a top-level array, or the original
/// single-catalog object. No real network is touched — every fetch test
/// uses a fake http client (MockClient).
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
    tempDir =
        await Directory.systemTemp.createTemp('streambox-multicat-test');
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

  Map<String, dynamic> itemJson({
    String id = 'show-1',
    String title = 'Test Show',
    String type = 'anime',
  }) => {
        'id': id,
        'type': type,
        'title': title,
      };

  Map<String, dynamic> catalogJson({
    String? name = 'Catalog A',
    Object? items,
    bool includeName = true,
    bool includeItems = true,
  }) {
    final doc = <String, Object?>{
      if (includeName) 'name': name,
      if (includeItems) 'items': items ?? [itemJson()],
    };
    return doc;
  }

  String singleJson({String? name = 'Catalog A', Object? items}) =>
      jsonEncode(catalogJson(name: name, items: items));

  String providersObjectJson(List<Map<String, dynamic>> catalogs) =>
      jsonEncode({'providers': catalogs});

  String arrayJson(List<Map<String, dynamic>> catalogs) =>
      jsonEncode(catalogs);

  group('parseRepoDocuments', () {
    test('multi-catalog object parses: one repo per catalog', () {
      final parsed = parseOnlyService().parseRepoDocuments(
        providersObjectJson([
          catalogJson(name: 'Anime Hub'),
          catalogJson(
            name: 'Manga Vault',
            items: [
              itemJson(id: 'm-1', title: 'Manga One', type: 'manga'),
              itemJson(id: 'm-2', title: 'Manga Two', type: 'manga'),
            ],
          ),
        ]),
        providerIdBase: 'base',
        sourceUrl: 'https://example.com/catalog.json',
      );
      expect(parsed, hasLength(2));
      expect(parsed[0].repo.name, 'Anime Hub');
      expect(parsed[0].repo.id, 'base');
      expect(parsed[0].repo.itemCount, 1);
      expect(parsed[0].items.first.providerId, 'base');
      expect(parsed[1].repo.name, 'Manga Vault');
      expect(parsed[1].repo.id, 'base-2');
      expect(parsed[1].repo.itemCount, 2);
      expect(parsed[1].items.first.providerId, 'base-2');
      // All siblings share the source URL.
      expect(parsed[0].repo.sourceUrl, parsed[1].repo.sourceUrl);
    });

    test('top-level array parses: one repo per catalog', () {
      final parsed = parseOnlyService().parseRepoDocuments(
        arrayJson([
          catalogJson(name: 'Anime Hub'),
          catalogJson(name: 'Manga Vault'),
          catalogJson(name: 'Movie Den'),
        ]),
        providerIdBase: 'base',
        sourceUrl: 'https://example.com/catalog.json',
      );
      expect(parsed, hasLength(3));
      expect(
        parsed.map((p) => p.repo.id),
        ['base', 'base-2', 'base-3'],
      );
      expect(
        parsed.map((p) => p.repo.name),
        ['Anime Hub', 'Manga Vault', 'Movie Den'],
      );
    });

    test('single-element array / providers list keeps the base id', () {
      final fromArray = parseOnlyService().parseRepoDocuments(
        arrayJson([catalogJson(name: 'Only One')]),
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(fromArray, hasLength(1));
      expect(fromArray.first.repo.id, 'base');

      final fromObject = parseOnlyService().parseRepoDocuments(
        providersObjectJson([catalogJson(name: 'Only One')]),
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(fromObject, hasLength(1));
      expect(fromObject.first.repo.id, 'base');
    });

    test('single-catalog object is backward compatible', () {
      const raw = '{"name": "Catalog A", "items": []}';
      final viaMulti = parseOnlyService().parseRepoDocuments(
        raw,
        providerIdBase: 'base',
        sourceUrl: 'https://example.com/catalog.json',
      );
      final viaSingle = parseOnlyService().parseRepoDocument(
        raw,
        providerId: 'base',
        sourceUrl: 'https://example.com/catalog.json',
      );
      expect(viaMulti, hasLength(1));
      expect(viaMulti.first.repo.id, viaSingle.repo.id);
      expect(viaMulti.first.repo.name, viaSingle.repo.name);
      expect(viaMulti.first.repo.itemCount, viaSingle.repo.itemCount);
      expect(viaMulti.first.items, isEmpty);
    });

    test('one bad catalog among good ones: error names it', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          providersObjectJson([
            catalogJson(name: 'Good One'),
            catalogJson(includeName: false),
            catalogJson(name: 'Good Two'),
          ]),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Provider #2'),
              contains('missing a "name"'),
            ),
          ),
        ),
      );
    });

    test('bad item in catalog #2: error names the catalog and the item', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          providersObjectJson([
            catalogJson(name: 'Anime Hub'),
            catalogJson(
              name: 'Manga Vault',
              items: [itemJson(id: 'bad-1', type: 'series')],
            ),
          ]),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Provider #2 ("Manga Vault")'),
              contains('unknown type "series"'),
            ),
          ),
        ),
      );
    });

    test('non-object catalog element errors with its number', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          jsonEncode([
            catalogJson(name: 'Anime Hub'),
            'not a catalog',
          ]),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('Provider #2 is not an object'),
          ),
        ),
      );
    });

    test('duplicate catalog names get distinct ids', () {
      final parsed = parseOnlyService().parseRepoDocuments(
        providersObjectJson([
          catalogJson(name: 'Same Name'),
          catalogJson(name: 'Same Name'),
        ]),
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(parsed, hasLength(2));
      expect(parsed[0].repo.id, isNot(parsed[1].repo.id));
    });

    test('item ids only need to be unique within their catalog', () {
      final parsed = parseOnlyService().parseRepoDocuments(
        providersObjectJson([
          catalogJson(name: 'A', items: [itemJson(id: 'show-1')]),
          catalogJson(name: 'B', items: [itemJson(id: 'show-1')]),
        ]),
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(parsed, hasLength(2));
      expect(parsed[0].items.first.id, 'show-1');
      expect(parsed[1].items.first.id, 'show-1');
      expect(
        parsed[0].items.first.boxKey,
        isNot(parsed[1].items.first.boxKey),
      );
    });

    test('empty array errors', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          '[]',
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('empty list'),
          ),
        ),
      );
    });

    test('empty providers list errors', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          '{"providers": []}',
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"providers" list is empty'),
          ),
        ),
      );
    });

    test('providers not a list errors', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          '{"providers": {"name": "Nope"}}',
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"providers"'),
          ),
        ),
      );
    });

    test('object with neither name/items nor providers errors', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          '{"foo": "bar"}',
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('"name" and "items"'),
          ),
        ),
      );
    });

    test('51 catalogs exceeds the per-file cap', () {
      final catalogs = [
        for (var i = 0; i < 51; i++) catalogJson(name: 'Catalog $i'),
      ];
      expect(
        () => parseOnlyService().parseRepoDocuments(
          providersObjectJson(catalogs),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('50 providers per file'),
          ),
        ),
      );
    });

    test('extension-index array is rejected with a clear message', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          jsonEncode([
            {
              'name': 'Some Extension',
              'pkg': 'eu.kanade.tachiyomi.extension.en.example',
              'apk': 'example-v1.apk',
              'version': '1.0.0',
              'lang': 'en',
              'code': 1,
            },
          ]),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('extension index'),
              contains('JSON catalog'),
            ),
          ),
        ),
      );
    });

    test('extension-index object is rejected with a clear message', () {
      expect(
        () => parseOnlyService().parseRepoDocuments(
          jsonEncode({
            'extensions': [
              {'name': 'X', 'pkg': 'com.example.x', 'apk': 'x.apk'},
            ],
          }),
          providerIdBase: 'base',
          sourceUrl: '',
        ),
        throwsA(
          isA<RepoException>().having(
            (e) => e.message,
            'message',
            contains('extension index'),
          ),
        ),
      );
    });

    test('UTF-8 BOM is tolerated (single + multi)', () {
      const bom = '\uFEFF';
      final single = parseOnlyService().parseRepoDocuments(
        '$bom${singleJson()}',
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(single, hasLength(1));
      expect(single.first.repo.name, 'Catalog A');

      final multi = parseOnlyService().parseRepoDocuments(
        '$bom${providersObjectJson([
          catalogJson(name: 'A'),
          catalogJson(name: 'B'),
        ])}',
        providerIdBase: 'base',
        sourceUrl: '',
      );
      expect(multi, hasLength(2));
    });
  });

  group('fetchRepos / addReposFromJson', () {
    const url = 'https://example.com/catalog.json';

    String twoCatalogsJson() => providersObjectJson([
          catalogJson(name: 'Anime Hub'),
          catalogJson(
            name: 'Manga Vault',
            items: [itemJson(id: 'm-1', title: 'Manga One', type: 'manga')],
          ),
        ]);

    test('fetchRepos persists every catalog + its items', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      final repos = await service.fetchRepos(url);
      expect(repos, hasLength(2));
      expect(repos.map((r) => r.name), ['Anime Hub', 'Manga Vault']);
      expect(repos[0].itemCount, 1);
      expect(repos[1].itemCount, 1);
      expect(reposBox.length, 2);
      expect(catalogBox.length, 2);
      expect(
        catalogBox.get('${repos[0].id}::show-1')?.title,
        'Test Show',
      );
      expect(
        catalogBox.get('${repos[1].id}::m-1')?.title,
        'Manga One',
      );
      // Both repos are enabled, so their items show up in search/home.
      expect(service.searchItems('manga one'), hasLength(1));
      expect(service.itemsByType(ContentType.manga), hasLength(1));
    });

    test('fetchRepo wrapper returns the first repo but persists all', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      final first = await service.fetchRepo(url);
      expect(first.name, 'Anime Hub');
      expect(reposBox.length, 2);
      expect(catalogBox.length, 2);
    });

    test('re-fetch with fewer catalogs removes the stale sibling', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      await service.fetchRepos(url);
      expect(reposBox.length, 2);
      expect(catalogBox.length, 2);

      // The file now holds only Anime Hub.
      final v2Service = serviceWithClient(
        MockClient(
          (_) async => http.Response(singleJson(name: 'Anime Hub'), 200),
        ),
      );
      final repos = await v2Service.fetchRepos(url);
      expect(repos, hasLength(1));
      expect(repos.first.name, 'Anime Hub');
      expect(reposBox.length, 1);
      expect(catalogBox.length, 1);
      expect(
        catalogBox.values.where((i) => i.id == 'm-1'),
        isEmpty,
      );
    });

    test('single-to-multi keeps the first catalog id', () async {
      final v1Service = serviceWithClient(
        MockClient((_) async => http.Response(singleJson(), 200)),
      );
      final v1 = await v1Service.fetchRepos(url);
      final originalId = v1.first.id;

      final v2Service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      final v2 = await v2Service.fetchRepos(url);
      expect(v2, hasLength(2));
      expect(v2.first.id, originalId);
      // The original item key is unchanged (library/history survive).
      expect(catalogBox.get('$originalId::show-1'), isNotNull);
    });

    test('addReposFromJson persists every catalog; re-paste updates in place',
        () async {
      final service = parseOnlyService();
      final repos = await service.addReposFromJson(twoCatalogsJson());
      expect(repos, hasLength(2));
      expect(repos[0].sourceUrl, startsWith('pasted://'));
      expect(repos[0].sourceUrl, repos[1].sourceUrl);
      expect(reposBox.length, 2);
      expect(catalogBox.length, 2);

      // Pasting the same JSON again updates in place — no duplicate rows.
      final again = await service.addReposFromJson(twoCatalogsJson());
      expect(again.map((r) => r.id), repos.map((r) => r.id));
      expect(reposBox.length, 2);
      expect(catalogBox.length, 2);
    });

    test('addRepoFromJson wrapper returns the first repo, persists all',
        () async {
      final repo = await parseOnlyService().addRepoFromJson(twoCatalogsJson());
      expect(repo.name, 'Anime Hub');
      expect(reposBox.length, 2);
    });

    test('validateRepo returns true for a multi-catalog URL', () async {
      final service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      expect(await service.validateRepo(url), isTrue);
      expect(reposBox.isEmpty, isTrue);
    });

    test('refreshRepo on one sibling refreshes all siblings', () async {
      final v1Service = serviceWithClient(
        MockClient((_) async => http.Response(twoCatalogsJson(), 200)),
      );
      final repos = await v1Service.fetchRepos(url);
      expect(reposBox.length, 2);

      // v2: both catalogs gain a second item.
      final v2Json = providersObjectJson([
        catalogJson(
          name: 'Anime Hub',
          items: [
            itemJson(id: 'show-1'),
            itemJson(id: 'show-2', title: 'Second Show'),
          ],
        ),
        catalogJson(
          name: 'Manga Vault',
          items: [
            itemJson(id: 'm-1', title: 'Manga One', type: 'manga'),
            itemJson(id: 'm-2', title: 'Manga Two', type: 'manga'),
          ],
        ),
      ]);
      final v2Service = serviceWithClient(
        MockClient((_) async => http.Response(v2Json, 200)),
      );
      await v2Service.refreshRepo(repos.first);
      expect(reposBox.get(repos[0].id)?.itemCount, 2);
      expect(reposBox.get(repos[1].id)?.itemCount, 2);
      expect(catalogBox.length, 4);
    });

    test('refreshAll fetches each distinct URL once', () async {
      var fetchCount = 0;
      final service = serviceWithClient(
        MockClient((_) async {
          fetchCount++;
          return http.Response(twoCatalogsJson(), 200);
        }),
      );
      await service.fetchRepos(url);
      expect(reposBox.length, 2);
      fetchCount = 0;

      await service.refreshAll();
      // Two sibling repos, one file: one HTTP fetch, not two.
      expect(fetchCount, 1);
    });

    test('deleting one sibling leaves the other intact', () async {
      final service = parseOnlyService();
      final repos = await service.addReposFromJson(twoCatalogsJson());
      await service.deleteRepo(repos[1].id);
      expect(reposBox.length, 1);
      expect(reposBox.get(repos[0].id), isNotNull);
      expect(catalogBox.length, 1);
      expect(service.itemsForRepo(repos[0].id), hasLength(1));
    });

    test('toggling one sibling hides only its items', () async {
      final service = parseOnlyService();
      final repos = await service.addReposFromJson(twoCatalogsJson());
      await service.toggleRepo(repos[1].id, false);
      expect(service.searchItems('manga one'), isEmpty);
      expect(service.searchItems('test show'), hasLength(1));
    });
  });
}
