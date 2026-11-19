/// Display formatters for durations, ratings, counts and dates shown on
/// cards, detail screens and the player/reader. Pure functions — no context.
class Formatters {
  Formatters._();

  /// Seconds -> `H:MM:SS` when >= 1h, otherwise `M:SS`.
  /// Used by the video player scrubber and episode runtimes.
  static String duration(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  /// Seconds -> long form, e.g. `1h 23m`, `45m`, `30s`.
  static String durationLong(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  /// Rating (0–10) with one decimal, e.g. 8.4 -> `8.4`.
  static String rating(double? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(1);
  }

  /// Compact count: 12500 -> `12.5k`, 999 -> `999`.
  static String compactCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }

  /// `2026` from a year int, `—` when null.
  static String year(int? value) => value == null ? '—' : value.toString();
}
