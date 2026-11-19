import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/details_screen.dart';
import '../screens/developer_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/manga_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/player/player_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/reader/reader_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings/add_repo_screen.dart';
import '../screens/settings/providers_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/welcome_screen.dart';
import '../services/auth_service.dart';
import '../widgets/bottom_nav_bar.dart';

/// App routing (go_router). All 17 routes return real screens; the only
/// remaining [PlaceholderScreen] use is the 404 errorBuilder below.
///
/// Route table (see CONTRACT.md):
///   /                     splash
///   /onboarding           onboarding slides
///   /welcome              welcome / choose login or sign-up
///   /signup               sign-up form
///   /login                login form (email + password + device code)
///   /home /search /manga /library /profile   bottom-nav shell branches
///   /settings             settings
///   /settings/providers   providers (inside settings)
///   /developer            developer page (from Profile / Settings)
///   /details/:id          title details
///   /player/:id           video player
///   /reader/:id           manga/manhwa reader
///   /backup               backup & restore
///
/// There is intentionally NO `/code` route: the device-code popup is a
/// dialog (see `lib/widgets/code_popup.dart`).

/// Notifies GoRouter when auth state changes so redirects re-run.
class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref.onDispose(refresh.dispose);
  ref.listen(authStateProvider, (_, _) => refresh.refresh());

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Real session check: authStateProvider is refreshed by the splash
      // screen at startup and flipped by login/logout (auth workstream).
      final loggedIn = ref.read(authStateProvider);
      final location = state.matchedLocation;
      const authRoutes = {'/welcome', '/login', '/signup', '/onboarding'};
      if (!loggedIn && location != '/' && !authRoutes.contains(location)) {
        return '/welcome';
      }
      if (loggedIn && authRoutes.contains(location)) {
        return '/home';
      }
      return null;
    },
    errorBuilder: (context, state) => const PlaceholderScreen(
      title: 'Not found',
      detail: 'This page does not exist.',
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/manga',
                builder: (context, state) => const MangaScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/providers',
        builder: (context, state) => const ProvidersScreen(),
      ),
      GoRoute(
        path: '/settings/providers/add',
        builder: (context, state) => const AddRepoScreen(),
      ),
      GoRoute(
        path: '/developer',
        builder: (context, state) => const DeveloperScreen(),
      ),
      GoRoute(
        path: '/details/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return DetailsScreen(itemId: id);
        },
      ),
      GoRoute(
        path: '/player/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final episode =
              int.tryParse(state.uri.queryParameters['episode'] ?? '');
          final source = state.uri.queryParameters['source'];
          return PlayerScreen(
            itemId: id,
            episodeNumber: episode,
            sourceHint: source,
          );
        },
      ),
      GoRoute(
        path: '/reader/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final chapter =
              int.tryParse(state.uri.queryParameters['chapter'] ?? '');
          final mode = state.uri.queryParameters['mode'];
          return ReaderScreen(
            itemId: id,
            chapterNumber: chapter,
            mode: mode,
          );
        },
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupScreen(),
      ),
    ],
  );
});

/// Bottom-nav shell: the active branch as body + the docked [BottomNavBar].
class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: navigationShell.goBranch,
      ),
    );
  }
}
