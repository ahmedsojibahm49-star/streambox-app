import 'package:hive/hive.dart';

part 'library_entry.g.dart';

/// Which library list an entry belongs to. Stored as a Hive enum (typeId 7).
@HiveType(typeId: 7)
enum LibraryList {
  @HiveField(0)
  myList,
  @HiveField(1)
  favorite,
}

/// One saved item in My List or Favorites.
/// Stored in the `library` box, keyed by `"${list.name}::$providerId::$itemId"`.
@HiveType(typeId: 2)
class LibraryEntry extends HiveObject {
  LibraryEntry({
    required this.itemId,
    required this.providerId,
    required this.list,
    required this.savedAt,
  });

  @HiveField(0)
  String itemId;

  @HiveField(1)
  String providerId;

  @HiveField(2)
  LibraryList list;

  @HiveField(3)
  DateTime savedAt;

  /// Box key for this entry.
  String get boxKey => '${list.name}::$providerId::$itemId';

  /// Key for looking up the catalog item this entry points to.
  String get catalogKey => '$providerId::$itemId';
}
