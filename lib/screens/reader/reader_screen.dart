import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../models/models.dart';
import '../../providers/catalog_providers.dart';
import '../../services/library_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/focusable_card.dart';
import '../player/player_logic.dart';
import 'reader_logic.dart';

/// Manga/manhwa reader (route `/reader/:id`).
///
/// Two modes: page-by-page (PageView, tap zones or swipe) and vertical
/// scroll (ListView). Pages are the `pageUrls` the provider JSON supplies
/// for the chapter — loaded with cached_network_image, never scraped.
///
/// Query params: `chapter` (chapter number, defaults to the first) and
/// `mode` (`page` or `vertical`, defaults to `page`).
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.itemId,
    this.chapterNumber,
    this.mode,
  });

  /// Catalog box key of the item (`"$providerId::$itemId"`).
  final String itemId;

  /// Chapter number to start on (from the `chapter` query param).
  final int? chapterNumber;

  /// Reader mode hint (from the `mode` query param).
  final String? mode;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ProviderItem? _item;
  ({String providerId, String itemId})? _keyParts;

  int _chapterIndex = 0;
  int _pageIndex = 0;
  late ReaderMode _mode;
  bool _chromeVisible = true;
  bool _itemLoading = true;

  /// 1.0 = full brightness, 0.0 = darkest. Renders as a black overlay.
  double _brightness = 1.0;

  late PageController _pageController;
  late final ScrollController _scrollController;
  Timer? _scrollSaveDebounce;
  Timer? _notFoundTimer;

  /// Retry nonce per page index — bumping it rebuilds that page's image.
  final Map<int, int> _pageRetryNonce = {};

  List<Map<String, dynamic>> get _chapters => _item?.chapters ?? const [];

  Map<String, dynamic>? get _currentChapter =>
      _chapters.isEmpty ? null : _chapters[_chapterIndex];

  List<String> get _pageUrls =>
      _currentChapter == null ? const [] : chapterPageUrls(_currentChapter!);

  int get _currentChapterNumber => _currentChapter == null
      ? 1
      : chapterNumber(_currentChapter!, fallback: _chapterIndex + 1);

  @override
  void initState() {
    super.initState();
    _mode = parseReaderMode(widget.mode);
    _keyParts = parseBoxKey(widget.itemId);
    _pageController = PageController(initialPage: 0);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    if (_keyParts == null) {
      _itemLoading = false;
    } else {
      // Resolve via the catalog provider (it also triggers the lazy
      // sample-catalog seed). The item may arrive a moment later — the
      // ref.listen in build() picks it up; only after a grace period do
      // we conclude the id is genuinely unknown.
      final item = ref.read(itemByIdProvider(widget.itemId));
      if (item != null) {
        _onItemLoaded(item);
      } else {
        _notFoundTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _item == null) {
            setState(() => _itemLoading = false);
          }
        });
      }
    }
  }

  /// Called once when the catalog item resolves (immediately from initState
  /// or later via the ref.listen in build()).
  void _onItemLoaded(ProviderItem item) {
    _notFoundTimer?.cancel();
    if (_item != null) return;
    _item = item;
    if (_chapters.isNotEmpty) {
      _chapterIndex = chapterIndexFor(_chapters, widget.chapterNumber);
    }
    _pageIndex = _savedPageForCurrentChapter();
    // Rebuild the page controller so it starts on the saved page.
    _pageController.dispose();
    _pageController = PageController(initialPage: _pageIndex);
    if (mounted) {
      setState(() => _itemLoading = false);
    } else {
      _itemLoading = false;
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollSaveDebounce?.cancel();
    _notFoundTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // -- Progress ----------------------------------------------------------------

  /// Saved page for the current chapter, or 0 when there is none.
  int _savedPageForCurrentChapter() {
    final parts = _keyParts;
    if (parts == null || _currentChapter == null) return 0;
    final entry = ref.read(libraryServiceProvider).progressFor(
          itemId: parts.itemId,
          providerId: parts.providerId,
        );
    if (entry == null) return 0;
    if (entry.episodeOrChapter != _currentChapterNumber) return 0;
    return clampPage(entry.page, _pageUrls.length);
  }

  void _saveProgress() {
    final parts = _keyParts;
    if (parts == null || _item == null || _currentChapter == null) return;
    unawaited(
      ref.read(historyProvider.notifier).record(
            itemId: parts.itemId,
            providerId: parts.providerId,
            episodeOrChapter: _currentChapterNumber,
            page: _pageIndex,
          ),
    );
  }

  void _onScroll() {
    if (_mode != ReaderMode.vertical || !mounted) return;
    final controller = _scrollController;
    if (!controller.hasClients || _pageUrls.isEmpty) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final contentHeight =
        position.maxScrollExtent + position.viewportDimension;
    final pageHeight = contentHeight / _pageUrls.length;
    final page = pageFromScrollOffset(
      controller.offset,
      pageHeight,
      _pageUrls.length,
    );
    if (page == _pageIndex) return;
    setState(() => _pageIndex = page);
    // Debounce: don't write history on every scroll tick.
    _scrollSaveDebounce?.cancel();
    _scrollSaveDebounce = Timer(
      const Duration(milliseconds: 500),
      _saveProgress,
    );
  }

  // -- Navigation --------------------------------------------------------------

  void _loadChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    _saveProgress();
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _pageRetryNonce.clear();
    });
    // The saved page only applies to the chapter the screen opened on —
    // a chapter switch always starts at page 0.
    if (_pageController.hasClients) _pageController.jumpToPage(0);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _saveProgress();
  }

  void _goToPage(int page) {
    final total = _pageUrls.length;
    if (total == 0) return;
    if (page < 0) {
      // Past the first page: previous chapter's last page.
      final prev = previousChapterIndex(_chapterIndex);
      if (prev != null) {
        _loadChapter(prev);
        final prevTotal = chapterPageUrls(_chapters[prev]).length;
        final lastPage = clampPage(prevTotal - 1, prevTotal);
        setState(() => _pageIndex = lastPage);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(lastPage);
        }
        _saveProgress();
      }
      return;
    }
    if (page >= total) {
      // Past the last page: next chapter.
      final next = nextChapterIndex(_chapters.length, _chapterIndex);
      if (next != null) _loadChapter(next);
      return;
    }
    setState(() => _pageIndex = page);
    if (_mode == ReaderMode.page && _pageController.hasClients) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    _saveProgress();
  }

  void _onPageChanged(int page) {
    setState(() => _pageIndex = page);
    _saveProgress();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  // -- Sheets ------------------------------------------------------------------

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, 'reader.settings'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Text(
                tr(context, 'reader.readingMode'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ReaderMode>(
                  segments: [
                    ButtonSegment<ReaderMode>(
                      value: ReaderMode.page,
                      icon: const Icon(Iconsax.book_1_copy, size: 18),
                      label: Text(tr(context, 'reader.pageTurn')),
                    ),
                    ButtonSegment<ReaderMode>(
                      value: ReaderMode.vertical,
                      icon: const Icon(Iconsax.arrow_down_1_copy, size: 18),
                      label: Text(tr(context, 'reader.verticalScroll')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    final mode = selection.first;
                    setSheetState(() {});
                    setState(() {
                      _mode = mode;
                      if (mode == ReaderMode.vertical) {
                        // Jump the scroll view to the current page.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_scrollController.hasClients) return;
                          final position = _scrollController.position;
                          if (!position.hasContentDimensions) return;
                          final contentHeight = position.maxScrollExtent +
                              position.viewportDimension;
                          final pageHeight =
                              contentHeight / _pageUrls.length;
                          _scrollController.jumpTo(
                            (_pageIndex * pageHeight)
                                .clamp(0.0, position.maxScrollExtent),
                          );
                        });
                      } else if (_pageController.hasClients) {
                        _pageController.jumpToPage(_pageIndex);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Iconsax.sun_1_copy, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'reader.brightness'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Text(
                    '${(_brightness * 100).round()}%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              Slider(
                value: _brightness,
                min: 0.25,
                max: 1.0,
                divisions: 15,
                activeColor: AppColors.brand,
                onChanged: (value) {
                  setSheetState(() => _brightness = value);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showChapterList() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final palette = context.palette;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, 'reader.chapters'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  itemCount: _chapters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final chapter = _chapters[index];
                    final isCurrent = index == _chapterIndex;
                    final number =
                        chapterNumber(chapter, fallback: index + 1);
                    final pages = chapterPageUrls(chapter).length;
                    return FocusableCard(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _loadChapter(index);
                      },
                      borderRadius: AppColors.radiusM,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.brand.withValues(alpha: 0.12)
                              : palette.card,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusM),
                          border: Border.all(
                            color: isCurrent
                                ? AppColors.brand
                                : palette.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trParams(context, 'reader.chapter', {
                                      'number': number.toString(),
                                    }),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: isCurrent
                                              ? AppColors.brand
                                              : palette.text,
                                        ),
                                  ),
                                  if (chapterTitle(chapter).isNotEmpty)
                                    Text(
                                      chapterTitle(chapter),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              trParams(context, 'reader.pagesCount', {
                                'count': pages.toString(),
                              }),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // React to the catalog item arriving late (lazy sample-catalog seed),
    // disappearing (repo removed mid-read), or refreshing (repo re-fetch
    // updates metadata). State changes run post-frame so a provider
    // notification during build can't call setState mid-build.
    ref.listen<ProviderItem?>(itemByIdProvider(widget.itemId),
        (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next != null && _item == null) {
          _onItemLoaded(next);
        } else if (next == null && _item != null) {
          setState(() {
            _item = null;
            _itemLoading = false;
          });
        } else if (next != null && _item != null) {
          setState(() => _item = next);
        }
      });
    });

    if (_itemLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.brand),
        ),
      );
    }
    if (_item == null || _keyParts == null) {
      return _buildErrorScaffold('reader.itemNotFound');
    }
    if (_chapters.isEmpty) {
      return _buildErrorScaffold('reader.noPages');
    }
    if (_pageUrls.isEmpty) {
      return _buildNoPagesScaffold();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _mode == ReaderMode.page ? _buildPageMode() : _buildVerticalMode(),
          // Brightness dimmer — above the pages, below the chrome.
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(
                alpha: (1.0 - _brightness) * 0.75,
              ),
            ),
          ),
          if (_mode == ReaderMode.page) _buildTapZones(),
          _buildChrome(),
        ],
      ),
    );
  }

  Widget _buildErrorScaffold(String messageKey) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_copy),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Iconsax.book_1_copy,
                size: 48,
                color: AppColors.brand,
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, messageKey),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPagesScaffold() {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_copy),
          onPressed: () => context.pop(),
        ),
        title: Text(_item?.title ?? ''),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Iconsax.book_1_copy,
                size: 48,
                color: AppColors.brand,
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, 'reader.noPages'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              FocusableCard(
                onPressed: _showChapterList,
                borderRadius: 999,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: AppColors.glowShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Iconsax.book_1_copy,
                          size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'reader.chapters'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Evict one page from the image cache so a retry re-downloads it.
  /// Guarded: evictFromCache is async cache I/O and the retry button
  /// fires it unawaited — a throw used to be an unhandled async error.
  /// The index is re-checked because the chapter may have changed since
  /// the page was built.
  void _evictPage(int index) {
    if (index < 0 || index >= _pageUrls.length) return;
    final url = _pageUrls[index];
    unawaited(Future(() async {
      try {
        await CachedNetworkImage.evictFromCache(url);
      } catch (_) {}
    }));
  }

  Widget _buildPageMode() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _pageUrls.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => _ReaderPageImage(
        key: ValueKey(
          '${_chapterIndex}_$index:${_pageRetryNonce[index] ?? 0}',
        ),
        url: _pageUrls[index],
        fit: BoxFit.contain,
        onRetry: () {
          _evictPage(index);
          setState(() {
            _pageRetryNonce[index] = (_pageRetryNonce[index] ?? 0) + 1;
          });
        },
      ),
    );
  }

  Widget _buildVerticalMode() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _pageUrls.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) => _ReaderPageImage(
        key: ValueKey(
          '${_chapterIndex}_$index:${_pageRetryNonce[index] ?? 0}',
        ),
        url: _pageUrls[index],
        fit: BoxFit.fitWidth,
        onRetry: () {
          _evictPage(index);
          setState(() {
            _pageRetryNonce[index] = (_pageRetryNonce[index] ?? 0) + 1;
          });
        },
      ),
    );
  }

  /// Invisible tap zones for page mode: left third = previous page, right
  /// third = next page, center = toggle the chrome. Drags still reach the
  /// PageView (tap and drag recognizers compete; a swipe wins over a tap).
  Widget _buildTapZones() {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToPage(_pageIndex - 1),
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            flex: 4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            flex: 3,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToPage(_pageIndex + 1),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChrome() {
    final total = _pageUrls.length;
    final chapterLabel = trParams(context, 'reader.chapter', {
      'number': _currentChapterNumber.toString(),
    });
    final title = chapterTitle(_currentChapter!);
    return AnimatedOpacity(
      opacity: _chromeVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: Stack(
          children: [
            // Top bar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _chromeIconButton(
                          icon: Iconsax.arrow_left_copy,
                          label: tr(context, 'common.back'),
                          onPressed: () => context.pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _item?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              Text(
                                title.isEmpty
                                    ? chapterLabel
                                    : '$chapterLabel · $title',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        _chromeIconButton(
                          icon: Iconsax.book_1_copy,
                          label: tr(context, 'reader.chapters'),
                          onPressed: _showChapterList,
                        ),
                        const SizedBox(width: 8),
                        _chromeIconButton(
                          icon: Iconsax.setting_2_copy,
                          label: tr(context, 'reader.settings'),
                          onPressed: _showSettingsSheet,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom bar: prev/next chapter + page progress.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _chromeTextButton(
                              label: tr(
                                context,
                                'reader.previousChapter',
                              ),
                              icon: Iconsax.arrow_left_1_copy,
                              onPressed: previousChapterIndex(_chapterIndex) ==
                                      null
                                  ? null
                                  : () => _loadChapter(
                                        previousChapterIndex(
                                          _chapterIndex,
                                        )!,
                                      ),
                            ),
                            const Spacer(),
                            Text(
                              trParams(context, 'reader.page', {
                                'current': (_pageIndex + 1).toString(),
                                'total': total.toString(),
                              }),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            _chromeTextButton(
                              label: tr(context, 'reader.nextChapter'),
                              icon: Iconsax.arrow_right_1_copy,
                              iconAfterLabel: true,
                              onPressed: nextChapterIndex(
                                        _chapters.length,
                                        _chapterIndex,
                                      ) ==
                                      null
                                  ? null
                                  : () => _loadChapter(
                                        nextChapterIndex(
                                          _chapters.length,
                                          _chapterIndex,
                                        )!,
                                      ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: readingProgress(_pageIndex, total),
                            minHeight: 4,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chromeIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FocusableCard(
      onPressed: onPressed,
      borderRadius: 22,
      child: Tooltip(
        message: label,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }

  Widget _chromeTextButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool iconAfterLabel = false,
  }) {
    final enabled = onPressed != null;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: iconAfterLabel
          ? [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 16,
                color: enabled ? Colors.white : Colors.white38,
              ),
            ]
          : [
              Icon(
                icon,
                size: 16,
                color: enabled ? Colors.white : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
    );
    return FocusableCard(
      onPressed: onPressed,
      borderRadius: 999,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
        ),
        child: content,
      ),
    );
  }
}

/// One reader page: cached network image with a loading spinner and an
/// error placeholder with a retry button.
class _ReaderPageImage extends StatelessWidget {
  const _ReaderPageImage({
    super.key,
    required this.url,
    required this.fit,
    required this.onRetry,
  });

  final String url;
  final BoxFit fit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: CircularProgressIndicator(color: AppColors.brand),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Iconsax.warning_2_copy,
              size: 32,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              tr(context, 'reader.failedToLoadPage'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FocusableCard(
              onPressed: onRetry,
              borderRadius: 999,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  tr(context, 'common.retry'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
