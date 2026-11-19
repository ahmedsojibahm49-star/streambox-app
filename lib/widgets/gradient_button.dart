import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Primary CTA: orange gradient, glow shadow, pressed-scale animation.
/// Full width by default; pass [width] to constrain.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.width,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double? width;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedScale(
      scale: _pressed && _enabled ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled ? widget.onPressed : null,
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient:
                _enabled ? AppColors.primaryGradient : null,
            color: _enabled ? null : palette.card,
            borderRadius: BorderRadius.circular(AppColors.radiusM),
            boxShadow: _enabled ? AppColors.glowShadow : null,
            border: _enabled
                ? null
                : Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: palette.onBrand,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 20,
                        color: _enabled ? palette.onBrand : palette.muted,
                      ),
                      const SizedBox(width: 8),
                    ],
                    // The label is Flexible + ellipsis: a long label (or a
                    // large system font scale / a wide Bangla label) must
                    // ellipsize inside the button, never overflow it — the
                    // old bare Text overdrew the neighbouring button at
                    // 360px ("Resume episo…" over the bookmark button).
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: _enabled
                                      ? palette.onBrand
                                      : palette.muted,
                                ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
