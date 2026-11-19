import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// TV-first focusable card: on Android TV (D-pad) it shows a visible orange
/// focus ring + scale-up when focused, and activates on Enter/Space.
/// On mobile it behaves as a plain tap target.
///
/// Wrap any card/row that must be reachable by D-pad navigation.
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.borderRadius = AppColors.radiusM,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final double borderRadius;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.select)) {
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: _focused
                  ? Border.all(color: AppColors.brand, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
              boxShadow: _focused ? AppColors.glowShadow : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius - 2),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
