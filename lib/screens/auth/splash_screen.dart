import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Splash (`/`): checks the session, then routes on.
///
/// Logged in → `/home`. Logged out → `/onboarding` on first launch,
/// `/welcome` afterwards. The auth provider is refreshed here so the
/// router's redirect sees the real session from the first frame on.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  /// Session check with hard timeouts: on some Android devices the secure
  /// storage read can hang (KeyStore) or throw — without a timeout the
  /// splash would spin forever and the app would look stuck (or, if the
  /// first frame never completed, white). Every failure degrades to
  /// "logged out, onboarding unseen" and the app ALWAYS routes.
  Future<void> _route() async {
    final auth = ref.read(authServiceProvider);
    bool loggedIn = false;
    try {
      loggedIn = await ref
          .read(authStateProvider.notifier)
          .refresh()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      loggedIn = false;
    }
    if (!mounted) return;
    if (loggedIn) {
      context.go('/home');
      return;
    }
    bool seenOnboarding = false;
    try {
      seenOnboarding =
          await auth.hasSeenOnboarding().timeout(const Duration(seconds: 8));
    } catch (_) {
      seenOnboarding = false;
    }
    if (!mounted) return;
    context.go(seenOnboarding ? '/welcome' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/artwork/hero-last-horizon.jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.darkBg.withValues(alpha: 0.55),
                  AppColors.darkBg.withValues(alpha: 0.92),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusXl),
                    boxShadow: AppColors.glowShadow,
                  ),
                  child: const Icon(
                    Iconsax.play_copy,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr(context, 'common.appName'),
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(color: AppColors.darkText),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'auth.welcomeTitle'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.darkMuted,
                      ),
                ),
                const Spacer(),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'auth.checkingSession'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
