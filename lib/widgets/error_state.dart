import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import 'gradient_button.dart';

/// Error state: warning icon, message and a Retry button.
/// Used when a repo fetch, backup or load fails.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.warning_2_copy,
                size: 32,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'common.error'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.muted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              GradientButton(
                label: tr(context, 'common.retry'),
                onPressed: onRetry,
                width: 180,
                height: 44,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
