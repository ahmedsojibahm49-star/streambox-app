import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/sample_provider.dart';
import '../models/models.dart';
import '../services/provider_service.dart';
import '../services/storage.dart';

/// Catalog providers — the read API other workstreams consume. Screens and
/// the player/reader use these, never the Hive boxes directly.
///
///   - [providersListProvider]: all repos (built-in first), with actions to
///     add / delete / toggle / refresh.
///   - [allEnabledItemsProvider]: every item from every enabled repo.
///   - [itemsByTypeProvider]: enabled items of one [ContentType].
///   - [itemByIdProvider]: one item by box key `"$providerId::$itemId"`
///     (or by bare item id, searching all repos).
///
/// The built-in sample catalog is seeded lazily on first read of
/// [providersListProvider] (main.dart does not seed — seeding stays inside
/// the providers workstream).

/// All provider repos, built-in first, then by name. Owns all repo
/// mutations; every mutation refreshes the list (and therefore the catalog
/// providers below, which watch it).
final providersListProvider =
    NotifierProvider<ProvidersListNotifier, List<ProviderRepo>>(
  ProvidersListNotifier.new,
);

class ProvidersListNotifier extends Notifier<List<ProviderRepo>> {
  @override
  List<ProviderRepo> build() {
    final service = ref.read(providerServiceProvider);
    final repos = service.listRepos();
    // Lazy-seed the built-in sample catalog on first use.
    if (repos.every((repo) => repo.id != sampleRepoId)) {
      unawaited(_seedAndRefresh(service));
    }
    return repos;
  }

  Future<void> _seedAndRefresh(ProviderService service) async {
    try {
      await service.seedBuiltIn();
      state = service.listRepos();
    } on RepoException {
      // Seeding only fails if the bundled sample data is corrupt; the
      // list stays as-is and the providers screen shows the empty state.
    } catch (_) {
      // Same: a Hive failure during the lazy seed must never crash
      // startup (this runs unawaited from build()).
    }
  }

  void _refresh() => state = ref.read(providerServiceProvider).listRepos();

  /// Fetch a repo from [url], validate it and add it. Returns one repo per
  /// catalog in the file (a multi-catalog file adds several rows).
  /// Throws [RepoException] with a user-facing message on any failure.
  /// The list refresh runs after the persist, so the Providers screen and
  /// every catalog consumer (Home / Search / Manga, which watch
  /// [allEnabledItemsProvider] below) see the new items immediately, with
  /// no restart.
  Future<List<ProviderRepo>> addFromUrl(String url) async {
    final repos = await ref.read(providerServiceProvider).fetchRepos(url);
    _refresh();
    return repos;
  }

  /// Add repo(s) from pasted JSON text. Returns one repo per catalog in
  /// the pasted JSON. Throws [RepoException] on invalid JSON.
  Future<List<ProviderRepo>> addFromJson(String rawJson) async {
    final repos =
        await ref.read(providerServiceProvider).addReposFromJson(rawJson);
    _refresh();
    return repos;
  }

  /// Delete a repo and its cached items. Throws [RepoException] for the
  /// built-in catalog (it cannot be deleted).
  Future<void> delete(String repoId) async {
    await ref.read(providerServiceProvider).deleteRepo(repoId);
    _refresh();
  }

  /// Enable/disable a repo. Disabled repos are skipped by the catalog.
  Future<void> toggle(String repoId, bool enabled) async {
    await ref.read(providerServiceProvider).toggleRepo(repoId, enabled);
    _refresh();
  }

  /// Re-fetch one repo (built-in re-seeds from bundled data).
  Future<void> refresh(String repoId) async {
    final service = ref.read(providerServiceProvider);
    final repo = service.repoById(repoId);
    if (repo == null) {
      throw RepoException('That provider no longer exists.');
    }
    await service.refreshRepo(repo);
    _refresh();
  }

  /// Re-fetch every enabled repo. Throws [RepoException] naming failures.
  Future<void> refreshAll() async {
    await ref.read(providerServiceProvider).refreshAll();
    _refresh();
  }
}

/// Every cached item from every enabled repo, newest first.
/// Rebuilds whenever the repo list changes (add / delete / toggle / refresh).
final allEnabledItemsProvider = Provider<List<ProviderItem>>((ref) {
  final repos = ref.watch(providersListProvider);
  final enabledIds = {
    for (final repo in repos.where((repo) => repo.enabled)) repo.id,
  };
  final box = Hive.box<ProviderItem>(BoxNames.catalog);
  final items = box.values
      .where((item) => enabledIds.contains(item.providerId))
      .toList();
  items.sort((a, b) {
    final yearCompare = (b.year ?? 0).compareTo(a.year ?? 0);
    if (yearCompare != 0) return yearCompare;
    return a.title.compareTo(b.title);
  });
  return items;
});

/// Enabled items of one [ContentType], newest first.
/// Usage: `ref.watch(itemsByTypeProvider(ContentType.anime))`.
final itemsByTypeProvider =
    Provider.family<List<ProviderItem>, ContentType>((ref, type) {
  final items = ref.watch(allEnabledItemsProvider);
  return items
      .where((item) => item.type == type)
      .toList(growable: false);
});

/// One catalog item by id. [id] is normally the box key
/// `"$providerId::$itemId"` (the `:id` in `/details/:id`); a bare item id
/// (no `::`) matches the first item with that id across ALL repos, enabled
/// or not (so details/history still resolve a disabled repo's item).
/// Returns null when nothing matches.
/// Usage: `ref.watch(itemByIdProvider('sample::last-horizon'))`.
final itemByIdProvider =
    Provider.family<ProviderItem?, String>((ref, id) {
  // Rebuild when repos change (add / delete / refresh replaces items).
  ref.watch(providersListProvider);
  final box = Hive.box<ProviderItem>(BoxNames.catalog);
  final direct = box.get(id);
  if (direct != null) return direct;
  if (id.contains('::')) return null;
  for (final item in box.values) {
    if (item.id == id) return item;
  }
  return null;
});
