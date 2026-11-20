import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// Developer page (`/developer`) — a full page, not a dialog (v1.0.4).
/// Reached from Profile → Developer and Settings → Developer. Shows the
/// developer photo, name, role, app version and a short bio.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'profile.developer'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // Photo with a gradient ring + glow.
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  boxShadow: AppColors.glowShadow,
                ),
                child: CircleAvatar(
                  radius: 68,
                  backgroundColor: palette.card,
                  backgroundImage: const AssetImage(
                    'assets/images/developer_photo.jpg',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr(context, 'profile.developerName'),
              textAlign: TextAlign.center,
              style: textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'developer.role'),
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                    color: AppColors.brand,
                  ),
            ),
            const SizedBox(height: 16),
            // App version pill.
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  tr(context, 'settings.aboutVersion'),
                  style: textTheme.labelMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Bio card.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius:
                    BorderRadius.circular(AppColors.radiusL),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppColors.radiusM,
                          ),
                        ),
                        child: const Icon(
                          Iconsax.code_copy,
                          size: 20,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        tr(context, 'common.appName'),
                        style: textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'developer.bio'),
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
