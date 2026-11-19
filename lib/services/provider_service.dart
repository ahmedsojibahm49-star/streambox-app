import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../data/sample_provider.dart';
import '../models/models.dart';
import 'storage.dart';

/// User-facing provider error. [message] is a specific, human-readable
/// explanation shown directly in the UI (SnackBar / error state) — never a
/// raw stack trace or a bare HTTP code.
class RepoException implements Exception {
  RepoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of parsing one repo JSON document: the repo row plus its items.
class ParsedRepo {
  ParsedRepo({required this.repo, required this.items});

  final ProviderRepo repo;
  final List<ProviderItem> items;
}

/// Provider-catalog service. Providers are JSON catalogs ONLY: one JSON
/// file per repo, fetched over HTTP(S), parsed into [ProviderItem]s and
/// cached in the `catalog` box. NO binary index files, NO extension APKs, NO
/// scraping, NO video-URL extraction. See CONTRACT.md hard boundaries.
///
/// Implemented by the PROVIDERS-DATA workstream (real Hive + http impl).
abstract class ProviderService {
  /// Fetch + parse a repo JSON from [sourceUrl] and cache its items.
  /// Returns the repo row (created or updated). Throws [RepoException]
  /// with a user-facing message on network/timeout/HTTP/validation errors.
  Future<ProviderRepo> fetchRepo(String sourceUrl);

  /// Parse raw repo JSON into items for [providerId]. Pure — no I/O.
  /// Throws [RepoException] when the JSON is not a valid catalog.
  List<ProviderItem> parseRepo(String rawJson, String providerId);

  /// Parse raw repo JSON into a repo row + items. Pure — no I/O.
  /// The repo row carries [providerId]/[sourceUrl]; callers persist it.
  /// Throws [RepoException] with a specific message on any invalid field.
  ParsedRepo parseRepoDocument(
    String rawJson, {
    required String providerId,
    required String sourceUrl,
  });

  /// True when [sourceUrl] fetches and parses as a valid catalog.
  /// Does NOT persist anything.
  Future<bool> validateRepo(String sourceUrl);

  /// Re-fetch one repo and update its cached items + [ProviderRepo] row.
  /// Built-in repos re-seed from the bundled sample data; pasted repos
  /// cannot be refreshed (throws [RepoException]).
  Future<void> refreshRepo(ProviderRepo repo);

  /// Re-fetch every enabled repo. Throws [RepoException] naming the repos
  /// that failed, after attempting all of them.
  Future<void> refreshAll();

  /// Add a repo from pasted JSON text (no URL). The repo is stored with a
  /// `pasted://` source URL and cannot be refreshed later.
  Future<ProviderRepo> addRepoFromJson(String rawJson);

  /// Delete a repo and all its cached items. The built-in sample catalog
  /// cannot be deleted (throws [RepoException]).
  Future<void> deleteRepo(String repoId);

  /// Enable/disable a repo. Disabled repos are skipped by search/home;
  /// their items stay cached.
  Future<void> toggleRepo(String repoId, bool enabled);

  /// All repos, built-in first, then by name.
  List<ProviderRepo> listRepos();

  /// One repo by id, or null.
  ProviderRepo? repoById(String repoId);

  /// Cached items belonging to one repo.
  List<ProviderItem> itemsForRepo(String repoId);

  /// Insert the built-in sample catalog (repo + items) if it is missing.
  /// Safe to call repeatedly; preserves the enabled flag if already present.
  Future<void> seedBuiltIn();

  /// Search cached catalog items across enabled repos.
  List<ProviderItem> searchItems(String query, {ContentType? type});

  /// All cached items of [type] from enabled repos, newest first.
  List<ProviderItem> itemsByType(ContentType type);
}

/// Hive + http implementation of [ProviderService].
class HiveProviderService implements ProviderService {
  HiveProviderService(
    this._reposBox,
    this._catalogBox, {
    http.Client? httpClient,
    this.fetchTimeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client();

  final Box<ProviderRepo> _reposBox;
  final Box<ProviderItem> _catalogBox;
  final http.Client _httpClient;

  /// HTTP fetch timeout (15s in the app; injectable for tests).
  final Duration fetchTimeout;

  /// Max repo file size (5 MB).
  static const int maxRepoBytes = 5 * 1024 * 1024;

  /// Max items per repo.
  static const int maxItemsPerRepo = 1000;

  /// Max episodes/chapters per item.
  static const int maxEpisodesPerItem = 1000;

  // -- Fetch ---------------------------------------------------------------

  @override
  Future<ProviderRepo> fetchRepo(String sourceUrl) async {
    final url = sourceUrl.trim();
    _validateRepoUrl(url);
    final rawJson = await _fetchRawJson(url);
    final parsed = parseRepoDocument(
      rawJson,
      providerId: _repoIdForUrl(url),
      sourceUrl: url,
    );
    await _persistParsed(parsed, rawJson);
    return parsed.repo;
  }

  @override
  Future<bool> validateRepo(String sourceUrl) async {
    try {
      final url = sourceUrl.trim();
      _validateRepoUrl(url);
      final rawJson = await _fetchRawJson(url);
      parseRepoDocument(
        rawJson,
        providerId: _repoIdForUrl(url),
        sourceUrl: url,
      );
      return true;
    } on RepoException {
      return false;
    }
  }

  /// Download the raw repo JSON. Throws [RepoException] with an exact,
  /// user-facing message for network / timeout / non-200 / oversize errors.
  ///
  /// STREAMED (audit fix, Nov 19): the old code used `_httpClient.get()`,
  /// which downloads the ENTIRE body before the 5 MB size check ran — a
  /// hostile or misconfigured host serving a 500 MB file would OOM the
  /// app before the check ever fired. The body is now read chunk by
  /// chunk and aborted the moment it exceeds [maxRepoBytes].
  Future<String> _fetchRawJson(String url) async {
    http.StreamedResponse streamed;
    try {
      final request = http.Request('GET', Uri.parse(url));
      streamed =
          await _httpClient.send(request).timeout(fetchTimeout);
    } on TimeoutException {
      throw RepoException(
        'The request timed out after ${fetchTimeout.inSeconds} seconds. '
        'Check your connection and try again.',
      );
    } on SocketException {
      throw RepoException(
        'Could not reach the server. Check your connection and the URL, '
        'then try again.',
      );
    } on http.ClientException {
      throw RepoException(
        'Could not reach the server. Check your connection and the URL, '
        'then try again.',
      );
    } on HttpException {
      throw RepoException(
        'Could not reach the server. Check your connection and the URL, '
        'then try again.',
      );
    } on Exception {
      throw RepoException(
        'Could not reach the server. Check your connection and the URL, '
        'then try again.',
      );
    }
    if (streamed.statusCode != 200) {
      throw RepoException(
        'The server returned HTTP ${streamed.statusCode} for this URL. '
        'Check the link and try again.',
      );
    }
    final bodyBytes = await _readCappedBody(streamed.stream);
    try {
      return utf8.decode(bodyBytes);
    } on FormatException {
      throw RepoException(
        'This file is not valid UTF-8 text. Save the repo JSON as UTF-8 '
        'and try again.',
      );
    }
  }

  /// Read a response body, aborting as soon as it exceeds [maxRepoBytes]
  /// so an oversized file never sits fully in memory. The read itself is
  /// bounded by [fetchTimeout] (a stalled body must not hang forever).
  Future<List<int>> _readCappedBody(Stream<List<int>> stream) async {
    final bytes = <int>[];
    try {
      await for (final chunk in stream.timeout(fetchTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxRepoBytes) {
          final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
          throw RepoException(
            'This repo file is too large ($mb MB). Repos must be under '
            '5 MB.',
          );
        }
      }
    } on RepoException {
      rethrow;
    } on TimeoutException {
      throw RepoException(
        'The request timed out after ${fetchTimeout.inSeconds} seconds. '
        'Check your connection and try again.',
      );
    }
    return bytes;
  }

  // -- Parse ---------------------------------------------------------------

  @override
  List<ProviderItem> parseRepo(String rawJson, String providerId) =>
      parseRepoDocument(
        rawJson,
        providerId: providerId,
        sourceUrl: '',
      ).items;

  @override
  ParsedRepo parseRepoDocument(
    String rawJson, {
    required String providerId,
    required String sourceUrl,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      throw RepoException(
        'This file is not valid JSON (${e.message}). '
        'Check the file for missing commas or brackets and try again.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw RepoException(
        'The repo file must be a JSON object with "name" and "items" — '
        'for example {"name": "My Catalog", "items": [...]}.',
      );
    }

    final name = decoded['name'];
    if (name is! String || name.trim().isEmpty) {
      throw RepoException(
        'This repo is missing a "name". Add a name at the top of the file, '
        'for example "name": "My Catalog".',
      );
    }
    if (name.length > 100) {
      throw RepoException(
        'The repo name is too long (${name.length} characters). '
        'Keep it under 100 characters.',
      );
    }

    if (!decoded.containsKey('items')) {
      throw RepoException(
        'This repo has no "items" list. Add "items": [...] with at least '
        'one title.',
      );
    }
    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw RepoException(
        'The "items" field must be a list of titles, for example '
        '"items": [{"id": "show-1", "type": "anime", "title": "..."}].',
      );
    }
    if (rawItems.length > maxItemsPerRepo) {
      throw RepoException(
        'This repo has ${rawItems.length} items, but the limit is '
        '$maxItemsPerRepo items per repo.',
      );
    }

    final seenIds = <String>{};
    final items = <ProviderItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final rawItem = rawItems[i];
      if (rawItem is! Map<String, dynamic>) {
        throw RepoException(
          'Item #${i + 1} is not an object. Each item must look like '
          '{"id": "...", "type": "anime", "title": "..."}.',
        );
      }
      items.add(_parseItem(rawItem, i, providerId, seenIds));
    }

    final repo = ProviderRepo(
      id: providerId,
      name: name.trim(),
      sourceUrl: sourceUrl,
      itemCount: items.length,
      lastFetchedAt: DateTime.now(),
    );
    return ParsedRepo(repo: repo, items: items);
  }

  ProviderItem _parseItem(
    Map<String, dynamic> map,
    int index,
    String providerId,
    Set<String> seenIds,
  ) {
    final id = map['id'];
    if (id is! String || id.trim().isEmpty) {
      throw RepoException(
        'Item #${index + 1} is missing an "id". Every item needs a unique '
        'id, for example "id": "show-1".',
      );
    }
    if (!seenIds.add(id)) {
      throw RepoException(
        'Two items share the id "$id". Item ids must be unique within a repo.',
      );
    }

    final title = map['title'];
    if (title is! String || title.trim().isEmpty) {
      throw RepoException(
        'Item "$id" is missing a "title". Every item needs a title.',
      );
    }

    final typeRaw = map['type'];
    if (typeRaw is! String || typeRaw.isEmpty) {
      throw RepoException(
        'Item "$id" is missing a "type". Use one of: '
        'anime, movie, manga, manhwa.',
      );
    }
    final type = switch (typeRaw) {
      'anime' => ContentType.anime,
      'movie' => ContentType.movie,
      'manga' => ContentType.manga,
      'manhwa' => ContentType.manhwa,
      _ => throw RepoException(
          'Item "$id" has an unknown type "$typeRaw". Use one of: '
          'anime, movie, manga, manhwa.',
        ),
    };

    final year = map['year'];
    if (year != null && year is! int) {
      throw RepoException(
        'Item "$id" has an invalid "year" — use a whole number like 2025.',
      );
    }
    final rating = map['rating'];
    if (rating != null && (rating is! num || rating < 0 || rating > 10)) {
      throw RepoException(
        'Item "$id" has an invalid "rating" — use a number from 0 to 10.',
      );
    }
    final genres = map['genres'];
    if (genres != null &&
        (genres is! List || genres.any((g) => g is! String))) {
      throw RepoException(
        'Item "$id" has an invalid "genres" list — use an array of text, '
        'for example ["Action", "Drama"].',
      );
    }
    for (final field in ['posterUrl', 'backdropUrl', 'overview', 'status']) {
      if (map[field] != null && map[field] is! String) {
        throw RepoException(
          'Item "$id" has an invalid "$field" — it must be text.',
        );
      }
    }

    final episodes = _parseEpisodes(map['episodes'], id);
    final chapters = _parseChapters(map['chapters'], id);

    return ProviderItem(
      id: id,
      providerId: providerId,
      type: type,
      title: title.trim(),
      posterUrl: map['posterUrl'] as String?,
      backdropUrl: map['backdropUrl'] as String?,
      year: year as int?,
      rating: (rating as num?)?.toDouble(),
      genres: (genres as List?)?.cast<String>() ?? const [],
      overview: map['overview'] as String?,
      status: map['status'] as String?,
      episodesJson: episodes == null ? null : jsonEncode(episodes),
      chaptersJson: chapters == null ? null : jsonEncode(chapters),
    );
  }

  List<Map<String, dynamic>>? _parseEpisodes(Object? raw, String itemId) {
    if (raw == null) return null;
    if (raw is! List) {
      throw RepoException(
        'Item "$itemId" has an invalid "episodes" field — it must be a list.',
      );
    }
    if (raw.length > maxEpisodesPerItem) {
      throw RepoException(
        'Item "$itemId" has ${raw.length} episodes, but the limit is '
        '$maxEpisodesPerItem episodes per item.',
      );
    }
    final episodes = <Map<String, dynamic>>[];
    for (var j = 0; j < raw.length; j++) {
      final ep = raw[j];
      if (ep is! Map<String, dynamic>) {
        throw RepoException(
          'Item "$itemId", episode #${j + 1} is not an object. Each episode '
          'must look like {"number": 1, "title": "...", "videoUrl": "..."}.',
        );
      }
      final number = ep['number'];
      if (number is! int) {
        throw RepoException(
          'Item "$itemId", episode #${j + 1} is missing a "number". Every '
          'episode needs a whole-number episode number.',
        );
      }
      if (ep['title'] != null && ep['title'] is! String) {
        throw RepoException(
          'Item "$itemId", episode $number has an invalid "title" — it must '
          'be text.',
        );
      }
      if (ep['videoUrl'] != null && ep['videoUrl'] is! String) {
        throw RepoException(
          'Item "$itemId", episode $number has an invalid "videoUrl" — it '
          'must be a video URL string.',
        );
      }
      // `youtubeId` is a first-class source (the player embeds it) — it
      // must be validated AND preserved. Audit fix, Nov 19: the parser
      // used to rebuild the episode map without this field, so a repo
      // using youtubeId silently lost every video (the player saw "no
      // source" for episodes that had one).
      if (ep['youtubeId'] != null && ep['youtubeId'] is! String) {
        throw RepoException(
          'Item "$itemId", episode $number has an invalid "youtubeId" — '
          'it must be a YouTube video id string, for example '
          '"dQw4w9WgXcQ".',
        );
      }
      final duration = ep['durationSeconds'];
      if (duration != null && duration is! int) {
        throw RepoException(
          'Item "$itemId", episode $number has an invalid '
          '"durationSeconds" — use a whole number of seconds.',
        );
      }
      episodes.add({
        'number': number,
        if (ep['title'] != null) 'title': ep['title'],
        if (ep['videoUrl'] != null) 'videoUrl': ep['videoUrl'],
        if (ep['youtubeId'] != null) 'youtubeId': ep['youtubeId'],
        'durationSeconds': ?duration,
      });
    }
    return episodes;
  }

  List<Map<String, dynamic>>? _parseChapters(Object? raw, String itemId) {
    if (raw == null) return null;
    if (raw is! List) {
      throw RepoException(
        'Item "$itemId" has an invalid "chapters" field — it must be a list.',
      );
    }
    if (raw.length > maxEpisodesPerItem) {
      throw RepoException(
        'Item "$itemId" has ${raw.length} chapters, but the limit is '
        '$maxEpisodesPerItem chapters per item.',
      );
    }
    final chapters = <Map<String, dynamic>>[];
    for (var j = 0; j < raw.length; j++) {
      final ch = raw[j];
      if (ch is! Map<String, dynamic>) {
        throw RepoException(
          'Item "$itemId", chapter #${j + 1} is not an object. Each chapter '
          'must look like {"number": 1, "title": "...", "pageUrls": [...]}.',
        );
      }
      final number = ch['number'];
      if (number is! int) {
        throw RepoException(
          'Item "$itemId", chapter #${j + 1} is missing a "number". Every '
          'chapter needs a whole-number chapter number.',
        );
      }
      if (ch['title'] != null && ch['title'] is! String) {
        throw RepoException(
          'Item "$itemId", chapter $number has an invalid "title" — it must '
          'be text.',
        );
      }
      final pages = ch['pageUrls'];
      if (pages != null &&
          (pages is! List || pages.any((p) => p is! String))) {
        throw RepoException(
          'Item "$itemId", chapter $number has an invalid "pageUrls" list — '
          'use an array of image URLs.',
        );
      }
      chapters.add({
        'number': number,
        if (ch['title'] != null) 'title': ch['title'],
        'pageUrls': ?(pages as List?)?.cast<String>(),
      });
    }
    return chapters;
  }

  // -- Repo management -----------------------------------------------------

  @override
  Future<ProviderRepo> addRepoFromJson(String rawJson) async {
    final digest = sha1.convert(utf8.encode(rawJson)).toString();
    final providerId = 'pasted-${digest.substring(0, 12)}';
    final parsed = parseRepoDocument(
      rawJson,
      providerId: providerId,
      sourceUrl: 'pasted://$providerId',
    );
    await _persistParsed(parsed, rawJson);
    return parsed.repo;
  }

  @override
  Future<void> deleteRepo(String repoId) async {
    final repo = _reposBox.get(repoId);
    if (repo == null) {
      throw RepoException('That provider no longer exists.');
    }
    if (repo.isBuiltIn) {
      throw RepoException(
        'The built-in sample catalog can’t be removed — but you can turn '
        'it off.',
      );
    }
    await _deleteItemsForRepo(repoId);
    await _reposBox.delete(repoId);
  }

  @override
  Future<void> toggleRepo(String repoId, bool enabled) async {
    final repo = _reposBox.get(repoId);
    if (repo == null) {
      throw RepoException('That provider no longer exists.');
    }
    repo.enabled = enabled;
    await repo.save();
  }

  @override
  List<ProviderRepo> listRepos() {
    final repos = _reposBox.values.toList();
    repos.sort((a, b) {
      if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return repos;
  }

  @override
  ProviderRepo? repoById(String repoId) => _reposBox.get(repoId);

  @override
  List<ProviderItem> itemsForRepo(String repoId) {
    final items = _catalogBox.values
        .where((item) => item.providerId == repoId)
        .toList();
    items.sort((a, b) => a.title.compareTo(b.title));
    return items;
  }

  @override
  Future<void> seedBuiltIn() async {
    final existing = _reposBox.get(sampleRepoId);
    final alreadySeeded = existing != null &&
        _catalogBox.values.any((i) => i.providerId == sampleRepoId);
    if (alreadySeeded) return;
    final parsed = parseRepoDocument(
      sampleRepoJsonString,
      providerId: sampleRepoId,
      sourceUrl: sampleRepoSourceUrl,
    );
    await _persistParsed(parsed, sampleRepoJsonString, isBuiltIn: true);
  }

  @override
  Future<void> refreshRepo(ProviderRepo repo) async {
    if (repo.isBuiltIn) {
      final parsed = parseRepoDocument(
        sampleRepoJsonString,
        providerId: sampleRepoId,
        sourceUrl: sampleRepoSourceUrl,
      );
      await _persistParsed(parsed, sampleRepoJsonString, isBuiltIn: true);
      return;
    }
    if (repo.sourceUrl.startsWith('pasted://')) {
      throw RepoException(
        '“${repo.name}” was added by pasting JSON, so it can’t be refreshed. '
        'Remove it and add it again with the new JSON.',
      );
    }
    await fetchRepo(repo.sourceUrl);
  }

  @override
  Future<void> refreshAll() async {
    final failed = <String>[];
    for (final repo in listRepos()) {
      if (!repo.enabled) continue;
      try {
        await refreshRepo(repo);
      } on RepoException {
        failed.add(repo.name);
      }
    }
    if (failed.isNotEmpty) {
      throw RepoException(
        'Couldn’t refresh ${failed.length} provider(s): ${failed.join(', ')}.',
      );
    }
  }

  // -- Queries -------------------------------------------------------------

  @override
  List<ProviderItem> searchItems(String query, {ContentType? type}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _enabledItems()
        .where((item) {
          if (type != null && item.type != type) return false;
          if (item.title.toLowerCase().contains(q)) return true;
          return item.genres.any((g) => g.toLowerCase().contains(q));
        })
        .toList(growable: false);
  }

  @override
  List<ProviderItem> itemsByType(ContentType type) {
    final items =
        _enabledItems().where((item) => item.type == type).toList();
    items.sort(_newestFirst);
    return items;
  }

  // -- Helpers -------------------------------------------------------------

  /// All cached items from enabled repos, newest first.
  List<ProviderItem> _enabledItems() {
    final enabledIds = {
      for (final repo in _reposBox.values.where((r) => r.enabled)) repo.id,
    };
    final items = _catalogBox.values
        .where((item) => enabledIds.contains(item.providerId))
        .toList();
    items.sort(_newestFirst);
    return items;
  }

  static int _newestFirst(ProviderItem a, ProviderItem b) {
    final yearCompare = (b.year ?? 0).compareTo(a.year ?? 0);
    if (yearCompare != 0) return yearCompare;
    return a.title.compareTo(b.title);
  }

  /// Persist a parsed repo: upsert the repo row (preserving the enabled
  /// flag and built-in marker) and REPLACE that repo's cached items.
  Future<void> _persistParsed(
    ParsedRepo parsed,
    String rawJson, {
    bool isBuiltIn = false,
  }) async {
    final existing = _reposBox.get(parsed.repo.id);
    final repo = parsed.repo
      ..enabled = existing?.enabled ?? true
      ..isBuiltIn = isBuiltIn || (existing?.isBuiltIn ?? false)
      ..rawJson = rawJson
      ..lastFetchedAt = DateTime.now()
      ..itemCount = parsed.items.length;
    await _reposBox.put(repo.id, repo);
    await _deleteItemsForRepo(repo.id);
    await _catalogBox.putAll({
      for (final item in parsed.items) item.boxKey: item,
    });
  }

  Future<void> _deleteItemsForRepo(String repoId) async {
    final keys = _catalogBox.keys
        .whereType<String>()
        .where((key) => key.startsWith('$repoId::'))
        .toList();
    if (keys.isNotEmpty) await _catalogBox.deleteAll(keys);
  }

  static void _validateRepoUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw RepoException(
        'Enter a valid http(s) URL for the repo JSON file.',
      );
    }
    if (!uri.path.toLowerCase().endsWith('.json')) {
      throw RepoException(
        'Provider URLs must end in .json — the repo is a single JSON file.',
      );
    }
  }

  static String _repoIdForUrl(String url) =>
      'repo-${sha1.convert(utf8.encode(url)).toString().substring(0, 16)}';
}

/// Service provider. Boxes must be open (main() opens them first).
final providerServiceProvider = Provider<ProviderService>((ref) {
  return HiveProviderService(
    Hive.box<ProviderRepo>(BoxNames.providers),
    Hive.box<ProviderItem>(BoxNames.catalog),
  );
});
