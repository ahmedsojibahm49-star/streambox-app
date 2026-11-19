import 'dart:convert';

import 'package:hive/hive.dart';

part 'provider_item.g.dart';

/// Content type of a catalog item. Stored as a Hive enum (typeId 6).
@HiveType(typeId: 6)
enum ContentType {
  @HiveField(0)
  anime,
  @HiveField(1)
  movie,
  @HiveField(2)
  manga,
  @HiveField(3)
  manhwa,
}

/// One catalog item from a provider repo (anime, movie, manga or manhwa).
///
/// Stored in the `catalog` box, keyed by `"$providerId::$id"`.
/// Episodes and chapters are JSON-encoded strings (see [episodesJson] /
/// [chaptersJson]) — the player/reader workstreams decode them with the
/// [episodes] / [chapters] getters. Each episode/chapter JSON object is a
/// plain map, e.g. `{"number": 1, "title": "...", "videoUrl": "...",
/// "durationSeconds": 1420}` or `{"number": 1, "title": "...",
/// "pageUrls": ["..."]}`.
@HiveType(typeId: 0)
class ProviderItem extends HiveObject {
  ProviderItem({
    required this.id,
    required this.providerId,
    required this.type,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.genres = const [],
    this.overview,
    this.status,
    this.episodesJson,
    this.chaptersJson,
  });

  /// Id unique within its provider (from the repo JSON).
  @HiveField(0)
  String id;

  /// Id of the [ProviderRepo] this item came from.
  @HiveField(1)
  String providerId;

  @HiveField(2)
  ContentType type;

  @HiveField(3)
  String title;

  /// Remote poster URL, or a bundled asset path (`assets/artwork/...`)
  /// for sample items.
  @HiveField(4)
  String? posterUrl;

  @HiveField(5)
  String? backdropUrl;

  @HiveField(6)
  int? year;

  /// 0–10 rating from the repo.
  @HiveField(7)
  double? rating;

  @HiveField(8)
  List<String> genres;

  @HiveField(9)
  String? overview;

  /// Free-form status from the repo, e.g. `ongoing`, `completed`.
  @HiveField(10)
  String? status;

  /// JSON-encoded list of episode maps (anime/movie). Null when none.
  @HiveField(11)
  String? episodesJson;

  /// JSON-encoded list of chapter maps (manga/manhwa). Null when none.
  @HiveField(12)
  String? chaptersJson;

  /// Decoded episode list. Empty when [episodesJson] is null or invalid.
  List<Map<String, dynamic>> get episodes => _decodeList(episodesJson);

  set episodes(List<Map<String, dynamic>> value) {
    episodesJson = jsonEncode(value);
  }

  /// Decoded chapter list. Empty when [chaptersJson] is null or invalid.
  List<Map<String, dynamic>> get chapters => _decodeList(chaptersJson);

  set chapters(List<Map<String, dynamic>> value) {
    chaptersJson = jsonEncode(value);
  }

  /// Box key for this item: `"$providerId::$id"`.
  String get boxKey => '$providerId::$id';

  static List<Map<String, dynamic>> _decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
