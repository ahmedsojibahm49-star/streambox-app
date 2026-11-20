import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../theme/app_theme.dart';

/// Shared auth-screen chrome, matching the Expo app's look: circular glass
/// back button, gradient logo mark, big bold title, muted subtitle.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.showLogo = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null)
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border.all(color: palette.border),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.arrow_left_copy,
                size: 20,
                color: palette.text,
              ),
            ),
          ),
        if (onBack != null) const SizedBox(height: 24),
        if (showLogo) ...[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppColors.radiusM),
              boxShadow: AppColors.glowShadow,
            ),
            child: const Icon(
              Iconsax.play_copy,
              size: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.muted,
              ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Footer link row: muted text + orange tappable link
/// ("Already have an account? Log in").
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.text,
    required this.linkText,
    required this.onTap,
  });

  final String text;
  final String linkText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text(
            '$text ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Text(
              linkText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
