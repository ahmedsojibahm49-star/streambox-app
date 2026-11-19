import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'app_image.dart';
import 'rating_badge.dart';

/// 2:3 poster card with rounded corners, title + optional subtitle below,
/// and a rating badge overlaid on the poster. Used in rails and grids.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.poster,
    required this.title,
    this.subtitle,
    this.rating,
    this.width = 120,
    this.onTap,
  });

  /// Asset path or remote URL (see [AppImage]).
  final String poster;
  final String title;
  final String? subtitle;
  final double? rating;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusM),
              child: Stack(
                children: [
                  AppImage(
                    src: poster,
                    width: width,
                    height: width * 1.5,
                  ),
                  if (rating != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: RatingBadge(rating: rating!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.muted),
              ),
          ],
        ),
      ),
    );
  }
}
