import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';
import 'storage.dart';

/// Hive-backed library state: My List, Favorites, watch/read history and
/// Continue Watching. FULLY IMPLEMENTED by setup — screens use the providers
/// below, they never touch the boxes directly.
///
/// Boxes are opened in main() via [initStorage] before runApp.
class LibraryService {
  LibraryService(this._libraryBox, this._historyBox);

  final Box<LibraryEntry> _libraryBox;
  final Box<HistoryEntry> _historyBox;

  // -- My List / Favorites -------------------------------------------------

  /// Entries in [list], newest saved first.
  List<LibraryEntry> entriesFor(LibraryList list) {
    final entries =
        _libraryBox.values.where((e) => e.list == list).toList();
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  bool isInList({
    required String itemId,
    required String providerId,
    required LibraryList list,
  }) =>
      _libraryBox.containsKey(
        '${list.name}::$providerId::$itemId',
      );

  Future<void> addToList({
    required String itemId,
    required String providerId,
    required LibraryList list,
  }) async {
    final entry = LibraryEntry(
      itemId: itemId,
      providerId: providerId,
      list: list,
      savedAt: DateTime.now(),
    );
    await _libraryBox.put(entry.boxKey, entry);
  }

  Future<void> removeFromList({
    required String itemId,
    required String providerId,
    required LibraryList list,
  }) async {
    await _libraryBox.delete('${list.name}::$providerId::$itemId');
  }

  /// Toggle membership; returns true when the item is now in the list.
  Future<bool> toggleList({
    required String itemId,
    required String providerId,
    required LibraryList list,
  }) async {
    if (isInList(itemId: itemId, providerId: providerId, list: list)) {
      await removeFromList(
        itemId: itemId,
        providerId: providerId,
        list: list,
      );
      return false;
    }
    await addToList(itemId: itemId, providerId: providerId, list: list);
    return true;
  }

  // -- History / Continue Watching -----------------------------------------

  /// History newest first, capped at [limit].
  List<HistoryEntry> recentHistory({int limit = 50}) {
    final entries = _historyBox.values.toList();
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.take(limit).toList();
  }

  /// Items with real progress (position > 0 or page > 0), newest first.
  /// Drives the Home "Continue watching / reading" rail.
  List<HistoryEntry> continueWatching({int limit = 10}) {
    final entries = _historyBox.values
        .where((e) => e.positionSeconds > 0 || e.page > 0)
        .toList();
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.take(limit).toList();
  }

  HistoryEntry? progressFor({
    required String itemId,
    required String providerId,
  }) =>
      _historyBox.get('$providerId::$itemId');

  /// Insert or update progress for an item. [episodeOrChapter] is the
  /// episode (video) or chapter (reader) number; [positionSeconds] is the
  /// video position, [page] the reader page.
  Future<void> recordProgress({
    required String itemId,
    required String providerId,
    required int episodeOrChapter,
    int positionSeconds = 0,
    int page = 0,
  }) async {
    final entry = HistoryEntry(
      itemId: itemId,
      providerId: providerId,
      episodeOrChapter: episodeOrChapter,
      positionSeconds: positionSeconds,
      page: page,
      updatedAt: DateTime.now(),
    );
    await _historyBox.put(entry.boxKey, entry);
  }

  Future<void> removeHistoryItem({
    required String itemId,
    required String providerId,
  }) async {
    await _historyBox.delete('$providerId::$itemId');
  }

  Future<void> clearHistory() async => _historyBox.clear();
}

/// Service provider. Boxes must be open (main() opens them first).
final libraryServiceProvider = Provider<LibraryService>((ref) {
  return LibraryService(
    Hive.box<LibraryEntry>(BoxNames.library),
    Hive.box<HistoryEntry>(BoxNames.history),
  );
});

/// My List entries, newest first.
final myListProvider =
    NotifierProvider<MyListNotifier, List<LibraryEntry>>(MyListNotifier.new);

class MyListNotifier extends Notifier<List<LibraryEntry>> {
  @override
  List<LibraryEntry> build() =>
      ref.read(libraryServiceProvider).entriesFor(LibraryList.myList);

  Future<bool> toggle(String itemId, String providerId) async {
    final service = ref.read(libraryServiceProvider);
    final added = await service.toggleList(
      itemId: itemId,
      providerId: providerId,
      list: LibraryList.myList,
    );
    if (!ref.mounted) return added;
    state = service.entriesFor(LibraryList.myList);
    return added;
  }
}

/// Favorites entries, newest first.
final favoritesProvider = NotifierProvider<FavoritesNotifier, List<LibraryEntry>>(
  FavoritesNotifier.new,
);

class FavoritesNotifier extends Notifier<List<LibraryEntry>> {
  @override
  List<LibraryEntry> build() =>
      ref.read(libraryServiceProvider).entriesFor(LibraryList.favorite);

  Future<bool> toggle(String itemId, String providerId) async {
    final service = ref.read(libraryServiceProvider);
    final added = await service.toggleList(
      itemId: itemId,
      providerId: providerId,
      list: LibraryList.favorite,
    );
    if (!ref.mounted) return added;
    state = service.entriesFor(LibraryList.favorite);
    return added;
  }
}

/// Watch/read history, newest first.
final historyProvider =
    NotifierProvider<HistoryNotifier, List<HistoryEntry>>(HistoryNotifier.new);

class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() =>
      ref.read(libraryServiceProvider).recentHistory();

  /// Record progress. BEST-EFFORT (audit fix, Nov 19): the player and
  /// reader call this fire-and-forget (`unawaited`) from timers and
  /// dispose(), so a Hive failure here used to surface as an unhandled
  /// async error. Progress must never break playback — a failed write is
  /// swallowed and the in-memory state is left untouched.
  Future<void> record({
    required String itemId,
    required String providerId,
    required int episodeOrChapter,
    int positionSeconds = 0,
    int page = 0,
  }) async {
    final service = ref.read(libraryServiceProvider);
    try {
      await service.recordProgress(
        itemId: itemId,
        providerId: providerId,
        episodeOrChapter: episodeOrChapter,
        positionSeconds: positionSeconds,
        page: page,
      );
    } catch (_) {
      return;
    }
    // The provider may have been disposed while the Hive write was in
    // flight (e.g. the player saving on dispose as its scope goes away).
    // Setting state on a disposed ref throws UnmountedRefException — an
    // unhandled async error. The write already landed; the state refresh
    // is pointless if nobody is listening.
    if (!ref.mounted) return;
    state = service.recentHistory();
  }

  Future<void> clear() async {
    final service = ref.read(libraryServiceProvider);
    await service.clearHistory();
    if (!ref.mounted) return;
    state = const [];
  }

  /// Remove one history entry (by item). Refreshes state so the Library
  /// and Continue Watching tabs update without an invalidate.
  Future<void> remove({
    required String itemId,
    required String providerId,
  }) async {
    final service = ref.read(libraryServiceProvider);
    await service.removeHistoryItem(itemId: itemId, providerId: providerId);
    if (!ref.mounted) return;
    state = service.recentHistory();
  }
}

/// Continue Watching rail items (progress > 0, newest first, max 10).
final continueWatchingProvider = Provider<List<HistoryEntry>>((ref) {
  ref.watch(historyProvider);
  return ref.read(libraryServiceProvider).continueWatching();
});

/// True when the item is in My List. Key: `(itemId, providerId)`.
final isInMyListProvider =
    Provider.family<bool, ({String itemId, String providerId})>((ref, key) {
  final list = ref.watch(myListProvider);
  return list.any(
    (e) => e.itemId == key.itemId && e.providerId == key.providerId,
  );
});

/// True when the item is a Favorite. Key: `(itemId, providerId)`.
final isFavoriteProvider =
    Provider.family<bool, ({String itemId, String providerId})>((ref, key) {
  final list = ref.watch(favoritesProvider);
  return list.any(
    (e) => e.itemId == key.itemId && e.providerId == key.providerId,
  );
});
