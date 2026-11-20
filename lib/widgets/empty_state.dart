import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme/app_theme.dart';
import 'ghost_button.dart';

/// Empty-list state: large muted icon in a card circle, title, body and an
/// optional action button. Used by Library, Search (no results) and Manga.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon = Iconsax.folder_copy,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

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
                color: palette.card,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: palette.muted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              GhostButton(
                label: actionLabel!,
                onPressed: onAction,
                width: 200,
                height: 44,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
