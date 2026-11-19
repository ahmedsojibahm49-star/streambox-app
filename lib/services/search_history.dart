import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Recent search queries, persisted locally in Hive.
///
/// Lives in its own lazily-opened box (`search_history`) so it does not
/// touch `lib/services/storage.dart` (shared file) or any model schema —
/// plain strings, no Hive adapter needed. Most recent first, capped at
/// [SearchHistory.maxEntries].
class SearchHistory {
  SearchHistory._();

  /// Box name for the recent-searches store. Kept here (not in BoxNames)
  /// because `storage.dart` is a shared file owned by the contract.
  static const String boxName = 'search_history';

  static const String _key = 'recent';
  static const int maxEntries = 10;

  static Future<Box<String>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  /// Stored queries, most recent first. Empty when nothing was searched.
  static Future<List<String>> load() async {
    try {
      final box = await _openBox();
      final raw = box.get(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Add [query] to the front (de-duplicated, case-insensitive) and
  /// return the updated list. Blank queries are ignored.
  static Future<List<String>> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();
    final current = await load();
    final updated = <String>[trimmed];
    for (final entry in current) {
      if (entry.toLowerCase() != trimmed.toLowerCase()) {
        updated.add(entry);
      }
      if (updated.length >= maxEntries) break;
    }
    try {
      final box = await _openBox();
      await box.put(_key, jsonEncode(updated));
    } catch (_) {
      // Persistence is best-effort — the in-memory list still updates.
    }
    return updated;
  }

  /// Remove every stored query.
  static Future<void> clear() async {
    try {
      final box = await _openBox();
      await box.delete(_key);
    } catch (_) {
      // Best-effort (see [add]).
    }
  }
}

/// Riverpod view over [SearchHistory]. Loads from disk on first build;
/// [add] / [clear] update both the box and the exposed state.
final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);

class SearchHistoryNotifier extends Notifier<List<String>> {
  bool _disposed = false;

  @override
  List<String> build() {
    ref.onDispose(() => _disposed = true);
    SearchHistory.load().then((loaded) {
      if (!_disposed) state = loaded;
    });
    return const [];
  }

  Future<void> add(String query) async {
    state = await SearchHistory.add(query);
  }

  Future<void> clear() async {
    await SearchHistory.clear();
    state = const [];
  }
}
