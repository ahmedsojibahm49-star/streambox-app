import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// Welcome: artwork/gradient hero, StreamBox wordmark, "Create account"
/// gradient button → `/signup`, "Log in" ghost button → `/login`.
///
/// NO demo account anywhere — auth is local sign-up → device code → login
/// (CONTRACT.md hard boundaries).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Hero art, top ~60%, fading into the background.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const AppImage(src: 'assets/artwork/hero-last-horizon.jpg'),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        palette.bg.withValues(alpha: 0.6),
                        palette.bg,
                      ],
                      stops: const [0.0, 0.45, 0.8, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusM),
                          boxShadow: AppColors.glowShadow,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Iconsax.play_copy,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        tr(context, 'common.appName'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    tr(context, 'auth.welcomeTitle'),
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'auth.welcomeSubtitle'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: palette.muted),
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: tr(context, 'auth.createAccount'),
                    icon: Iconsax.user_copy,
                    onPressed: () => context.push('/signup'),
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: tr(context, 'auth.login'),
                    icon: Iconsax.login_1_copy,
                    onPressed: () => context.push('/login'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
