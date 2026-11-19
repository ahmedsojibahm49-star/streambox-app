import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'app_image.dart';
import 'rating_badge.dart';

/// 16:9 backdrop card with a bottom gradient scrim and the title overlaid.
/// Used for hero rows, trending rails and continue-watching cards.
class WideCard extends StatelessWidget {
  const WideCard({
    super.key,
    required this.backdrop,
    required this.title,
    this.subtitle,
    this.rating,
    this.width = 280,
    this.progress,
    this.onTap,
  });

  /// Asset path or remote URL (see [AppImage]).
  final String backdrop;
  final String title;
  final String? subtitle;
  final double? rating;

  /// Card width; height is width * 9/16.
  final double width;

  /// 0.0–1.0 watch progress; null hides the progress bar.
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final height = width * 9 / 16;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          child: Stack(
            children: [
              AppImage(src: backdrop, width: width, height: height),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
              if (rating != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: RatingBadge(rating: rating!),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                      ),
                    if (progress != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0, 1),
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.brand,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
