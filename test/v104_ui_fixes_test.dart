import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:streambox/i18n/i18n.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/screens/backup_screen.dart';
import 'package:streambox/screens/developer_screen.dart';
import 'package:streambox/screens/home_screen.dart';
import 'package:streambox/screens/profile_screen.dart';
import 'package:streambox/screens/settings_screen.dart';
import 'package:streambox/services/auth_service.dart';
import 'package:streambox/services/backup_service.dart';
import 'package:streambox/services/credential_storage.dart';
import 'package:streambox/services/provider_service.dart';
import 'package:streambox/services/storage.dart';
import 'package:streambox/theme/app_theme.dart';
import 'package:streambox/widgets/widgets.dart';

/// Widget tests for the v1.0.4 UI pass:
///
/// 1. Developer is a full page (`/developer`): Profile → Developer and
///    Settings → Developer navigate there; the page shows the photo,
///    name, role and version.
/// 2. Home top-bar search icon: the visible magnifier glyph, with a
///    high-contrast colour in BOTH themes, navigating to /search.
/// 3. Backup code dialog: a mistyped code shows an inline error and
///    keeps the dialog open; a wrong (but well-formed) code on export
///    re-prompts instead of dropping back to the screen.
///
/// Plain `pumpAndSettle` is never used here: the Home hero carousel runs
/// a 5-second periodic timer, which never settles. [_pumpUntil] /
/// [_pumpUntilGone] pump in bounded 100 ms steps instead.

/// In-memory [CredentialStorage] — no platform channels, no stored code,
/// so `verifyCode` always returns false (drives the re-prompt test).
class _MapCredentialStorage implements CredentialStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// Minimal router for these tests: the real screens under test plus a
/// marker for /search. The production router (auth redirects, shell) is
/// not needed to prove navigation between these screens.
GoRouter _testRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/search',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Search screen')),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/developer',
        builder: (_, _) => const DeveloperScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/backup',
        builder: (_, _) => const BackupScreen(),
      ),
    ],
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String initialLocation,
  ThemeMode themeMode = ThemeMode.dark,
  AuthService? authService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Riverpod 3 does not export the `Override` type, so the
        // override list is built here instead of taken as a parameter.
        if (authService != null)
          authServiceProvider.overrideWithValue(authService),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: _testRouter(initialLocation: initialLocation),
      ),
    ),
  );
}

/// Pump until [finder] matches (or [maxPumps] is reached — the expect
/// after the call then fails with a clear message).
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// Pump until [finder] matches nothing (e.g. a dialog finishing its
/// pop animation).
Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('streambox-v104-test');
    Hive.init(tempDir.path);
    await initStorage();
    // Pre-seed the sample catalog HERE (real async). The providers
    // provider lazy-seeds on first read inside the test body; a seed
    // started in the FakeAsync test zone never completes after the
    // test ends, and the next test's setUp clear() on the
    // providers/catalog boxes then hangs forever waiting for the
    // stranded write. Seeding once up front means the lazy seed never
    // fires inside a test.
    await HiveProviderService(
      Hive.box<ProviderRepo>(BoxNames.providers),
      Hive.box<ProviderItem>(BoxNames.catalog),
    ).seedBuiltIn();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box<UserProfile>(BoxNames.profile).clear();
    await Hive.box<LibraryEntry>(BoxNames.library).clear();
    await Hive.box<HistoryEntry>(BoxNames.history).clear();
    await Hive.box<AppSettings>(BoxNames.settings).clear();
    // NOTE: the providers + catalog boxes are deliberately NOT cleared
    // here — clearing them would re-trigger the lazy sample seed
    // inside the next test's FakeAsync zone (see setUpAll). None of
    // these tests mutates providers or catalog items.
  });

  group('Developer page', () {
    testWidgets('Profile → Developer navigates to the page',
        (tester) async {
      // Tall viewport: the Developer row sits below the fold at the
      // default 600px height and the ListView builds rows lazily, so a
      // plain finder never sees it. (scrollUntilVisible stops with the
      // row 1px visible at the edge, where taps miss, and
      // tester.ensureVisible awaits a scroll animation that never
      // completes without pumps — both were tried and both fail.)
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpApp(tester, initialLocation: '/profile');
      await _pumpUntil(tester, find.text('Developer'));

      final row = find.text('Developer');
      await tester.tap(row);
      await _pumpUntil(
        tester,
        find.text(trForLocale(const Locale('en'), 'developer.role')),
      );

      // The page shows the name, role, version and photo.
      expect(find.text('Jarif Ahmed'), findsWidgets);
      expect(
        find.text(trForLocale(const Locale('en'), 'developer.role')),
        findsOneWidget,
      );
      expect(
        find.text(
          trForLocale(const Locale('en'), 'settings.aboutVersion'),
        ),
        findsOneWidget,
      );
      final avatar =
          tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<AssetImage>());
      expect(
        (avatar.backgroundImage as AssetImage).assetName,
        'assets/images/developer_photo.jpg',
      );
      // The bio is on the page too.
      expect(
        find.text(trForLocale(const Locale('en'), 'developer.bio')),
        findsOneWidget,
      );
    });

    testWidgets('Settings → Developer navigates to the page',
        (tester) async {
      // Tall viewport, as on Profile: the row is below the fold at
      // the default height and the ListView builds rows lazily.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpApp(tester, initialLocation: '/settings');
      await _pumpUntil(tester, find.text('Developer'));
      final row = find.text('Developer');
      await tester.tap(row);
      await _pumpUntil(
        tester,
        find.text(trForLocale(const Locale('en'), 'developer.role')),
      );

      expect(
        find.text(trForLocale(const Locale('en'), 'developer.role')),
        findsOneWidget,
      );
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('Home search icon', () {
    testWidgets('visible search button navigates to /search (dark theme)',
        (tester) async {
      await _pumpApp(tester, initialLocation: '/home');
      // The header (with the search button) renders even before the
      // sample catalog finishes seeding — and even with an empty
      // catalog, where the old code showed no header at all.
      final searchIcon = find.byIcon(Iconsax.search_normal_copy);
      await _pumpUntil(tester, searchIcon);

      // The malformed search_normal glyph (solid disc + dot in this
      // font build) must not appear on Home any more.
      expect(find.byIcon(Iconsax.search_normal), findsNothing);
      expect(searchIcon, findsOneWidget);

      // High-contrast in dark theme: near-white icon on near-black bg.
      final icon = tester.widget<Icon>(searchIcon);
      expect(icon.color, AppColors.darkText);
      expect(icon.color, isNot(AppColors.darkBg));

      await tester.tap(searchIcon);
      await _pumpUntil(tester, find.text('Search screen'));
      expect(find.text('Search screen'), findsOneWidget);
    });

    testWidgets('search icon is high-contrast in the light theme',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/home',
        themeMode: ThemeMode.light,
      );
      final searchIcon = find.byIcon(Iconsax.search_normal_copy);
      await _pumpUntil(tester, searchIcon);

      expect(searchIcon, findsOneWidget);
      // Near-black icon on the light background — not the background
      // colour, not the muted colour.
      final icon = tester.widget<Icon>(searchIcon);
      expect(icon.color, AppColors.lightText);
      expect(icon.color, isNot(AppColors.lightBg));
    });
  });

  group('Backup code dialog', () {
    testWidgets('a mistyped code shows an inline error, dialog stays open',
        (tester) async {
      await _pumpApp(tester, initialLocation: '/backup');
      await _pumpUntil(tester, find.byType(GradientButton));

      // Export opens the code dialog.
      await tester.tap(find.byType(GradientButton));
      final prompt = find.text(
        trForLocale(const Locale('en'), 'backup.codePrompt'),
      );
      await _pumpUntil(tester, prompt);

      await tester.enterText(find.byType(TextField), 'not-a-code');
      await tester.pump();
      await tester.tap(
        find.text(trForLocale(const Locale('en'), 'backup.unlockBackup')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The dialog is still open, with the error shown inline — the
      // user corrects the typo instead of restarting the export.
      expect(prompt, findsOneWidget);
      expect(
        find.text(trForLocale(const Locale('en'), 'auth.codeInvalid')),
        findsOneWidget,
      );

      // Clean up: cancel out of the dialog.
      await tester.tap(
        find.text(trForLocale(const Locale('en'), 'common.cancel')),
      );
      await _pumpUntilGone(tester, prompt);
    });

    testWidgets('a wrong code on export re-prompts instead of dropping out',
        (tester) async {
      final credentials = _MapCredentialStorage();
      final auth = LocalAuthService(
        credentials: credentials,
        backupService: BackupService(credentials: credentials),
      );
      await _pumpApp(
        tester,
        initialLocation: '/backup',
        authService: auth,
      );
      await _pumpUntil(tester, find.byType(GradientButton));

      await tester.tap(find.byType(GradientButton));
      final prompt = find.text(
        trForLocale(const Locale('en'), 'backup.codePrompt'),
      );
      await _pumpUntil(tester, prompt);

      // Well-formed but wrong: no code is stored, so verifyCode fails.
      await tester.enterText(
        find.byType(TextField),
        'SB-AAAA-BBBB-CCCC',
      );
      await tester.pump();
      await tester.tap(
        find.text(trForLocale(const Locale('en'), 'backup.unlockBackup')),
      );
      // The first dialog pops, then the re-prompt appears.
      await _pumpUntilGone(tester, prompt);
      await _pumpUntil(tester, prompt);

      expect(prompt, findsOneWidget);
      expect(
        find.text(
          trForLocale(const Locale('en'), 'auth.errorWrongCode'),
        ),
        findsOneWidget,
      );

      // Cancel out of the re-prompt to leave the flow.
      await tester.tap(
        find.text(trForLocale(const Locale('en'), 'common.cancel')),
      );
      await _pumpUntilGone(tester, prompt);
    });
  });
}
