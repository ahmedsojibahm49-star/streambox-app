// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProviderItemAdapter extends TypeAdapter<ProviderItem> {
  @override
  final int typeId = 0;

  @override
  ProviderItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProviderItem(
      id: fields[0] as String,
      providerId: fields[1] as String,
      type: fields[2] as ContentType,
      title: fields[3] as String,
      posterUrl: fields[4] as String?,
      backdropUrl: fields[5] as String?,
      year: fields[6] as int?,
      rating: fields[7] as double?,
      genres: (fields[8] as List).cast<String>(),
      overview: fields[9] as String?,
      status: fields[10] as String?,
      episodesJson: fields[11] as String?,
      chaptersJson: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ProviderItem obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.providerId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.posterUrl)
      ..writeByte(5)
      ..write(obj.backdropUrl)
      ..writeByte(6)
      ..write(obj.year)
      ..writeByte(7)
      ..write(obj.rating)
      ..writeByte(8)
      ..write(obj.genres)
      ..writeByte(9)
      ..write(obj.overview)
      ..writeByte(10)
      ..write(obj.status)
      ..writeByte(11)
      ..write(obj.episodesJson)
      ..writeByte(12)
      ..write(obj.chaptersJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ContentTypeAdapter extends TypeAdapter<ContentType> {
  @override
  final int typeId = 6;

  @override
  ContentType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ContentType.anime;
      case 1:
        return ContentType.movie;
      case 2:
        return ContentType.manga;
      case 3:
        return ContentType.manhwa;
      default:
        return ContentType.anime;
    }
  }

  @override
  void write(BinaryWriter writer, ContentType obj) {
    switch (obj) {
      case ContentType.anime:
        writer.writeByte(0);
        break;
      case ContentType.movie:
        writer.writeByte(1);
        break;
      case ContentType.manga:
        writer.writeByte(2);
        break;
      case ContentType.manhwa:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
