import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/widgets.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Title details (`/details/:id`, `:id` = catalog box key).
///
/// Hero backdrop, title/meta/genres/overview, action row (Play/Read,
/// My List toggle, Favorite toggle, Share), episode list (anime/movie)
/// or chapter list (manga/manhwa), and a "More like this" rail (same
/// type + shared genre). Save/favorite go through [LibraryService] with
/// SnackBar feedback.
class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.itemId});

  /// Catalog box key (`"$providerId::$itemId"`).
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemByIdProvider(itemId));
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: tr(context, 'details.notFoundTitle'),
          body: tr(context, 'details.notFoundBody'),
          icon: Iconsax.folder_open,
        ),
      );
    }

    final palette = context.palette;
    final readable = isReadable(item.type);
    final history = ref.watch(historyProvider);
    HistoryEntry? progress;
    for (final entry in history) {
      if (entry.catalogKey == item.boxKey) progress = entry;
    }
    final inMyList = ref.watch(
      isInMyListProvider((itemId: item.id, providerId: item.providerId)),
    );
    final isFavorite = ref.watch(
      isFavoriteProvider((itemId: item.id, providerId: item.providerId)),
    );
    final moreLikeThis = ref.watch(allEnabledItemsProvider).where((other) {
      if (other.boxKey == item.boxKey || other.type != item.type) {
        return false;
      }
      return other.genres.any(item.genres.contains);
    }).toList()
      ..sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(src: backdropOf(item)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          palette.bg.withValues(alpha: 0.7),
                          palette.bg,
                        ],
                        stops: const [0.0, 0.45, 0.8, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeLabel(context, item.type).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (item.year != null)
                        _metaChip(context, item.year.toString()),
                      if (item.rating != null)
                        _metaChip(
                          context,
                          Formatters.rating(item.rating),
                          icon: Iconsax.star_1,
                        ),
                      _metaChip(
                        context,
                        statusLabel(context, item.status),
                      ),
                      if (readable && item.chapters.isNotEmpty)
                        _metaChip(
                          context,
                          trParams(context, 'manga.chaptersCount', {
                            'count': item.chapters.length.toString(),
                          }),
                        ),
                      if (!readable && item.episodes.isNotEmpty)
                        _metaChip(
                          context,
                          '${item.episodes.length} '
                          '${tr(context, 'common.episodes').toLowerCase()}',
                        ),
                    ],
                  ),
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final genre in item.genres)
                          ChipToggle(
                            label: genre,
                            selected: false,
                            // Genre chips open Search filtered to that
                            // genre (audit fix, Nov 19 — they used to be
                            // dead buttons with an empty onTap).
                            onTap: () => context.go(
                              '/search?genre=${Uri.encodeComponent(genre)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: GradientButton(
                          label: _primaryLabel(context, item, progress),
                          icon: Iconsax.play_copy,
                          onPressed: () =>
                              _onPrimary(context, item, progress),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _actionButton(
                        context,
                        icon: inMyList
                            ? Iconsax.bookmark_copy
                            : Iconsax.bookmark,
                        tooltip: inMyList
                            ? tr(context, 'details.inList')
                            : tr(context, 'details.addToList'),
                        active: inMyList,
                        onPressed: () async {
                          try {
                            final added = await ref
                                .read(myListProvider.notifier)
                                .toggle(item.id, item.providerId);
                            if (context.mounted) {
                              showSnack(
                                context,
                                tr(
                                  context,
                                  added
                                      ? 'library.addedToList'
                                      : 'library.removedFromList',
                                ),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showSnack(
                                context,
                                tr(context, 'common.errorGeneric'),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      _actionButton(
                        context,
                        icon: isFavorite
                            ? Iconsax.heart_copy
                            : Iconsax.heart,
                        tooltip: tr(context, 'details.favorite'),
                        active: isFavorite,
                        onPressed: () async {
                          try {
                            final added = await ref
                                .read(favoritesProvider.notifier)
                                .toggle(item.id, item.providerId);
                            if (context.mounted) {
                              showSnack(
                                context,
                                tr(
                                  context,
                                  added
                                      ? 'library.addedToFavorites'
                                      : 'library.removedFromFavorites',
                                ),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showSnack(
                                context,
                                tr(context, 'common.errorGeneric'),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      _actionButton(
                        context,
                        icon: Iconsax.share,
                        tooltip: tr(context, 'common.share'),
                        // share_plus is a platform-channel call — the old
                        // code fired it unawaited and unguarded, so a
                        // broken plugin layer was an unhandled async
                        // error and the user got no feedback at all.
                        onPressed: () async {
                          try {
                            await SharePlus.instance.share(
                              ShareParams(
                                text: trParams(
                                  context,
                                  'details.shareText',
                                  {'title': item.title},
                                ),
                              ),
                            );
                          } catch (_) {
                            if (context.mounted) {
                              showSnack(
                                context,
                                tr(context, 'common.errorGeneric'),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  if (item.overview != null &&
                      item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      tr(context, 'details.overview'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.overview!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Episodes / chapters.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                readable
                    ? tr(context, 'details.chaptersList')
                    : tr(context, 'details.episodesList'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (readable)
            _chapterList(context, item)
          else
            _episodeList(context, item),
          // More like this.
          if (moreLikeThis.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  tr(context, 'details.moreLikeThis'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount:
                      moreLikeThis.length > 10 ? 10 : moreLikeThis.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final other = moreLikeThis[index];
                    return FocusableCard(
                      onPressed: () => openDetails(context, other),
                      child: PosterCard(
                        poster: posterOf(other),
                        title: other.title,
                        subtitle: other.year?.toString() ??
                            typeLabel(context, other.type),
                        rating: other.rating,
                        onTap: () => openDetails(context, other),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  String _primaryLabel(
    BuildContext context,
    ProviderItem item,
    HistoryEntry? progress,
  ) {
    if (progress != null) {
      if (isReadable(item.type)) {
        return trParams(context, 'details.resumeChapter', {
          'number': progress.episodeOrChapter.toString(),
        });
      }
      return trParams(context, 'details.resumeEpisode', {
        'number': progress.episodeOrChapter.toString(),
      });
    }
    return isReadable(item.type)
        ? tr(context, 'details.readNow')
        : tr(context, 'details.watchNow');
  }

  void _onPrimary(
    BuildContext context,
    ProviderItem item,
    HistoryEntry? progress,
  ) {
    final resumeAt = progress?.episodeOrChapter;
    if (isReadable(item.type)) {
      if (item.chapters.isEmpty) {
        showSnack(context, tr(context, 'details.noPages'));
        return;
      }
      openReader(
        context,
        item,
        chapter: resumeAt ?? _firstChapterNumber(item),
      );
      return;
    }
    if (item.episodes.isEmpty) {
      showSnack(context, tr(context, 'details.noVideo'));
      return;
    }
    openPlayer(
      context,
      item,
      episode: resumeAt ?? _firstEpisodeNumber(item),
    );
  }

  int? _firstEpisodeNumber(ProviderItem item) {
    if (item.episodes.isEmpty) return null;
    return (item.episodes.first['number'] as num?)?.toInt();
  }

  int? _firstChapterNumber(ProviderItem item) {
    if (item.chapters.isEmpty) return null;
    return (item.chapters.first['number'] as num?)?.toInt();
  }

  Widget _metaChip(BuildContext context, String label, {IconData? icon}) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: const Color(0xFFFFC531)),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    final palette = context.palette;
    // FocusableCard (not a bare GestureDetector) so the buttons are
    // reachable by D-pad on Android TV like every other card in the app.
    return Tooltip(
      message: tooltip,
      child: FocusableCard(
        onPressed: onPressed,
        borderRadius: AppColors.radiusM,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: active
                ? AppColors.brand.withValues(alpha: 0.15)
                : palette.card,
            borderRadius: BorderRadius.circular(AppColors.radiusM),
            border: Border.all(
              color: active ? AppColors.brand : palette.border,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? AppColors.brand : palette.text,
          ),
        ),
      ),
    );
  }

  Widget _episodeList(BuildContext context, ProviderItem item) {
    final episodes = item.episodes;
    if (episodes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            tr(context, 'details.noEpisodes'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final episode = episodes[index];
          final number = (episode['number'] as num?)?.toInt() ?? index + 1;
          final title = episode['title'] as String? ??
              trParams(
                context,
                'player.episode',
                {'number': number.toString()},
              );
          final duration = (episode['durationSeconds'] as num?)?.toInt();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _listRow(
              context,
              number: number,
              title: title,
              subtitle: duration != null
                  ? Formatters.duration(duration)
                  : null,
              icon: Iconsax.play_circle,
              onTap: () => openPlayer(context, item, episode: number),
            ),
          );
        },
        childCount: episodes.length,
      ),
    );
  }

  Widget _chapterList(BuildContext context, ProviderItem item) {
    final chapters = item.chapters;
    if (chapters.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            tr(context, 'details.noChapters'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final chapter = chapters[index];
          final number = (chapter['number'] as num?)?.toInt() ?? index + 1;
          final title = chapter['title'] as String? ??
              trParams(
                context,
                'reader.chapter',
                {'number': number.toString()},
              );
          final pages = chapter['pageUrls'];
          final pageCount = pages is List ? pages.length : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _listRow(
              context,
              number: number,
              title: title,
              subtitle: pageCount != null
                  ? trParams(context, 'details.pagesCount', {
                      'count': pageCount.toString(),
                    })
                  : null,
              icon: Iconsax.book,
              onTap: () => openReader(context, item, chapter: number),
            ),
          );
        },
        childCount: chapters.length,
      ),
    );
  }

  Widget _listRow(
    BuildContext context, {
    required int number,
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(AppColors.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radiusM),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppColors.radiusS),
                ),
                alignment: Alignment.center,
                child: Text(
                  number.toString(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.brand,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(icon, size: 22, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
