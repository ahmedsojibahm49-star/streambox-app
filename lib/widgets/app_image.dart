import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme/app_theme.dart';

/// Image that accepts either a bundled asset path (`assets/...`) or a
/// remote URL. Remote images go through CachedNetworkImage (disk cache);
/// failures show a muted placeholder instead of crashing the card.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  /// Asset path (`assets/artwork/...`) or http(s) URL. Empty/null-safe
  /// callers should pass a non-empty string; empty shows the placeholder.
  final String src;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _placeholder(context);
    if (src.startsWith('assets/')) {
      return Image.asset(
        src,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, _) => _placeholder(context),
      errorWidget: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      height: height,
      color: palette.card,
      alignment: Alignment.center,
      child: Icon(Iconsax.image_copy, size: 32, color: palette.muted),
    );
  }
}
