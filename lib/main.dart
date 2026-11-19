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
import 'screens/auth/startup_error_screen.dart';
import 'services/storage.dart';
import 'theme/app_theme.dart';

/// Result of [bootstrap]. [storageError] is non-null when local storage
/// could not be started even after recovery — the app then shows
/// [StartupErrorScreen] instead of the normal UI (never a white screen).
class BootstrapResult {
  const BootstrapResult({required this.settings, this.storageError});

  /// Defaults when storage is unavailable (system theme, English).
  factory BootstrapResult.fallback() =>
      BootstrapResult(settings: AppSettings());

  final AppSettings settings;

  /// The storage error, or null when storage started fine.
  final Object? storageError;

  bool get storageReady => storageError == null;
}

/// Current bootstrap result. Seeded by main() via override; the Retry
/// button on [StartupErrorScreen] re-runs [bootstrap] through [retry].
final startupProvider =
    NotifierProvider<StartupNotifier, BootstrapResult>(StartupNotifier.new);

class StartupNotifier extends Notifier<BootstrapResult> {
  StartupNotifier([BootstrapResult? initial])
      : _initial = initial ?? BootstrapResult.fallback();

  final BootstrapResult _initial;

  @override
  BootstrapResult build() => _initial;

  /// Re-run the bootstrap (storage recovery included) and update state.
  Future<void> retry() async {
    state = await bootstrap();
  }
}

/// App startup. NEVER throws: every step is guarded so a failure degrades
/// (defaults / error screen) instead of dying before runApp — a throw
/// here used to leave the white Android launch background up forever
/// (white screen on launch, Nov 19).
///
/// Storage init uses [initHiveWithFallback]: if the documents directory
/// is unusable on a device, Hive retries the support, temp, then cache
/// directory before the startup error screen appears.
Future<BootstrapResult> bootstrap() async {
  // Android immersive mode: hide system nav on entry (swipe brings it back).
  // Android ONLY — iOS/web keep their system UI. The player handles its own
  // landscape orientation; the manifest does not lock orientation.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // System UI is cosmetic — never block startup on it.
    }
  }

  // Local storage: Hive boxes (all data is on-device, no server).
  // initHiveWithFallback tries the documents, support, temp, then cache
  // directory — a broken documents-dir call must not kill startup.
  Object? storageError;
  AppSettings settings = AppSettings();
  var hiveReady = false;
  try {
    await initHiveWithFallback();
    hiveReady = true;
    await initStorage();
  } catch (e) {
    // initStorage failed (e.g. corrupt box file) after Hive had a working
    // directory: delete the box files and try once more before giving up.
    // Recovery needs a Hive path, so it only runs when init succeeded.
    if (hiveReady) {
      try {
        await recoverStorage();
      } catch (e2) {
        storageError = e2;
      }
    } else {
      storageError = e;
    }
  }
  if (storageError == null) {
    // Seed theme + locale from the persisted settings (or defaults).
    try {
      final settingsBox = Hive.box<AppSettings>(BoxNames.settings);
      settings = settingsBox.get('current') ?? AppSettings();
      if (!settingsBox.containsKey('current')) {
        await settingsBox.put('current', settings);
      }
    } catch (e) {
      storageError = e;
    }
  }

  // Bangla date symbols for intl (English is built in). Failure is
  // non-fatal: Bangla dates fall back to English formatting.
  try {
    await initializeDateFormatting('bn');
  } catch (_) {}

  return BootstrapResult(settings: settings, storageError: storageError);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never show a blank screen on a build failure: log the error and
  // render a visible branded error view instead of Flutter's blank
  // release-mode error widget. The previous onError handler (Flutter's
  // default, or the test framework's reporter in tests) is still called.
  // The ErrorWidget override is release/profile only: in debug builds the
  // red error screen is more useful, and flutter_test forbids changing
  // ErrorWidget.builder.
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('StreamBox FlutterError: ${details.exception}');
    defaultOnError?.call(details);
  };
  if (!kDebugMode) {
    ErrorWidget.builder = (details) => StartupErrorFallback(details: details);
  }

  final startup = await bootstrap();
  runStreamBoxApp(startup);
}

/// Attach the app widget. Split out of [main] so widget tests can run
/// the real [bootstrap] (real file I/O) inside `tester.runAsync()` and
/// then call this in the test's FakeAsync zone — calling runApp inside
/// runAsync would run the first frame (and the splash's post-frame
/// session check) in the real-async zone, where its timeouts use wall
/// time instead of fake time.
void runStreamBoxApp(BootstrapResult startup) {
  runApp(
    ProviderScope(
      overrides: [
        startupProvider.overrideWith(() => StartupNotifier(startup)),
        localeProvider.overrideWith(
          () => LocaleNotifier(startup.settings.localeValue),
        ),
        themeModeProvider.overrideWith(
          () => ThemeModeNotifier(startup.settings.themeModeValue),
        ),
      ],
      child: const StreamBoxApp(),
    ),
  );
}

class StreamBoxApp extends ConsumerWidget {
  const StreamBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    if (!startup.storageReady) {
      // Storage could not be started: show the error screen (with Retry)
      // instead of the router app, whose providers need the Hive boxes.
      return MaterialApp(
        title: 'StreamBox',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: StartupErrorScreen(
          error: startup.storageError ?? 'Unknown storage error',
          onRetry: () => ref.read(startupProvider.notifier).retry(),
        ),
      );
    }
    final router = ref.watch(appRouterProvider);
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
