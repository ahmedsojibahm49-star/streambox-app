import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'bn.dart';
import 'en.dart';

/// Hand-rolled map-based i18n (same approach as the Expo app — no codegen).
///
/// Usage in widgets: `tr(context, 'home.trendingNow')`.
/// Placeholders use `{name}` and are filled via [trParams].
///
/// Adding keys (workstreams): add the key to BOTH en.dart and bn.dart in the
/// same change. A unit test (`test/i18n_test.dart`) fails the build when the
/// two maps drift apart.

/// Current app locale. Persisted to the settings box by the settings screen;
/// main.dart seeds it from there at startup. Update via
/// `ref.read(localeProvider.notifier).setLocale(...)`.
final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  LocaleNotifier([this._initial = const Locale('en')]);

  final Locale _initial;

  @override
  Locale build() => _initial;

  void setLocale(Locale locale) => state = locale;
}

/// All supported locales, in settings-screen order.
const List<Locale> supportedLocales = [Locale('en'), Locale('bn')];

/// Translate [key] for the locale in [localeProvider].
/// Falls back to English, then to the key itself (never crashes on a
/// missing key — it just shows the key, which the i18n test catches).
String tr(BuildContext context, String key) {
  final locale = ProviderScope.containerOf(context).read(localeProvider);
  return trForLocale(locale, key);
}

/// Translate [key] for an explicit locale (non-widget code).
String trForLocale(Locale locale, String key) {
  final map = locale.languageCode == 'bn' ? bnStrings : enStrings;
  return map[key] ?? enStrings[key] ?? key;
}

/// Translate [key] and fill `{name}` placeholders from [params].
String trParams(BuildContext context, String key, Map<String, String> params) {
  var value = tr(context, key);
  params.forEach((name, replacement) {
    value = value.replaceAll('{$name}', replacement);
  });
  return value;
}

/// Locale-aware short date, e.g. `19 Nov 2026` / `১৯ নভেম্বর ২০২৬`.
/// main.dart calls `initializeDateFormatting('bn')` at startup so the Bangla
/// symbols are loaded; English is built into intl.
String formatDate(BuildContext context, DateTime date) {
  final locale = ProviderScope.containerOf(context).read(localeProvider);
  return DateFormat.yMMMd(locale.languageCode).format(date);
}
