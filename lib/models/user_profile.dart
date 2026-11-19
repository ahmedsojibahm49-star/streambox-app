import 'package:hive/hive.dart';

part 'user_profile.g.dart';

/// The signed-in user. Stored in the `profile` box under the single key
/// `current`. All data is local — there is no server account.
///
/// NOTE: never store the password or device code in this box. Credentials
/// live in flutter_secure_storage only (auth workstream).
@HiveType(typeId: 4)
class UserProfile extends HiveObject {
  UserProfile({
    required this.name,
    required this.email,
    required this.createdAt,
  });

  @HiveField(0)
  String name;

  @HiveField(1)
  String email;

  @HiveField(2)
  DateTime createdAt;
}
