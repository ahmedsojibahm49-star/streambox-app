import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Secondary button: transparent background, hairline border, text-colour
/// label. Used for Cancel / secondary actions next to [GradientButton].
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.width,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null;
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null
            ? null
            : Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? palette.text : palette.muted,
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusM),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
