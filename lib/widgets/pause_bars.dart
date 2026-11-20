import 'package:material_ui/material_ui.dart';

/// Pause glyph drawn as two clean rounded bars — never a font glyph.
///
/// The Iconsax pause glyph (`Iconsax.pause_copy`) is two fat rounded
/// bars that read as "00" at small sizes (the episode-row circle renders
/// it at 18px). These bars are tall, narrow rectangles with a gap equal to
/// one bar width, so they read as pause at any size. Same treatment as the
/// big center play/pause button; use this widget anywhere a pause glyph
/// renders small.
class PauseBars extends StatelessWidget {
  const PauseBars({super.key, this.height = 18, this.color = Colors.white});

  /// Height of each bar (the glyph's total height).
  final double height;

  /// Bar color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Tall + narrow: each bar is ~1/4 as wide as it is tall, and the gap
    // equals one bar width. A square-ish bar is what made the old glyph
    // read as "00".
    final barWidth = height * 0.28;
    final gap = height * 0.28;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(barWidth),
        SizedBox(width: gap),
        _bar(barWidth),
      ],
    );
  }

  Widget _bar(double width) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
