import 'package:material_ui/material_ui.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// Rail header: bold title on the left, orange "See all" on the right.
/// [onSeeAll] null hides the action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
  });

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                tr(context, 'common.seeAll'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.brand,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
