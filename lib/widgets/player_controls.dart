import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'focusable_card.dart';

/// Center play/pause button — the branded StreamBox player control.
///
/// A proper play TRIANGLE (Iconsax `play_copy`, Bold) inside an orange
/// gradient circle with glow. The pause state is two clean rounded bars
/// drawn as shapes — never a glyph that could read as "00" (the old broken
/// pause look is banned).
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.size = 72,
    this.autofocus = false,
  });

  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onPressed: onPressed,
      autofocus: autofocus,
      borderRadius: size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: AppColors.glowShadow,
        ),
        alignment: Alignment.center,
        child: isPlaying ? _pauseBars(size) : _playTriangle(size),
      ),
    );
  }

  /// Two clean rounded white bars — the pause glyph, drawn as shapes.
  Widget _pauseBars(double size) {
    final barWidth = size * 0.09;
    final barHeight = size * 0.36;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: barWidth,
          height: barHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(barWidth / 2),
          ),
        ),
        SizedBox(width: size * 0.09),
        Container(
          width: barWidth,
          height: barHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(barWidth / 2),
          ),
        ),
      ],
    );
  }

  /// Iconsax Bold play triangle, nudged right so it reads optically centered.
  Widget _playTriangle(double size) {
    return Padding(
      padding: EdgeInsets.only(left: size * 0.06),
      child: Icon(
        Iconsax.play_copy,
        size: size * 0.42,
        color: Colors.white,
      ),
    );
  }
}

/// Circular translucent icon button for the player overlay (skip, fullscreen,
/// speed, episodes). Focusable with a visible orange ring on TV.
class PlayerControlButton extends StatelessWidget {
  const PlayerControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 24,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onPressed: onPressed,
      borderRadius: size / 2,
      child: Tooltip(
        message: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

/// Seek bar with drag + tap-to-seek, time labels and a buffered indicator.
///
/// [buffered] is the furthest buffered position; it renders as a lighter
/// track segment behind the orange played segment. While the user drags,
/// [onScrub] fires live and [onSeekEnd] fires once on release so the player
/// seeks once instead of on every drag tick.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragFraction;

  double get _maxSeconds => widget.duration.inMilliseconds > 0
      ? widget.duration.inMilliseconds.toDouble()
      : 1;

  double get _playedFraction {
    if (_dragFraction != null) return _dragFraction!;
    if (widget.duration <= Duration.zero) return 0;
    return (widget.position.inMilliseconds / _maxSeconds).clamp(0.0, 1.0);
  }

  double get _bufferedFraction {
    if (widget.duration <= Duration.zero) return 0;
    return (widget.buffered.inMilliseconds / _maxSeconds).clamp(0.0, 1.0);
  }

  Duration _fractionToPosition(double fraction) => Duration(
        milliseconds: (fraction.clamp(0.0, 1.0) * _maxSeconds).round(),
      );

  void _onDragStart(DragStartDetails details, double width) {
    widget.onScrubStart?.call();
    setState(() {
      _dragFraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    setState(() {
      _dragFraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final fraction = _dragFraction;
    setState(() => _dragFraction = null);
    if (fraction != null) widget.onSeek(_fractionToPosition(fraction));
    widget.onScrubEnd?.call();
  }

  void _onTapDown(TapDownDetails details, double width) {
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek(_fractionToPosition(fraction));
  }

  @override
  Widget build(BuildContext context) {
    final shownPosition = _dragFraction == null
        ? widget.position
        : _fractionToPosition(_dragFraction!);
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            Formatters.duration(shownPosition.inSeconds),
            style: labelStyle,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _onTapDown(details, width),
                onHorizontalDragStart: (details) =>
                    _onDragStart(details, width),
                onHorizontalDragUpdate: (details) =>
                    _onDragUpdate(details, width),
                onHorizontalDragEnd: _onDragEnd,
                child: Container(
                  height: 28,
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: _bufferedFraction,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: _playedFraction,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        // The knob is 14px wide, centered on the play head;
                        // clamp it inside the track so it never hangs half
                        // off either edge (at 0% it used to sit at left: -7,
                        // half-clipped; at 100% it stuck out 7px right).
                        left: (_playedFraction * width - 7)
                            .clamp(0.0, width > 14 ? width - 14 : 0.0)
                            .toDouble(),
                        top: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(top: -5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.brand,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            Formatters.duration(widget.duration.inSeconds),
            style: labelStyle,
          ),
        ),
      ],
    );
  }
}
