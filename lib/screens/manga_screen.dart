import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Manga & manhwa tab: "New Chapters" rail, type filter chips
/// (All / Manga / Manhwa), genre filter, sort, search-within-manga and a
/// cover grid. Tap a cover → Details.
class MangaScreen extends ConsumerStatefulWidget {
  const MangaScreen({super.key});

  @override
  ConsumerState<MangaScreen> createState() => _MangaScreenState();
}

enum _MangaSort { rating, year, az }

class _MangaScreenState extends ConsumerState<MangaScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  ContentType? _type; // null = All, manga, or manhwa
  String? _genre; // null = all genres
  _MangaSort _sort = _MangaSort.rating;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ProviderItem> _filtered(List<ProviderItem> comics) {
    final query = _query.toLowerCase();
    final filtered = comics.where((item) {
      if (_type != null && item.type != _type) return false;
      if (_genre != null && !item.genres.contains(_genre)) return false;
      if (query.isNotEmpty &&
          !item.title.toLowerCase().contains(query) &&
          !item.genres.any((g) => g.toLowerCase().contains(query))) {
        return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case _MangaSort.rating:
        filtered.sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
      case _MangaSort.year:
        filtered.sort((a, b) => (b.year ?? -1).compareTo(a.year ?? -1));
      case _MangaSort.az:
        filtered.sort((a, b) => a.title.compareTo(b.title));
    }
    return filtered;
  }

  String _sortKey(_MangaSort sort) => switch (sort) {
        _MangaSort.rating => 'search.sortRating',
        _MangaSort.year => 'search.sortYear',
        _MangaSort.az => 'search.sortAZ',
      };

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<_MangaSort>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.palette.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(context, 'search.sortBy'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final option in _MangaSort.values)
              ListTile(
                title: Text(tr(context, _sortKey(option))),
                trailing: _sort == option
                    ? const Icon(Iconsax.tick_circle_copy, color: AppColors.brand)
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _sort = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final allItems = ref.watch(allEnabledItemsProvider);
    final comics =
        allItems.where((item) => isReadable(item.type)).toList();
    final genres = <String>{};
    for (final item in comics) {
      genres.addAll(item.genres);
    }
    final sortedGenres = genres.toList()..sort();
    final filtered = _filtered(comics);
    final newChapters = comics.where((i) => i.chapters.isNotEmpty).toList()
      ..sort((a, b) {
        final byChapters = b.chapters.length.compareTo(a.chapters.length);
        if (byChapters != 0) return byChapters;
        return (b.rating ?? -1).compareTo(a.rating ?? -1);
      });

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                tr(context, 'manga.title'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchField(
                controller: _controller,
                hintKey: 'manga.searchHint',
                onChanged: (value) =>
                    setState(() => _query = value.trim()),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _typeChip(null, tr(context, 'common.all')),
                  _typeChip(ContentType.manga, tr(context, 'search.typeManga')),
                  _typeChip(
                    ContentType.manhwa,
                    tr(context, 'search.typeManhwa'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _genreDropdown(sortedGenres),
                  ),
                  const SizedBox(width: 12),
                  // FocusableCard (not a bare GestureDetector) so the
                  // sort control is reachable by D-pad on Android TV.
                  FocusableCard(
                    onPressed: _openSortSheet,
                    borderRadius: AppColors.radiusM,
                    child: Container(
                      height: 48,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius:
                            BorderRadius.circular(AppColors.radiusM),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Iconsax.sort_copy,
                              size: 16, color: AppColors.brand),
                          const SizedBox(width: 6),
                          Text(
                            tr(context, _sortKey(_sort)),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: AppColors.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: comics.isEmpty
                  ? EmptyState(
                      title: tr(context, 'manga.emptyTitle'),
                      body: tr(context, 'manga.emptyBody'),
                      icon: Iconsax.book_copy,
                      actionLabel: tr(context, 'home.addProvider'),
                      onAction: () =>
                          context.push('/settings/providers'),
                    )
                  : filtered.isEmpty
                      ? EmptyState(
                          title: tr(context, 'search.noResultsTitle'),
                          body: tr(context, 'search.noResultsBody'),
                          icon: Iconsax.search_normal_copy,
                          actionLabel: tr(context, 'search.clearFilters'),
                          onAction: () => setState(() {
                            _query = '';
                            _controller.clear();
                            _type = null;
                            _genre = null;
                          }),
                        )
                      : CustomScrollView(
                          slivers: [
                            if (newChapters.isNotEmpty &&
                                _query.isEmpty &&
                                _genre == null) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 12, 20, 12),
                                  child: Text(
                                    tr(context, 'manga.newChapters'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 232,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    itemCount: newChapters.length > 10
                                        ? 10
                                        : newChapters.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      final item = newChapters[index];
                                      return FocusableCard(
                                        onPressed: () =>
                                            openDetails(context, item),
                                        child: PosterCard(
                                          poster: posterOf(item),
                                          title: item.title,
                                          subtitle: trParams(
                                            context,
                                            'manga.chaptersCount',
                                            {
                                              'count': item.chapters.length
                                                  .toString()
                                            },
                                          ),
                                          rating: item.rating,
                                          onTap: () =>
                                              openDetails(context, item),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 24, 20, 12),
                                  child: Text(
                                    tr(context, 'manga.browseAll'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                              ),
                            ],
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 4, 20, 24),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.52,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final item = filtered[index];
                                    return FocusableCard(
                                      onPressed: () =>
                                          openDetails(context, item),
                                      child: PosterCard(
                                        poster: posterOf(item),
                                        title: item.title,
                                        subtitle: item.year?.toString() ??
                                            typeLabel(context, item.type),
                                        rating: item.rating,
                                        width: double.infinity,
                                        onTap: () =>
                                            openDetails(context, item),
                                      ),
                                    );
                                  },
                                  childCount: filtered.length,
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(ContentType? type, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChipToggle(
        label: label,
        selected: _type == type,
        onTap: () => setState(() => _type = type),
      ),
    );
  }

  Widget _genreDropdown(List<String> genres) {
    return DropdownButtonFormField<String?>(
      // initialValue is uncontrolled after first build — the key
      // recreates the field when the selection changes externally
      // (e.g. Clear filters), keeping it in sync with the state.
      key: ValueKey(_genre),
      initialValue: _genre,
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(tr(context, 'manga.genreAll')),
        ),
        for (final genre in genres)
          DropdownMenuItem<String?>(
            value: genre,
            child: Text(genre),
          ),
      ],
      onChanged: (value) => setState(() => _genre = value),
    );
  }
}
