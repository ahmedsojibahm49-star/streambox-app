import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Filter chip. Selected = orange gradient pill with white text;
/// unselected = card pill with hairline border. Taps call [onTap] —
/// the parent owns the selected state (single- or multi-select).
class ChipToggle extends StatelessWidget {
  const ChipToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : palette.card,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : palette.muted,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? Colors.white : palette.text,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
