import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'i18n/i18n.dart';
import 'models/models.dart';
import 'router/app_router.dart';
import 'services/storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android immersive mode: hide system nav on entry (swipe brings it back).
  // Android ONLY — iOS/web keep their system UI. The player handles its own
  // landscape orientation; the manifest does not lock orientation.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // Local storage: Hive boxes (all data is on-device, no server).
  await Hive.initFlutter();
  await initStorage();

  // Bangla date symbols for intl (English is built in).
  await initializeDateFormatting('bn');

  // Seed theme + locale from the persisted settings (or defaults).
  final settingsBox = Hive.box<AppSettings>(BoxNames.settings);
  final settings = settingsBox.get('current') ?? AppSettings();
  if (!settingsBox.containsKey('current')) {
    await settingsBox.put('current', settings);
  }

  runApp(
    ProviderScope(
      overrides: [
        localeProvider.overrideWith(() => LocaleNotifier(settings.localeValue)),
        themeModeProvider
            .overrideWith(() => ThemeModeNotifier(settings.themeModeValue)),
      ],
      child: const StreamBoxApp(),
    ),
  );
}

class StreamBoxApp extends ConsumerWidget {
  const StreamBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'StreamBox',
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    );
  }
}
