import 'package:hive/hive.dart';

part 'history_entry.g.dart';

/// Watch/read progress for one item. Stored in the `history` box, keyed by
/// `"$providerId::$itemId"` (one row per item — the latest position wins).
@HiveType(typeId: 3)
class HistoryEntry extends HiveObject {
  HistoryEntry({
    required this.itemId,
    required this.providerId,
    required this.episodeOrChapter,
    this.positionSeconds = 0,
    this.page = 0,
    required this.updatedAt,
  });

  @HiveField(0)
  String itemId;

  @HiveField(1)
  String providerId;

  /// Episode number (video) or chapter number (reader) last opened.
  @HiveField(2)
  int episodeOrChapter;

  /// Playback position in seconds (video). 0 when not started / reader.
  @HiveField(3)
  int positionSeconds;

  /// Page index within the chapter (reader). 0 when video.
  @HiveField(4)
  int page;

  @HiveField(5)
  DateTime updatedAt;

  /// Box key for this entry.
  String get boxKey => '$providerId::$itemId';

  /// Key for looking up the catalog item this entry points to.
  String get catalogKey => '$providerId::$itemId';
}
