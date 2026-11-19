import 'package:hive/hive.dart';

part 'provider_repo.g.dart';

/// A provider source: a JSON catalog repo (remote URL or the built-in
/// sample catalog). Stored in the `providers` box, keyed by [id].
///
/// Providers are JSON catalogs ONLY — a repo is one JSON file at [sourceUrl]
/// describing a list of items. No extension APKs, no binary index files, no
/// scraping, no video-URL extraction. See CONTRACT.md hard boundaries.
@HiveType(typeId: 1)
class ProviderRepo extends HiveObject {
  ProviderRepo({
    required this.id,
    required this.name,
    required this.sourceUrl,
    this.isBuiltIn = false,
    this.enabled = true,
    this.itemCount = 0,
    this.lastFetchedAt,
    this.rawJson,
  });

  /// Stable id, e.g. `sample` for the built-in catalog.
  @HiveField(0)
  String id;

  /// Display name shown in Settings > Providers.
  @HiveField(1)
  String name;

  /// URL of the repo JSON file, or `asset://...` for the built-in sample.
  @HiveField(2)
  String sourceUrl;

  /// True for the built-in sample catalog (cannot be deleted).
  @HiveField(3)
  bool isBuiltIn;

  /// Disabled repos are skipped by search/home (items stay cached).
  @HiveField(4)
  bool enabled;

  /// Number of items parsed on the last successful fetch.
  @HiveField(5)
  int itemCount;

  @HiveField(6)
  DateTime? lastFetchedAt;

  /// Last fetched raw JSON, kept for offline use and debugging.
  @HiveField(7)
  String? rawJson;
}
