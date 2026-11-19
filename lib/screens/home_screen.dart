import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../services/provider_service.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Home feed: hero carousel (auto-advancing, dots), Continue Watching,
/// and rails per type — Trending Anime, Movies, Manga & Manhwa, New
/// Chapters. Pull-to-refresh re-fetches every enabled provider.
///
/// Never blank: with no providers/items the screen shows an empty state
/// with an "Add a provider" action instead of an empty list.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _heroController = PageController();
  Timer? _heroTimer;
  int _heroIndex = 0;

  @override
  void initState() {
    super.initState();
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_heroController.hasClients) return;
      // Hero shows the top 5 rated items (see build); wrap at the end.
      final itemCount = ref.read(allEnabledItemsProvider).length;
      final heroCount = itemCount > 5 ? 5 : itemCount;
      if (heroCount <= 1) return;
      final next = (_heroIndex + 1) % heroCount;
      _heroController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  String _greetingKey() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'home.greetingMorning';
    if (hour < 17) return 'home.greetingAfternoon';
    return 'home.greetingEvening';
  }

  Future<void> _refresh() async {
    try {
      await ref.read(providerServiceProvider).refreshAll();
    } catch (_) {
      // The providers stub throws until the providers workstream lands;
      // a real failure shows the same honest message.
      if (mounted) showSnack(context, tr(context, 'home.refreshFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(allEnabledItemsProvider);
    final profile =
        Hive.box<UserProfile>(BoxNames.profile).get('current');

    if (items.isEmpty) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.brand,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
              EmptyState(
                title: tr(context, 'home.emptyTitle'),
                body: tr(context, 'home.emptyBody'),
                icon: Iconsax.folder_open,
                actionLabel: tr(context, 'home.addProvider'),
                onAction: () => context.push('/settings/providers'),
              ),
            ],
          ),
        ),
      );
    }

    final heroItems = _topRated(items, 5);
    final continueWatching = ref.watch(continueWatchingProvider);
    final catalogByKey = {for (final item in items) item.boxKey: item};
    final anime = _byTypeSorted(items, ContentType.anime);
    final movies = _byTypeSorted(items, ContentType.movie);
    final comics = items
        .where((i) => isReadable(i.type))
        .toList()
      ..sort(_byRatingDesc);
    final newChapters = comics.where((i) => i.chapters.isNotEmpty).toList()
      ..sort((a, b) {
        final byChapters = b.chapters.length.compareTo(a.chapters.length);
        if (byChapters != 0) return byChapters;
        return _byRatingDesc(a, b);
      });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.brand,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context, profile?.name)),
            SliverToBoxAdapter(
              child: _heroCarousel(context, heroItems),
            ),
            if (continueWatching.isNotEmpty)
              SliverToBoxAdapter(
                child: _continueWatchingRail(
                  context,
                  continueWatching,
                  catalogByKey,
                ),
              ),
            if (anime.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  context,
                  title: tr(context, 'home.trendingAnime'),
                  items: anime,
                  onSeeAll: () => context.go('/search?type=anime'),
                ),
              ),
            if (movies.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  context,
                  title: tr(context, 'home.moviesRow'),
                  items: movies,
                  onSeeAll: () => context.go('/search?type=movie'),
                ),
              ),
            if (comics.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  context,
                  title: tr(context, 'home.mangaRow'),
                  items: comics,
                  onSeeAll: () => context.go('/manga'),
                ),
              ),
            if (newChapters.isNotEmpty)
              SliverToBoxAdapter(
                child: _rail(
                  context,
                  title: tr(context, 'home.newChapters'),
                  items: newChapters,
                  subtitle: (item) => trParams(
                    context,
                    'manga.chaptersCount',
                    {'count': item.chapters.length.toString()},
                  ),
                  onSeeAll: () => context.go('/manga'),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String? name) {
    final palette = context.palette;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppColors.radiusM),
                boxShadow: AppColors.glowShadow,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Iconsax.play_copy,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, _greetingKey()),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
                  Text(
                    name ?? tr(context, 'common.appName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Iconsax.search_normal,
                color: palette.text,
              ),
              onPressed: () => context.go('/search'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCarousel(BuildContext context, List<ProviderItem> heroItems) {
    final palette = context.palette;
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 380,
          child: PageView.builder(
            controller: _heroController,
            itemCount: heroItems.length,
            onPageChanged: (index) => setState(() => _heroIndex = index),
            itemBuilder: (context, index) {
              final item = heroItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusL),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppImage(src: backdropOf(item)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.88),
                            ],
                            stops: const [0.3, 0.65, 1.0],
                          ),
                        ),
                      ),
                      if (item.rating != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: RatingBadge(rating: item.rating!),
                        ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              typeLabel(context, item.type).toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.brandSoft,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _heroMeta(context, item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.75),
                                  ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: GradientButton(
                                    label: isReadable(item.type)
                                        ? tr(context, 'details.readNow')
                                        : tr(context, 'details.watchNow'),
                                    icon: Iconsax.play_copy,
                                    height: 44,
                                    onPressed: () =>
                                        openPlay(context, item),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GhostButton(
                                    label: tr(context, 'home.details'),
                                    height: 44,
                                    onPressed: () =>
                                        openDetails(context, item),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < heroItems.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _heroIndex ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  gradient:
                      i == _heroIndex ? AppColors.primaryGradient : null,
                  color: i == _heroIndex
                      ? null
                      : palette.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _heroMeta(BuildContext context, ProviderItem item) {
    final parts = <String>[];
    if (item.year != null) parts.add(item.year.toString());
    if (item.genres.isNotEmpty) parts.add(item.genres.take(2).join(' · '));
    if (item.status != null && item.status!.isNotEmpty) {
      parts.add(statusLabel(context, item.status));
    }
    return parts.join('  ·  ');
  }

  Widget _continueWatchingRail(
    BuildContext context,
    List<HistoryEntry> entries,
    Map<String, ProviderItem> catalogByKey,
  ) {
    final resolved = <({HistoryEntry entry, ProviderItem item})>[];
    for (final entry in entries) {
      final item = catalogByKey[entry.catalogKey];
      if (item != null) resolved.add((entry: entry, item: item));
    }
    if (resolved.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(
              title: tr(context, 'home.continueWatching'),
              onSeeAll: () => context.go('/library'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: resolved.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final pair = resolved[index];
                final item = pair.item;
                final entry = pair.entry;
                final subtitle = isReadable(item.type)
                    ? trParams(context, 'reader.chapter', {
                        'number': entry.episodeOrChapter.toString(),
                      })
                    : trParams(context, 'player.episode', {
                        'number': entry.episodeOrChapter.toString(),
                      });
                return FocusableCard(
                  onPressed: () => openPlay(
                    context,
                    item,
                    episodeOrChapter: entry.episodeOrChapter,
                  ),
                  child: WideCard(
                    backdrop: backdropOf(item),
                    title: item.title,
                    subtitle: subtitle,
                    rating: item.rating,
                    progress: watchProgress(entry, item),
                    onTap: () => openPlay(
                      context,
                      item,
                      episodeOrChapter: entry.episodeOrChapter,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail(
    BuildContext context, {
    required String title,
    required List<ProviderItem> items,
    String Function(ProviderItem)? subtitle,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(title: title, onSeeAll: onSeeAll),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 232,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length > 10 ? 10 : items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return FocusableCard(
                  onPressed: () => openDetails(context, item),
                  child: PosterCard(
                    poster: posterOf(item),
                    title: item.title,
                    subtitle: subtitle?.call(item) ??
                        (item.year?.toString() ??
                            typeLabel(context, item.type)),
                    rating: item.rating,
                    onTap: () => openDetails(context, item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static int _byRatingDesc(ProviderItem a, ProviderItem b) =>
      (b.rating ?? -1).compareTo(a.rating ?? -1);

  List<ProviderItem> _topRated(List<ProviderItem> items, int count) {
    final sorted = items.toList()..sort(_byRatingDesc);
    return sorted.take(count).toList();
  }

  List<ProviderItem> _byTypeSorted(List<ProviderItem> items, ContentType type) {
    final filtered = items.where((i) => i.type == type).toList()
      ..sort(_byRatingDesc);
    return filtered;
  }
}
