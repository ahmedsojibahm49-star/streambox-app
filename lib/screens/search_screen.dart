import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/search_history.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Advanced search: debounced text search, recent searches (persisted),
/// trending suggestions, a full filter sheet (type, genres, year range,
/// minimum rating, status, provider), sort options, and per-type result
/// counts.
///
/// Deep links: `/search?type=anime|movie|manga|manhwa` and
/// `/search?q=...` pre-fill the type filter / query (used by Home rails).
///
/// Never blank: with no catalog it explains how to add a provider; with
/// no matches it explains why and offers to clear the filters.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

enum _SortOption { relevance, rating, year, az }

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  ContentType? _type;
  _SortOption _sort = _SortOption.relevance;
  _Filters _filters = const _Filters();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final params = GoRouterState.of(context).uri.queryParameters;
    final typeParam = params['type'];
    if (typeParam != null) {
      _type = switch (typeParam) {
        'anime' => ContentType.anime,
        'movie' => ContentType.movie,
        'manga' => ContentType.manga,
        'manhwa' => ContentType.manhwa,
        _ => null,
      };
    }
    final q = params['q'];
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _query = q;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _onSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).add(query);
    setState(() => _query = query);
  }

  void _searchRecent(String query) {
    _controller.text = query;
    setState(() => _query = query);
  }

  bool get _isIdle =>
      _query.isEmpty && _type == null && !_filters.hasActive;

  Future<void> _openFilterSheet() async {
    final allItems = ref.read(allEnabledItemsProvider);
    final genreSet = <String>{};
    for (final item in allItems) {
      genreSet.addAll(item.genres);
    }
    final genres = genreSet.toList()..sort();
    final repos = ref
        .read(providersListProvider)
        .where((repo) => repo.enabled)
        .toList();
    final years = <int>{};
    for (final item in allItems) {
      if (item.year != null) years.add(item.year!);
    }
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FilterSheet(
        initialType: _type,
        initialFilters: _filters,
        genres: genres,
        providers: repos,
        years: sortedYears,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _type = result.type;
        _filters = result.filters;
      });
    }
  }

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<_SortOption>(
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
            for (final option in _SortOption.values)
              ListTile(
                title: Text(tr(context, _sortKey(option))),
                trailing: _sort == option
                    ? const Icon(Iconsax.tick_circle, color: AppColors.brand)
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

  String _sortKey(_SortOption option) => switch (option) {
        _SortOption.relevance => 'search.sortRelevance',
        _SortOption.rating => 'search.sortRating',
        _SortOption.year => 'search.sortYear',
        _SortOption.az => 'search.sortAZ',
      };

  /// Items matching the query + filters, EXCEPT the type filter (used for
  /// the per-type counts).
  List<ProviderItem> _filteredExceptType(List<ProviderItem> items) {
    final query = _query.toLowerCase();
    return items.where((item) {
      if (query.isNotEmpty) {
        final inTitle = item.title.toLowerCase().contains(query);
        final inGenre = item.genres
            .any((g) => g.toLowerCase().contains(query));
        if (!inTitle && !inGenre) return false;
      }
      if (_filters.genres.isNotEmpty &&
          !_filters.genres.any(item.genres.contains)) {
        return false;
      }
      if (_filters.yearFrom != null &&
          (item.year == null || item.year! < _filters.yearFrom!)) {
        return false;
      }
      if (_filters.yearTo != null &&
          (item.year == null || item.year! > _filters.yearTo!)) {
        return false;
      }
      if (_filters.minRating > 0 &&
          (item.rating == null || item.rating! < _filters.minRating)) {
        return false;
      }
      if (_filters.status != null &&
          item.status?.toLowerCase() != _filters.status) {
        return false;
      }
      if (_filters.providerIds.isNotEmpty &&
          !_filters.providerIds.contains(item.providerId)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<ProviderItem> _sorted(List<ProviderItem> items) {
    final sorted = items.toList();
    final query = _query.toLowerCase();
    switch (_sort) {
      case _SortOption.relevance:
        int score(ProviderItem item) {
          final title = item.title.toLowerCase();
          if (query.isNotEmpty && title.startsWith(query)) return 3;
          if (query.isNotEmpty && title.contains(query)) return 2;
          if (query.isNotEmpty &&
              item.genres.any((g) => g.toLowerCase().contains(query))) {
            return 1;
          }
          return 0;
        }

        sorted.sort((a, b) {
          final byScore = score(b).compareTo(score(a));
          if (byScore != 0) return byScore;
          return (b.rating ?? -1).compareTo(a.rating ?? -1);
        });
      case _SortOption.rating:
        sorted.sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
      case _SortOption.year:
        sorted.sort((a, b) => (b.year ?? -1).compareTo(a.year ?? -1));
      case _SortOption.az:
        sorted.sort((a, b) => a.title.compareTo(b.title));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(allEnabledItemsProvider);
    final base = _filteredExceptType(allItems);
    final typed = _type == null
        ? base
        : base.where((item) => item.type == _type).toList();
    final results = _sorted(typed);
    final counts = <ContentType, int>{
      for (final t in ContentType.values)
        t: base.where((item) => item.type == t).length,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'search.title'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  _FilterButton(
                    activeCount: _filters.activeCount,
                    onPressed: _openFilterSheet,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchField(
                controller: _controller,
                onChanged: _onQueryChanged,
                onSubmitted: _onSubmitted,
              ),
            ),
            const SizedBox(height: 12),
            if (allItems.isNotEmpty) _typeChips(counts, base.length),
            const SizedBox(height: 8),
            Expanded(
              child: allItems.isEmpty
                  ? _noCatalog(context)
                  : _isIdle
                      ? _idleBody(context, allItems)
                      : _resultsBody(context, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChips(Map<ContentType, int> counts, int total) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _countChip(
            label: tr(context, 'common.all'),
            count: total,
            selected: _type == null,
            onTap: () => setState(() => _type = null),
          ),
          for (final type in ContentType.values)
            _countChip(
              label: typeLabel(context, type),
              count: counts[type] ?? 0,
              selected: _type == type,
              onTap: () => setState(() => _type = type),
            ),
        ],
      ),
    );
  }

  Widget _countChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChipToggle(
        label: '$label ($count)',
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  Widget _noCatalog(BuildContext context) {
    return EmptyState(
      title: tr(context, 'search.noCatalogTitle'),
      body: tr(context, 'search.noCatalogBody'),
      icon: Iconsax.folder_open,
      actionLabel: tr(context, 'home.addProvider'),
      onAction: () => context.push('/settings/providers'),
    );
  }

  Widget _idleBody(BuildContext context, List<ProviderItem> allItems) {
    final recent = ref.watch(searchHistoryProvider);
    final trending = allItems.toList()
      ..sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
    final topTrending = trending.take(10).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr(context, 'search.recent'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(searchHistoryProvider.notifier).clear(),
                  child: Text(
                    tr(context, 'search.clearAll'),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.brand),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in recent)
                  ChipToggle(
                    label: query,
                    selected: false,
                    icon: Iconsax.clock,
                    onTap: () => _searchRecent(query),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            tr(context, 'search.trending'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: topTrending.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = topTrending[index];
              return FocusableCard(
                onPressed: () => openDetails(context, item),
                child: PosterCard(
                  poster: posterOf(item),
                  title: item.title,
                  subtitle: item.year?.toString() ??
                      typeLabel(context, item.type),
                  rating: item.rating,
                  onTap: () => openDetails(context, item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _resultsBody(BuildContext context, List<ProviderItem> results) {
    if (results.isEmpty) {
      return EmptyState(
        title: tr(context, 'search.noResultsTitle'),
        body: tr(context, 'search.noResultsBody'),
        icon: Iconsax.search_normal,
        actionLabel: _filters.hasActive || _type != null
            ? tr(context, 'search.clearFilters')
            : null,
        onAction: _filters.hasActive || _type != null
            ? () => setState(() {
                  _filters = const _Filters();
                  _type = null;
                })
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _query.isNotEmpty
                      ? trParams(context, 'search.resultsFor',
                          {'query': _query})
                      : trParams(context, 'search.resultsCount',
                          {'count': results.length.toString()}),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.palette.muted,
                      ),
                ),
              ),
              GestureDetector(
                onTap: _openSortSheet,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Iconsax.sort, size: 16, color: AppColors.brand),
                    const SizedBox(width: 4),
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
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.52,
            ),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              return FocusableCard(
                onPressed: () => openDetails(context, item),
                child: PosterCard(
                  poster: posterOf(item),
                  title: item.title,
                  subtitle: item.year?.toString() ??
                      typeLabel(context, item.type),
                  rating: item.rating,
                  width: double.infinity,
                  onTap: () => openDetails(context, item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Filter state (everything except the type, which the screen owns).
class _Filters {
  const _Filters({
    this.genres = const {},
    this.yearFrom,
    this.yearTo,
    this.minRating = 0,
    this.status,
    this.providerIds = const {},
  });

  final Set<String> genres;
  final int? yearFrom;
  final int? yearTo;
  final double minRating;
  final String? status; // 'ongoing' | 'completed'
  final Set<String> providerIds;

  bool get hasActive =>
      genres.isNotEmpty ||
      yearFrom != null ||
      yearTo != null ||
      minRating > 0 ||
      status != null ||
      providerIds.isNotEmpty;

  int get activeCount =>
      genres.length +
      (yearFrom != null ? 1 : 0) +
      (yearTo != null ? 1 : 0) +
      (minRating > 0 ? 1 : 0) +
      (status != null ? 1 : 0) +
      providerIds.length;

  _Filters copyWith({
    Set<String>? genres,
    int? yearFrom,
    int? yearTo,
    double? minRating,
    String? status,
    Set<String>? providerIds,
    bool clearYearFrom = false,
    bool clearYearTo = false,
    bool clearStatus = false,
  }) =>
      _Filters(
        genres: genres ?? this.genres,
        yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
        yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
        minRating: minRating ?? this.minRating,
        status: clearStatus ? null : (status ?? this.status),
        providerIds: providerIds ?? this.providerIds,
      );
}

class _FilterResult {
  const _FilterResult({required this.type, required this.filters});

  final ContentType? type;
  final _Filters filters;
}

/// Filter icon button with an orange count badge when filters are active.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.filter,
              size: 18,
              color: activeCount > 0 ? AppColors.brand : palette.text,
            ),
            const SizedBox(width: 6),
            Text(
              tr(context, 'search.filters'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  activeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet filter editor. Edits a draft copy; Apply returns the new
/// type + filters, Clear resets the draft (Apply still needed to confirm).
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialType,
    required this.initialFilters,
    required this.genres,
    required this.providers,
    required this.years,
  });

  final ContentType? initialType;
  final _Filters initialFilters;
  final List<String> genres;
  final List<ProviderRepo> providers;
  final List<int> years;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ContentType? _type;
  late _Filters _draft;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _draft = widget.initialFilters;
  }

  void _toggleGenre(String genre) {
    final next = Set<String>.from(_draft.genres);
    if (!next.remove(genre)) next.add(genre);
    setState(() => _draft = _draft.copyWith(genres: next));
  }

  void _toggleProvider(String id) {
    final next = Set<String>.from(_draft.providerIds);
    if (!next.remove(id)) next.add(id);
    setState(() => _draft = _draft.copyWith(providerIds: next));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr(context, 'search.filters'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _type = null;
                      _draft = const _Filters();
                    }),
                    child: Text(
                      tr(context, 'search.clearAll'),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.brand),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  _sectionLabel(context, 'search.allTypes'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChipToggle(
                        label: tr(context, 'common.all'),
                        selected: _type == null,
                        onTap: () => setState(() => _type = null),
                      ),
                      for (final type in ContentType.values)
                        ChipToggle(
                          label: typeLabel(context, type),
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                    ],
                  ),
                  if (widget.genres.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionLabel(context, 'search.genres'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final genre in widget.genres)
                          ChipToggle(
                            label: genre,
                            selected: _draft.genres.contains(genre),
                            onTap: () => _toggleGenre(genre),
                          ),
                      ],
                    ),
                  ],
                  if (widget.years.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionLabel(context, 'search.yearFrom'),
                    Row(
                      children: [
                        Expanded(
                          child: _yearDropdown(
                            value: _draft.yearFrom,
                            hint: tr(context, 'search.yearFrom'),
                            onChanged: (v) => setState(() => _draft =
                                _draft.copyWith(
                                    yearFrom: v, clearYearFrom: v == null)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _yearDropdown(
                            value: _draft.yearTo,
                            hint: tr(context, 'search.yearTo'),
                            onChanged: (v) => setState(() => _draft =
                                _draft.copyWith(
                                    yearTo: v, clearYearTo: v == null)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr(context, 'search.minRating'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _draft.minRating <= 0
                            ? tr(context, 'search.anyRating')
                            : _draft.minRating.toStringAsFixed(1),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: AppColors.brand),
                      ),
                    ],
                  ),
                  Slider(
                    value: _draft.minRating,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    activeColor: AppColors.brand,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(minRating: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionLabel(context, 'search.status'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChipToggle(
                        label: tr(context, 'search.statusAny'),
                        selected: _draft.status == null,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(clearStatus: true),
                        ),
                      ),
                      ChipToggle(
                        label: tr(context, 'details.ongoing'),
                        selected: _draft.status == 'ongoing',
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(status: 'ongoing'),
                        ),
                      ),
                      ChipToggle(
                        label: tr(context, 'details.completed'),
                        selected: _draft.status == 'completed',
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(status: 'completed'),
                        ),
                      ),
                    ],
                  ),
                  if (widget.providers.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionLabel(context, 'search.providers'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChipToggle(
                          label: tr(context, 'search.allProviders'),
                          selected: _draft.providerIds.isEmpty,
                          onTap: () => setState(
                            () =>
                                _draft = _draft.copyWith(providerIds: {}),
                          ),
                        ),
                        for (final repo in widget.providers)
                          ChipToggle(
                            label: repo.name,
                            selected: _draft.providerIds.contains(repo.id),
                            onTap: () => _toggleProvider(repo.id),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  GradientButton(
                    label: tr(context, 'search.applyFilters'),
                    onPressed: () => Navigator.of(context).pop(
                      _FilterResult(type: _type, filters: _draft),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        tr(context, key),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  Widget _yearDropdown({
    required int? value,
    required String hint,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int?>(
      // initialValue is uncontrolled after first build — the key
      // recreates the field when the selection changes externally
      // (e.g. Clear all), keeping it in sync with the draft.
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(hintText: hint),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(tr(context, 'search.anyYear')),
        ),
        for (final year in widget.years)
          DropdownMenuItem<int?>(
            value: year,
            child: Text(year.toString()),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
