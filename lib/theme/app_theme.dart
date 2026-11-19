import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current theme mode. Persisted to the settings box; main.dart seeds it
/// from there at startup. The settings screen updates this provider AND
/// writes the settings box (see CONTRACT.md settings pattern). Update via
/// `ref.read(themeModeProvider.notifier).setThemeMode(...)`.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier([this._initial = ThemeMode.system]);

  final ThemeMode _initial;

  @override
  ThemeMode build() => _initial;

  void setThemeMode(ThemeMode mode) => state = mode;
}

/// StreamBox design tokens (from the Figma file "StreamBox — Provider App").
/// Single source of truth for colour, radius, gradient and type — screens
/// must use these, never hard-coded hex values.
///
/// Brand: orange #FF7700 -> #F03A02 gradient. Dark-first (dark bg #09090D),
/// Light theme provided for the settings toggle.
class AppColors {
  AppColors._();

  // Brand (same in both themes).
  static const Color brand = Color(0xFFFF7700);
  static const Color brandEnd = Color(0xFFF03A02);
  static const Color brandSoft = Color(0xFFFF8A3D);

  /// Orange gradient used by primary buttons, active tab dots, hero glows.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [brand, brandEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Orange glow for primary CTAs (blur 24, alpha 0.45).
  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: brand.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  // Radii.
  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 20;
  static const double radiusXl = 24;

  // Dark palette.
  static const Color darkBg = Color(0xFF09090D);
  static const Color darkSurface = Color(0xFF131318);
  static const Color darkCard = Color(0xFF1C1C22);
  static const Color darkText = Color(0xFFF5F5F7);
  static const Color darkMuted = Color(0xFF9C9CA6);

  // Light palette.
  static const Color lightBg = Color(0xFFF2F2F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF111114);
  static const Color lightMuted = Color(0xFF6E6E77);

  // Status.
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
}

/// Brightness-resolved palette. Access via `context.palette`.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.card,
    required this.border,
    required this.text,
    required this.muted,
    required this.onBrand,
  });

  const AppPalette.dark()
      : brightness = Brightness.dark,
        bg = AppColors.darkBg,
        surface = AppColors.darkSurface,
        card = AppColors.darkCard,
        border = const Color(0x14FFFFFF), // white 8%
        text = AppColors.darkText,
        muted = AppColors.darkMuted,
        onBrand = const Color(0xFFFFFFFF);

  const AppPalette.light()
      : brightness = Brightness.light,
        bg = AppColors.lightBg,
        surface = AppColors.lightSurface,
        card = AppColors.lightCard,
        border = const Color(0x14000000), // black 8%
        text = AppColors.lightText,
        muted = AppColors.lightMuted,
        onBrand = const Color(0xFFFFFFFF);

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color card;

  /// Hairline border: white 8% on dark, black 8% on light.
  final Color border;
  final Color text;
  final Color muted;

  /// Text/icon colour on top of the orange gradient.
  final Color onBrand;

  bool get isDark => brightness == Brightness.dark;
}

extension PaletteContext on BuildContext {
  AppPalette get palette {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark
        ? const AppPalette.dark()
        : const AppPalette.light();
  }
}

/// ThemeData builders. `main.dart` picks dark/light by the settings box
/// (default: system).
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Inter';

  /// Bangla fallback — Hind Siliguri renders bn strings; Inter has no
  /// Bengali glyphs.
  static const List<String> fontFamilyFallback = ['HindSiliguri'];

  static ThemeData dark() => _build(const AppPalette.dark());

  static ThemeData light() => _build(const AppPalette.light());

  static ThemeData _build(AppPalette p) {
    final textTheme = _textTheme(p);
    return ThemeData(
      brightness: p.brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: AppColors.brand,
        onPrimary: p.onBrand,
        secondary: AppColors.brandEnd,
        onSecondary: p.onBrand,
        surface: p.surface,
        onSurface: p.text,
        error: AppColors.danger,
        onError: const Color(0xFFFFFFFF),
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        hintStyle: TextStyle(color: p.muted, fontSize: 15),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: AppColors.brand,
        labelStyle: TextStyle(color: p.text, fontSize: 13),
        secondaryLabelStyle:
            const TextStyle(color: Colors.white, fontSize: 13),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: AppColors.brand,
        unselectedItemColor: p.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusL),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppColors.radiusL),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.card,
        contentTextStyle: TextStyle(color: p.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusS),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme _textTheme(AppPalette p) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      Color? color,
      double? height,
      double? letterSpacing,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: size,
          fontWeight: weight,
          color: color ?? p.text,
          height: height,
          letterSpacing: letterSpacing,
        );

    return TextTheme(
      displayLarge: style(size: 34, weight: FontWeight.w700, height: 1.15),
      displayMedium: style(size: 28, weight: FontWeight.w700, height: 1.2),
      headlineLarge: style(size: 24, weight: FontWeight.w700, height: 1.25),
      headlineMedium: style(size: 20, weight: FontWeight.w600, height: 1.3),
      titleLarge: style(size: 18, weight: FontWeight.w600, height: 1.35),
      titleMedium: style(size: 16, weight: FontWeight.w600, height: 1.4),
      titleSmall: style(size: 14, weight: FontWeight.w600, height: 1.4),
      bodyLarge: style(size: 16, weight: FontWeight.w400, height: 1.5),
      bodyMedium: style(size: 14, weight: FontWeight.w400, height: 1.5),
      bodySmall:
          style(size: 12, weight: FontWeight.w400, height: 1.5, color: p.muted),
      labelLarge: style(size: 15, weight: FontWeight.w600, height: 1.4),
      labelMedium: style(size: 13, weight: FontWeight.w500, height: 1.4),
      labelSmall:
          style(size: 11, weight: FontWeight.w500, height: 1.4, color: p.muted),
    );
  }
}
