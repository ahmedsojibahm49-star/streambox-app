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
/// One JSON file may hold ONE catalog or SEVERAL (v1.0.4, multi-catalog):
///
///   - single catalog: `{"name": "...", "items": [...]}`
///   - multi-catalog object: `{"providers": [{"name": "...", "items": [...]},
///     {"name": "...", "items": [...]}]}`
///   - top-level array: `[{"name": "...", "items": [...]}, {...}]`
///
/// Each catalog becomes its OWN repo row (own id / name / items) that the
/// user can enable/disable/delete individually. A single-catalog file keeps
/// the exact repo id it always had, so library entries and history survive.
/// In a multi-catalog file the FIRST catalog keeps the base id and later
/// ones get `-2`, `-3`, … suffixes, so a file that grows from one catalog
/// to several keeps the first catalog's id too.
///
/// Implemented by the PROVIDERS-DATA workstream (real Hive + http impl).
abstract class ProviderService {
  /// Fetch + parse a repo JSON from [sourceUrl] and cache its items.
  /// Returns the repo row (created or updated). Throws [RepoException]
  /// with a user-facing message on network/timeout/HTTP/validation errors.
  ///
  /// Multi-catalog files persist EVERY catalog; this returns the first
  /// repo only. Prefer [fetchRepos] when the caller needs all of them.
  Future<ProviderRepo> fetchRepo(String sourceUrl);

  /// Fetch + parse a repo JSON from [sourceUrl] and cache its items.
  /// Returns one repo row per catalog in the file (one for a
  /// single-catalog file, several for a multi-catalog file). Catalogs
  /// that disappeared from the file since the last fetch are removed.
  /// Throws [RepoException] with a user-facing message on
  /// network/timeout/HTTP/validation errors.
  Future<List<ProviderRepo>> fetchRepos(String sourceUrl);

  /// Parse raw repo JSON into items for [providerId]. Pure — no I/O.
  /// Throws [RepoException] when the JSON is not a valid catalog.
  ///
  /// Single-catalog only (legacy signature); multi-catalog files must go
  /// through [parseRepoDocuments].
  List<ProviderItem> parseRepo(String rawJson, String providerId);

  /// Parse raw repo JSON into a repo row + items. Pure — no I/O.
  /// The repo row carries [providerId]/[sourceUrl]; callers persist it.
  /// Throws [RepoException] with a specific message on any invalid field.
  ///
  /// Single-catalog only (legacy signature); multi-catalog files must go
  /// through [parseRepoDocuments].
  ParsedRepo parseRepoDocument(
    String rawJson, {
    required String providerId,
    required String sourceUrl,
  });

  /// Parse raw repo JSON into one [ParsedRepo] per catalog in the file.
  /// Pure — no I/O. Accepts a single-catalog object, a
  /// `{"providers": [...]}` object, or a top-level array of catalog
  /// objects. Repo ids derive from [providerIdBase]: the first (or only)
  /// catalog keeps the base id, later ones get `-2`, `-3`, … suffixes.
  /// All repos share [sourceUrl]. Throws [RepoException] with a specific
  /// message on any invalid field; in a multi-catalog file the message
  /// names which catalog failed (e.g. `Provider #2 is missing a "name"`).
  List<ParsedRepo> parseRepoDocuments(
    String rawJson, {
    required String providerIdBase,
    required String sourceUrl,
  });

  /// True when [sourceUrl] fetches and parses as a valid catalog.
  /// Does NOT persist anything.
  Future<bool> validateRepo(String sourceUrl);

  /// Re-fetch one repo and update its cached items + [ProviderRepo] row.
  /// Built-in repos re-seed from the bundled sample data; pasted repos
  /// cannot be refreshed (throws [RepoException]). For a repo that came
  /// from a multi-catalog file, every catalog from that file is
  /// re-synced (siblings included) and catalogs removed from the file
  /// are dropped.
  Future<void> refreshRepo(ProviderRepo repo);

  /// Re-fetch every enabled repo. Each distinct source URL is fetched
  /// once (multi-catalog siblings share one fetch). Throws
  /// [RepoException] naming the repos that failed, after attempting all
  /// of them.
  Future<void> refreshAll();

  /// Add a repo from pasted JSON text (no URL). The repo is stored with a
  /// `pasted://` source URL and cannot be refreshed later.
  ///
  /// Multi-catalog input persists EVERY catalog; this returns the first
  /// repo only. Prefer [addReposFromJson] when the caller needs all of
  /// them.
  Future<ProviderRepo> addRepoFromJson(String rawJson);

  /// Add repo(s) from pasted JSON text (no URL). Returns one repo row per
  /// catalog in the pasted JSON. Repos are stored with a `pasted://`
  /// source URL and cannot be refreshed later.
  Future<List<ProviderRepo>> addReposFromJson(String rawJson);

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

  /// Max catalogs in one multi-catalog file.
  static const int maxCatalogsPerFile = 50;

  // -- Fetch ---------------------------------------------------------------

  @override
  Future<ProviderRepo> fetchRepo(String sourceUrl) async =>
      (await fetchRepos(sourceUrl)).first;

  @override
  Future<List<ProviderRepo>> fetchRepos(String sourceUrl) async {
    final url = sourceUrl.trim();
    _validateRepoUrl(url);
    final rawJson = await _fetchRawJson(url);
    final parsed = parseRepoDocuments(
      rawJson,
      providerIdBase: _repoIdForUrl(url),
      sourceUrl: url,
    );
    await _persistAll(parsed, rawJson, sourceUrl: url);
    return parsed.map((p) => p.repo).toList(growable: false);
  }

  @override
  Future<bool> validateRepo(String sourceUrl) async {
    try {
      final url = sourceUrl.trim();
      _validateRepoUrl(url);
      final rawJson = await _fetchRawJson(url);
      parseRepoDocuments(
        rawJson,
        providerIdBase: _repoIdForUrl(url),
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
    final decoded = _decodeJson(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw RepoException(
        'The repo file must be a JSON object with "name" and "items" — '
        'for example {"name": "My Catalog", "items": [...]}.',
      );
    }
    return _parseSingleCatalog(
      decoded,
      providerId: providerId,
      sourceUrl: sourceUrl,
    );
  }

  @override
  List<ParsedRepo> parseRepoDocuments(
    String rawJson, {
    required String providerIdBase,
    required String sourceUrl,
  }) {
    final decoded = _decodeJson(rawJson);
    final List<Object?> catalogs;
    if (decoded is List) {
      if (decoded.isEmpty) {
        throw RepoException(
          'This file is an empty list. Add at least one provider catalog, '
          'for example [{"name": "My Catalog", "items": [...]}].',
        );
      }
      _rejectExtensionIndex(decoded);
      if (decoded.length > maxCatalogsPerFile) {
        throw RepoException(
          'This file has ${decoded.length} providers, but the limit is '
          '$maxCatalogsPerFile providers per file.',
        );
      }
      catalogs = decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('providers')) {
        final providers = decoded['providers'];
        if (providers is! List) {
          throw RepoException(
            'The "providers" field must be a list of catalog objects, for '
            'example {"providers": [{"name": "My Catalog", "items": '
            '[...]}]}.',
          );
        }
        if (providers.isEmpty) {
          throw RepoException(
            'The "providers" list is empty. Add at least one provider '
            'catalog.',
          );
        }
        _rejectExtensionIndex(providers);
        if (providers.length > maxCatalogsPerFile) {
          throw RepoException(
            'This file has ${providers.length} providers, but the limit is '
            '$maxCatalogsPerFile providers per file.',
          );
        }
        catalogs = providers;
      } else if (decoded.containsKey('name') ||
          decoded.containsKey('items')) {
        // Single-catalog object.
        catalogs = [decoded];
      } else if (_looksLikeExtensionIndex(decoded)) {
        throw _extensionIndexException();
      } else {
        throw RepoException(
          'The repo file must be a JSON catalog with "name" and "items" — '
          'for example {"name": "My Catalog", "items": [...]} — or a '
          'multi-catalog file: {"providers": [{...}, {...}]} or a list of '
          'catalogs [{...}, {...}].',
        );
      }
    } else {
      throw RepoException(
        'The repo file must be a JSON catalog with "name" and "items" — '
        'for example {"name": "My Catalog", "items": [...]} — or a '
        'multi-catalog file: {"providers": [{...}, {...}]} or a list of '
        'catalogs [{...}, {...}].',
      );
    }

    final isMulti = catalogs.length > 1;
    final parsed = <ParsedRepo>[];
    for (var i = 0; i < catalogs.length; i++) {
      final n = i + 1;
      final rawCatalog = catalogs[i];
      if (rawCatalog is! Map<String, dynamic>) {
        if (isMulti) {
          throw RepoException(
            'Provider #$n is not an object. Each provider must look like '
            '{"name": "...", "items": [...]}.',
          );
        }
        throw RepoException(
          'The repo file must be a JSON object with "name" and "items" — '
          'for example {"name": "My Catalog", "items": [...]}.',
        );
      }
      // First (or only) catalog keeps the base id; later catalogs get
      // `-2`, `-3`, … so a file that grows from one catalog to several
      // keeps the first catalog's id (library/history survive).
      final providerId =
          i == 0 ? providerIdBase : '$providerIdBase-${i + 1}';
      if (!isMulti) {
        parsed.add(
          _parseSingleCatalog(
            rawCatalog,
            providerId: providerId,
            sourceUrl: sourceUrl,
          ),
        );
        continue;
      }
      // Multi-catalog: errors must name WHICH catalog failed.
      final name = rawCatalog['name'];
      if (name is! String || name.trim().isEmpty) {
        throw RepoException(
          'Provider #$n is missing a "name". Every provider in the file '
          'needs its own name, for example "name": "My Catalog".',
        );
      }
      final label = 'Provider #$n ("${name.trim()}")';
      try {
        parsed.add(
          _parseSingleCatalog(
            rawCatalog,
            providerId: providerId,
            sourceUrl: sourceUrl,
          ),
        );
      } on RepoException catch (e) {
        throw RepoException('$label: ${e.message}');
      }
    }
    return parsed;
  }

  /// Decode repo JSON, tolerating a leading UTF-8 byte-order mark.
  ///
  /// BOM FIX (v1.0.4): `jsonDecode` REJECTS a leading U+FEFF, and Windows
  /// Notepad saves UTF-8 files WITH a BOM by default — so a JSON file
  /// written or edited in Notepad failed with "not valid JSON" even
  /// though the JSON itself was fine. Strip it before decoding.
  static Object? _decodeJson(String rawJson) {
    var text = rawJson;
    while (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw RepoException(
        'This file is not valid JSON (${e.message}). '
        'Check the file for missing commas or brackets and try again.',
      );
    }
  }

  /// True when [node] carries extension-index markers (`pkg` / `apk` /
  /// `packageName` / `extensions` / `apps`) instead of catalog fields.
  /// Aniyomi-style extension indexes list app packages, not titles.
  static bool _looksLikeExtensionIndex(Map<String, dynamic> node) =>
      node.containsKey('pkg') ||
      node.containsKey('apk') ||
      node.containsKey('packageName') ||
      node.containsKey('extensions') ||
      node.containsKey('apps');

  /// Reject a list of catalogs when any entry looks like an extension
  /// index. Extension indexes are out of scope (hard boundary) — the
  /// error says so plainly instead of failing on a missing "items" list.
  static void _rejectExtensionIndex(List<Object?> catalogs) {
    for (final entry in catalogs) {
      if (entry is Map<String, dynamic> &&
          _looksLikeExtensionIndex(entry)) {
        throw _extensionIndexException();
      }
    }
  }

  static RepoException _extensionIndexException() => RepoException(
        'This file looks like an extension index — it lists app packages, '
        'not titles. StreamBox providers are JSON catalogs: each provider '
        'needs a "name" and an "items" list of titles. Extension files are '
        'not supported.',
      );

  /// Parse ONE catalog object into a repo row + items. Pure — no I/O.
  /// Shared by the single-catalog entry point ([parseRepoDocument]) and
  /// the multi-catalog parser ([parseRepoDocuments]); messages are the
  /// original single-catalog messages, and the multi-catalog parser
  /// prefixes them with `Provider #N ("Name"): ` when needed.
  ParsedRepo _parseSingleCatalog(
    Map<String, dynamic> decoded, {
    required String providerId,
    required String sourceUrl,
  }) {
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
  Future<ProviderRepo> addRepoFromJson(String rawJson) async =>
      (await addReposFromJson(rawJson)).first;

  @override
  Future<List<ProviderRepo>> addReposFromJson(String rawJson) async {
    final digest = sha1.convert(utf8.encode(rawJson)).toString();
    final baseId = 'pasted-${digest.substring(0, 12)}';
    // All catalogs from one paste share one source URL so re-pasting the
    // same JSON updates them in place and stale-sibling cleanup groups
    // them (same as a multi-catalog URL file).
    final sourceUrl = 'pasted://$baseId';
    final parsed = parseRepoDocuments(
      rawJson,
      providerIdBase: baseId,
      sourceUrl: sourceUrl,
    );
    await _persistAll(parsed, rawJson, sourceUrl: sourceUrl);
    return parsed.map((p) => p.repo).toList(growable: false);
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
    // fetchRepos re-syncs EVERY catalog from this URL, so refreshing one
    // sibling of a multi-catalog file refreshes them all (and drops
    // catalogs removed from the file).
    await fetchRepos(repo.sourceUrl);
  }

  @override
  Future<void> refreshAll() async {
    // Group by source URL: multi-catalog siblings share one file, so one
    // fetch refreshes them all. Fetching per repo would download the
    // same file once per sibling.
    final bySourceUrl = <String, List<ProviderRepo>>{};
    for (final repo in listRepos()) {
      if (!repo.enabled) continue;
      bySourceUrl.putIfAbsent(repo.sourceUrl, () => []).add(repo);
    }
    final failed = <String>[];
    for (final entry in bySourceUrl.entries) {
      try {
        await refreshRepo(entry.value.first);
      } on RepoException {
        failed.addAll(entry.value.map((repo) => repo.name));
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

  /// Persist every parsed catalog from one file, then drop any repo rows
  /// that came from the same [sourceUrl] but are no longer in the file
  /// (e.g. a catalog was removed, or the file changed shape from
  /// multi-catalog to single). Without the cleanup, a re-fetch would
  /// leave stale rows whose items no longer exist upstream.
  Future<void> _persistAll(
    List<ParsedRepo> parsed,
    String rawJson, {
    required String sourceUrl,
  }) async {
    for (final repo in parsed) {
      await _persistParsed(repo, rawJson);
    }
    final keepIds = {for (final repo in parsed) repo.repo.id};
    final stale = _reposBox.values
        .where(
          (repo) =>
              repo.sourceUrl == sourceUrl &&
              !keepIds.contains(repo.id) &&
              !repo.isBuiltIn,
        )
        .toList();
    for (final repo in stale) {
      await _deleteItemsForRepo(repo.id);
      await _reposBox.delete(repo.id);
    }
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
