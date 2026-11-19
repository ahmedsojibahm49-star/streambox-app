/// Reader modes. `page` = one page at a time (PageView, tap zones or
/// swipe); `vertical` = continuous vertical scroll (ListView).
enum ReaderMode { page, vertical }

/// Parse the `mode` query param on the `/reader/:id` route.
/// `vertical`/`scroll` select vertical mode; anything else (including null)
/// selects page mode.
ReaderMode parseReaderMode(String? value) {
  final mode = value?.trim().toLowerCase();
  if (mode == 'vertical' || mode == 'scroll') return ReaderMode.vertical;
  return ReaderMode.page;
}

/// Chapter number from a chapter map. Falls back to [fallback] (the list
/// position + 1) when the map has no usable `number` field.
int chapterNumber(Map<String, dynamic> chapter, {int fallback = 1}) {
  final raw = chapter['number'];
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw.toInt() > 0) return raw.toInt();
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed > 0) return parsed;
  }
  return fallback;
}

/// Chapter title from a chapter map. Empty when the map has no title.
String chapterTitle(Map<String, dynamic> chapter) {
  final value = chapter['title'];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return '';
}

/// Page image URLs for a chapter. Only http(s) URLs survive — anything else
/// is dropped so the reader never tries to load a junk source.
List<String> chapterPageUrls(Map<String, dynamic> chapter) {
  final raw = chapter['pageUrls'];
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((url) => url.trim())
      .where(
        (url) => url.startsWith('http://') || url.startsWith('https://'),
      )
      .toList(growable: false);
}

/// Index of the chapter with [number] in [chapters], or 0 when [number] is
/// null or no chapter has that number. Never out of range.
int chapterIndexFor(List<Map<String, dynamic>> chapters, int? number) {
  if (chapters.isEmpty) return 0;
  if (number != null) {
    for (var i = 0; i < chapters.length; i++) {
      if (chapterNumber(chapters[i], fallback: i + 1) == number) return i;
    }
  }
  return 0;
}

/// Index of the next chapter after [currentIndex], or null at the end.
int? nextChapterIndex(int chapterCount, int currentIndex) {
  if (currentIndex < 0 || currentIndex + 1 >= chapterCount) return null;
  return currentIndex + 1;
}

/// Index of the previous chapter before [currentIndex], or null at the start.
int? previousChapterIndex(int currentIndex) {
  if (currentIndex <= 0) return null;
  return currentIndex - 1;
}

/// Clamp a page index into `[0, totalPages - 1]`. 0 when there are no pages.
int clampPage(int page, int totalPages) {
  if (totalPages <= 0) return 0;
  if (page < 0) return 0;
  if (page >= totalPages) return totalPages - 1;
  return page;
}

/// Reading progress as a 0.0–1.0 fraction (page is 0-based, so the last page
/// reads as 1.0). 0 when there are no pages.
double readingProgress(int page, int totalPages) {
  if (totalPages <= 0) return 0;
  return (clampPage(page, totalPages) + 1) / totalPages;
}

/// Which page a vertical-scroll offset is showing, given each page renders
/// [pageHeight] tall. Clamped to the chapter bounds.
int pageFromScrollOffset(
  double offset,
  double pageHeight,
  int totalPages,
) {
  if (totalPages <= 0 || pageHeight <= 0) return 0;
  return clampPage((offset / pageHeight).floor(), totalPages);
}
