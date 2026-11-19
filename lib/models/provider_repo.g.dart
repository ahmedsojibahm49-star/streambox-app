// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_repo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProviderRepoAdapter extends TypeAdapter<ProviderRepo> {
  @override
  final int typeId = 1;

  @override
  ProviderRepo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProviderRepo(
      id: fields[0] as String,
      name: fields[1] as String,
      sourceUrl: fields[2] as String,
      isBuiltIn: fields[3] as bool,
      enabled: fields[4] as bool,
      itemCount: fields[5] as int,
      lastFetchedAt: fields[6] as DateTime?,
      rawJson: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ProviderRepo obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.sourceUrl)
      ..writeByte(3)
      ..write(obj.isBuiltIn)
      ..writeByte(4)
      ..write(obj.enabled)
      ..writeByte(5)
      ..write(obj.itemCount)
      ..writeByte(6)
      ..write(obj.lastFetchedAt)
      ..writeByte(7)
      ..write(obj.rawJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderRepoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
