import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:streambox/i18n/i18n.dart';
import 'package:streambox/models/models.dart';
import 'package:streambox/screens/developer_screen.dart';
import 'package:streambox/screens/home_screen.dart';
import 'package:streambox/screens/profile_screen.dart';
import 'package:streambox/screens/settings_screen.dart';
import 'package:streambox/services/provider_service.dart';
import 'package:streambox/services/storage.dart';
import 'package:streambox/theme/app_theme.dart';
import 'package:streambox/widgets/bottom_nav_bar.dart';

/// Widget + source-scan tests for the v1.0.5 icon polish pass:
///
/// 1. NO Bold (filled) icons anywhere: in iconsax_flutter 1.0.1 base
///    names are Bold and `_copy` names are Linear (verified against the
///    font file — filled glyphs carry ~2-3x the ink of their outline
///    twin). Every icon in lib/ must be a `_copy` name.
/// 2. No decorative trailing chevrons on Settings/Profile rows.
/// 3. The Home notification bell is still present (dark + light).
/// 4. Bottom nav: Linear glyphs in both states; active = colour only.
/// 5. The in-app version string matches pubspec (it is a hardcoded
///    i18n string, not package_info_plus — the two can drift).
///
/// Plain `pumpAndSettle` is never used here: the Home hero carousel
/// runs a 5-second periodic timer, which never settles. [_pumpUntil]
/// pumps in bounded 100 ms steps instead (same as the v1.0.4 tests).

/// Every Bold (base-name) Iconsax identifier removed in v1.0.5.
/// `refresh_2` has no `_copy` variant in the package — it was replaced
/// by `refresh_copy` (the Linear circular arrow).
const List<String> _bannedBoldIconNames = [
  'add_circle',
  'arrow_down_1',
  'arrow_left',
  'arrow_left_1',
  'arrow_right',
  'arrow_right_1',
  'backward_10_seconds',
  'book',
  'book_1',
  'bookmark',
  'clock',
  'close_circle',
  'cloud',
  'code',
  'copy',
  'copy_success',
  'document_text',
  'export_1',
  'eye',
  'eye_slash',
  'filter',
  'folder',
  'folder_open',
  'forward_10_seconds',
  'global',
  'heart',
  'home',
  'image',
  'import_1',
  'info_circle',
  'key',
  'link',
  'link_1',
  'lock',
  'login_1',
  'logout',
  'maximize_1',
  'monitor',
  'moon',
  'notification',
  'play_circle',
  'refresh',
  'refresh_2',
  'search_normal',
  'setting_2',
  'share',
  'shield_tick',
  'sms',
  'sort',
  'star_1',
  'sun_1',
  'tick_circle',
  'translate',
  'trash',
  'user',
  'warning_2',
];

/// The same denylist as [IconData] values, for the rendered-widget
/// checks (a Bold glyph must never appear on screen, not just in code).
/// Not `const`: IconData overrides ==/hashCode, so it cannot be an
/// element of a constant set.
final Set<IconData> _bannedBoldIcons = {
  Iconsax.add_circle,
  Iconsax.arrow_down_1,
  Iconsax.arrow_left,
  Iconsax.arrow_left_1,
  Iconsax.arrow_right,
  Iconsax.arrow_right_1,
  Iconsax.backward_10_seconds,
  Iconsax.book,
  Iconsax.book_1,
  Iconsax.bookmark,
  Iconsax.clock,
  Iconsax.close_circle,
  Iconsax.cloud,
  Iconsax.code,
  Iconsax.copy,
  Iconsax.copy_success,
  Iconsax.document_text,
  Iconsax.export_1,
  Iconsax.eye,
  Iconsax.eye_slash,
  Iconsax.filter,
  Iconsax.folder,
  Iconsax.folder_open,
  Iconsax.forward_10_seconds,
  Iconsax.global,
  Iconsax.heart,
  Iconsax.home,
  Iconsax.image,
  Iconsax.import_1,
  Iconsax.info_circle,
  Iconsax.key,
  Iconsax.link,
  Iconsax.link_1,
  Iconsax.lock,
  Iconsax.login_1,
  Iconsax.logout,
  Iconsax.maximize_1,
  Iconsax.monitor,
  Iconsax.moon,
  Iconsax.notification,
  Iconsax.play_circle,
  Iconsax.refresh,
  Iconsax.refresh_2,
  Iconsax.search_normal,
  Iconsax.setting_2,
  Iconsax.share,
  Iconsax.shield_tick,
  Iconsax.sms,
  Iconsax.sort,
  Iconsax.star_1,
  Iconsax.sun_1,
  Iconsax.tick_circle,
  Iconsax.translate,
  Iconsax.trash,
  Iconsax.user,
  Iconsax.warning_2,
};

/// Minimal router for these tests: the real screens under test plus a
/// marker for /search. The production router (auth redirects, shell)
/// is not needed to prove navigation between these screens.
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
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/developer',
        builder: (_, _) => const DeveloperScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String initialLocation,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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

/// Every [Icon] currently rendered must use a Linear glyph — no banned
/// Bold IconData anywhere on the pumped screen.
void _expectNoBoldIcons(WidgetTester tester) {
  final icons = find.byType(Icon).evaluate().map(
        (e) => e.widget as Icon,
      );
  final bold = icons.where((icon) => _bannedBoldIcons.contains(icon.icon));
  expect(
    bold,
    isEmpty,
    reason: 'Bold icons rendered: '
        '${bold.map((i) => 'U+${i.icon!.codePoint.toRadixString(16)}')}',
  );
}

void main() {
  group('Source scan: no Bold icon identifiers in lib/', () {
    test('no banned Bold Iconsax identifier appears in lib/ code', () {
      final libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'lib/ not found — run from the package root.',
      );
      final hits = <String>[];
      for (final file in libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        var code = file.readAsStringSync();
        // Comments are not code: strip block comments, then line
        // comments, so a comment *discussing* a banned glyph (e.g. the
        // Home search-icon note) cannot trip the scan.
        code = code.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        code = code.replaceAll(RegExp(r'//.*'), '');
        for (final name in _bannedBoldIconNames) {
          // Whole identifier only: the negative lookahead keeps
          // `Iconsax.book` from matching `Iconsax.book_1` or
          // `Iconsax.book_copy`, and `Iconsax.refresh` from matching
          // `Iconsax.refresh_2`.
          final pattern = RegExp(
            'Iconsax\\.${RegExp.escape(name)}(?![A-Za-z0-9_])',
          );
          if (pattern.hasMatch(code)) {
            hits.add('${file.path}: Iconsax.$name');
          }
        }
      }
      expect(hits, isEmpty, reason: 'Bold icons in lib/:\n${hits.join('\n')}');
    });

    test('in-app version string matches pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+',
              multiLine: true)
          .firstMatch(pubspec);
      expect(match, isNotNull, reason: 'no version: in pubspec.yaml');
      final version = match!.group(1)!;
      // The version shown on the Developer page + About dialog is a
      // hardcoded i18n string, not package_info_plus — it must be
      // bumped with pubspec or the app lies about its own version.
      expect(
        trForLocale(const Locale('en'), 'settings.aboutVersion'),
        'Version $version',
      );
    });
  });

  group('Rendered screens: Linear icons only, no row chevrons', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('streambox-v105-test');
      Hive.init(tempDir.path);
      await initStorage();
      // Pre-seed the sample catalog HERE (real async) — see the v1.0.4
      // tests for why the lazy seed must never fire in FakeAsync.
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
      // NOTE: the providers + catalog boxes are deliberately NOT
      // cleared here (see setUpAll).
    });

    testWidgets('Settings rows have no trailing chevron and stay tappable',
        (tester) async {
      // Tall viewport: the Developer row sits below the fold at the
      // default 600px height and the ListView builds rows lazily.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpApp(tester, initialLocation: '/settings');
      await _pumpUntil(tester, find.text('Developer'));

      // No chevron glyph at all — neither the old Bold one nor the
      // Linear one: the chevron was REMOVED, not restyled.
      expect(find.byIcon(Iconsax.arrow_right_1), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right_1_copy), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right_copy), findsNothing);
      _expectNoBoldIcons(tester);

      // The rows are still there and still tappable without the
      // chevron: Developer navigates to the Developer page.
      expect(find.text('Developer'), findsOneWidget);
      expect(find.text('Providers'), findsOneWidget);
      expect(
        find.text(trForLocale(const Locale('en'), 'settings.backup')),
        findsOneWidget,
      );
      await tester.tap(find.text('Developer'));
      await _pumpUntil(
        tester,
        find.text(trForLocale(const Locale('en'), 'developer.role')),
      );
      expect(
        find.text(trForLocale(const Locale('en'), 'developer.role')),
        findsOneWidget,
      );
    });

    testWidgets('Profile rows have no trailing chevron and stay tappable',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpApp(tester, initialLocation: '/profile');
      await _pumpUntil(tester, find.text('Developer'));

      expect(find.byIcon(Iconsax.arrow_right_1), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right_1_copy), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right), findsNothing);
      expect(find.byIcon(Iconsax.arrow_right_copy), findsNothing);
      _expectNoBoldIcons(tester);

      expect(find.text('Developer'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Developer'));
      await _pumpUntil(
        tester,
        find.text(trForLocale(const Locale('en'), 'developer.role')),
      );
      expect(
        find.text(trForLocale(const Locale('en'), 'developer.role')),
        findsOneWidget,
      );
    });

    testWidgets('Home: bell present, Linear icons only (dark theme)',
        (tester) async {
      await _pumpApp(tester, initialLocation: '/home');
      final bell = find.byIcon(Iconsax.notification_copy);
      await _pumpUntil(tester, bell);

      expect(bell, findsOneWidget);
      // The old filled bell must not appear anywhere on Home.
      expect(find.byIcon(Iconsax.notification), findsNothing);
      // High-contrast in dark theme: near-white icon on near-black bg.
      final icon = tester.widget<Icon>(bell);
      expect(icon.color, AppColors.darkText);
      expect(icon.color, isNot(AppColors.darkBg));
      _expectNoBoldIcons(tester);
    });

    testWidgets('Home: bell present and high-contrast (light theme)',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/home',
        themeMode: ThemeMode.light,
      );
      final bell = find.byIcon(Iconsax.notification_copy);
      await _pumpUntil(tester, bell);

      expect(bell, findsOneWidget);
      final icon = tester.widget<Icon>(bell);
      expect(icon.color, AppColors.lightText);
      expect(icon.color, isNot(AppColors.lightBg));
    });

    testWidgets('Bottom nav: Linear glyphs in both states, active = colour',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              bottomNavigationBar:
                  BottomNavBar(currentIndex: 0, onTap: (_) {}),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      // All five tabs render their Linear glyphs…
      expect(find.byIcon(Iconsax.home_copy), findsOneWidget);
      expect(find.byIcon(Iconsax.search_normal_copy), findsOneWidget);
      expect(find.byIcon(Iconsax.book_copy), findsOneWidget);
      expect(find.byIcon(Iconsax.bookmark_copy), findsOneWidget);
      expect(find.byIcon(Iconsax.user_copy), findsOneWidget);
      // …and none of the Bold twins.
      expect(find.byIcon(Iconsax.home), findsNothing);
      expect(find.byIcon(Iconsax.book), findsNothing);
      expect(find.byIcon(Iconsax.bookmark), findsNothing);
      expect(find.byIcon(Iconsax.user), findsNothing);

      // Active tab (Home, index 0) is brand orange; an inactive tab
      // is muted — colour, not glyph weight, marks the active tab.
      final homeIcon = tester.widget<Icon>(find.byIcon(Iconsax.home_copy));
      expect(homeIcon.color, AppColors.brand);
      final mangaIcon =
          tester.widget<Icon>(find.byIcon(Iconsax.book_copy));
      expect(mangaIcon.color, isNot(AppColors.brand));
    });
  });
}
