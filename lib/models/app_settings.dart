import 'package:material_ui/material_ui.dart';
import 'package:hive/hive.dart';

part 'app_settings.g.dart';

/// Persisted app settings. Stored in the `settings` box under the single
/// key `current`. The theme/locale providers in main.dart read from here.
///
/// `themeMode` / `localeCode` are plain strings (not enums) so new values
/// can be added without a Hive schema migration.
@HiveType(typeId: 5)
class AppSettings extends HiveObject {
  AppSettings({
    this.themeMode = 'system',
    this.localeCode = 'en',
    this.notificationsEnabled = true,
  });

  /// `'system'` | `'dark'` | `'light'`.
  @HiveField(0)
  String themeMode;

  /// `'en'` | `'bn'`.
  @HiveField(1)
  String localeCode;

  @HiveField(2)
  bool notificationsEnabled;

  ThemeMode get themeModeValue {
    switch (themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Locale get localeValue => Locale(localeCode);
}
