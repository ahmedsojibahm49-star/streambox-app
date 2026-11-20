import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// Onboarding: 3 full-bleed artwork pages (same premium feel as the Expo
/// app), title + body, page dots, Skip, Next, and a final gradient
/// "Get Started" that routes to `/welcome`.
///
/// Finishing (or skipping) marks onboarding seen via the auth service so
/// the splash screen routes returning users straight to `/welcome`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const List<_Slide> _slides = [
    _Slide(
      image: 'assets/artwork/hero-last-horizon.jpg',
      titleKey: 'onboarding.slide1Title',
      bodyKey: 'onboarding.slide1Body',
    ),
    _Slide(
      image: 'assets/artwork/midnight-city-wide.jpg',
      titleKey: 'onboarding.slide2Title',
      bodyKey: 'onboarding.slide2Body',
    ),
    _Slide(
      image: 'assets/artwork/neon-frontier-skyline-wide.jpg',
      titleKey: 'onboarding.slide3Title',
      bodyKey: 'onboarding.slide3Body',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      await ref.read(authServiceProvider).markOnboardingSeen();
    } catch (_) {
      // Best-effort: onboarding still ends at /welcome even if the
      // flag write fails.
    }
    if (mounted) context.go('/welcome');
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isLast = _index == _slides.length - 1;
    final slide = _slides[_index];
    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          // Full-bleed artwork pages with a bottom scrim.
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final page = _slides[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(src: page.image),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                          palette.bg.withValues(alpha: 0.55),
                          palette.bg,
                        ],
                        stops: const [0.0, 0.4, 0.75, 1.0],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Top bar: brand + Skip.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusS),
                          boxShadow: AppColors.glowShadow,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Iconsax.play_copy,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        tr(context, 'common.appName'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _finish,
                    child: Text(
                      tr(context, 'common.skip'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom content: dots, title, body, CTA.
          Positioned(
            left: 24,
            right: 24,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: i == _index ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: i == _index
                                ? AppColors.primaryGradient
                                : null,
                            color: i == _index
                                ? null
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr(context, slide.titleKey),
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, slide.bodyKey),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: palette.muted),
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: isLast
                        ? tr(context, 'common.getStarted')
                        : tr(context, 'common.next'),
                    icon: isLast ? Iconsax.play_copy : Iconsax.arrow_right_copy,
                    onPressed: _next,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.image,
    required this.titleKey,
    required this.bodyKey,
  });

  final String image;
  final String titleKey;
  final String bodyKey;
}
