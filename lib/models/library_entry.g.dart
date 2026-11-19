// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LibraryEntryAdapter extends TypeAdapter<LibraryEntry> {
  @override
  final int typeId = 2;

  @override
  LibraryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LibraryEntry(
      itemId: fields[0] as String,
      providerId: fields[1] as String,
      list: fields[2] as LibraryList,
      savedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, LibraryEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.itemId)
      ..writeByte(1)
      ..write(obj.providerId)
      ..writeByte(2)
      ..write(obj.list)
      ..writeByte(3)
      ..write(obj.savedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LibraryListAdapter extends TypeAdapter<LibraryList> {
  @override
  final int typeId = 7;

  @override
  LibraryList read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return LibraryList.myList;
      case 1:
        return LibraryList.favorite;
      default:
        return LibraryList.myList;
    }
  }

  @override
  void write(BinaryWriter writer, LibraryList obj) {
    switch (obj) {
      case LibraryList.myList:
        writer.writeByte(0);
        break;
      case LibraryList.favorite:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
