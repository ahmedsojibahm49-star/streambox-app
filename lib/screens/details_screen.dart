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
          icon: Iconsax.folder_open_copy,
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
    }).toList()..sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));

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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
                          icon: Iconsax.star_1_copy,
                        ),
                      _metaChip(context, statusLabel(context, item.status)),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // At 360px the content column is 320 wide: three
                      // 52px buttons + gaps leave only ~134px for the
                      // CTA — the old "Resume episode 3" label overflowed
                      // it and painted over the bookmark button (a Row
                      // overflow doesn't clip, it overdraws). Shrink the
                      // icon buttons on narrow screens so the CTA keeps
                      // a comfortable width, and keep the CTA height
                      // matched to them.
                      final narrow = constraints.maxWidth < 400;
                      final actionSize = narrow ? 44.0 : 52.0;
                      final gap = narrow ? 8.0 : 10.0;
                      return Row(
                        children: [
                          Expanded(
                            child: GradientButton(
                              label: _primaryLabel(context, item, progress),
                              icon: Iconsax.play_copy,
                              height: actionSize,
                              onPressed: () =>
                                  _onPrimary(context, item, progress),
                            ),
                          ),
                          SizedBox(width: gap),
                          _actionButton(
                            context,
                            size: actionSize,
                            // v1.0.5: one Linear glyph in both states —
                            // the saved state is shown by colour (the
                            // `active` tint), not a filled glyph.
                            icon: Iconsax.bookmark_copy,
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
                          SizedBox(width: gap),
                          _actionButton(
                            context,
                            size: actionSize,
                            // v1.0.5: one Linear glyph in both states —
                            // the favorite state is shown by colour (the
                            // `active` tint), not a filled glyph.
                            icon: Iconsax.heart_copy,
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
                          SizedBox(width: gap),
                          _actionButton(
                            context,
                            size: actionSize,
                            icon: Iconsax.share_copy,
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
                      );
                    },
                  ),
                  // Where "Resume" goes — the episode/chapter number
                  // lives here now, not inside the button.
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    _resumeCaption(context, item, progress),
                  ],
                  if (item.overview != null && item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      tr(context, 'details.overview'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.overview!,
                      style: Theme.of(context).textTheme.bodyMedium
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
            _chapterList(context, item, progress)
          else
            _episodeList(context, item, progress),
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
                  itemCount: moreLikeThis.length > 10
                      ? 10
                      : moreLikeThis.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final other = moreLikeThis[index];
                    return FocusableCard(
                      onPressed: () => openDetails(context, other),
                      child: PosterCard(
                        poster: posterOf(other),
                        title: other.title,
                        subtitle:
                            other.year?.toString() ??
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
    // Just "Resume" — the episode/chapter number lives in the caption
    // underneath (the old "Resume episode 3" label overflowed the button
    // at 360px and painted over the bookmark button).
    if (progress != null) return tr(context, 'details.resume');
    return isReadable(item.type)
        ? tr(context, 'details.readNow')
        : tr(context, 'details.watchNow');
  }

  /// "Episode 3 · 12:34" under the Resume button — where Resume goes.
  Widget _resumeCaption(
    BuildContext context,
    ProviderItem item,
    HistoryEntry progress,
  ) {
    final palette = context.palette;
    final target = isReadable(item.type)
        ? trParams(context, 'reader.chapter', {
            'number': progress.episodeOrChapter.toString(),
          })
        : trParams(context, 'player.episode', {
            'number': progress.episodeOrChapter.toString(),
          });
    final position = progress.positionSeconds > 0
        ? ' · ${Formatters.duration(progress.positionSeconds)}'
        : '';
    return Row(
      children: [
        Icon(Iconsax.clock_copy, size: 14, color: palette.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$target$position',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.muted),
          ),
        ),
      ],
    );
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
      openReader(context, item, chapter: resumeAt ?? _firstChapterNumber(item));
      return;
    }
    if (item.episodes.isEmpty) {
      showSnack(context, tr(context, 'details.noVideo'));
      return;
    }
    openPlayer(context, item, episode: resumeAt ?? _firstEpisodeNumber(item));
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
    double size = 52,
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
          width: size,
          height: size,
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
            size: size * 0.42,
            color: active ? AppColors.brand : palette.text,
          ),
        ),
      ),
    );
  }

  Widget _episodeList(
    BuildContext context,
    ProviderItem item,
    HistoryEntry? progress,
  ) {
    final episodes = item.episodes;
    if (episodes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            tr(context, 'details.noEpisodes'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final episode = episodes[index];
        final number = (episode['number'] as num?)?.toInt() ?? index + 1;
        final title =
            episode['title'] as String? ??
            trParams(context, 'player.episode', {'number': number.toString()});
        final duration = (episode['durationSeconds'] as num?)?.toInt();
        // The episode Resume would open is highlighted, with its saved
        // position ("12:34 / 24:00") instead of just the runtime.
        final isResumeTarget = progress?.episodeOrChapter == number;
        String? subtitle;
        if (duration != null) {
          subtitle = Formatters.duration(duration);
          if (isResumeTarget &&
              progress != null &&
              progress.positionSeconds > 0) {
            subtitle =
                '${Formatters.duration(progress.positionSeconds)} / $subtitle';
          }
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: _listRow(
            context,
            number: number,
            title: title,
            subtitle: subtitle,
            icon: Iconsax.play_circle_copy,
            highlighted: isResumeTarget,
            onTap: () => openPlayer(context, item, episode: number),
          ),
        );
      }, childCount: episodes.length),
    );
  }

  Widget _chapterList(
    BuildContext context,
    ProviderItem item,
    HistoryEntry? progress,
  ) {
    final chapters = item.chapters;
    if (chapters.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            tr(context, 'details.noChapters'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final chapter = chapters[index];
        final number = (chapter['number'] as num?)?.toInt() ?? index + 1;
        final title =
            chapter['title'] as String? ??
            trParams(context, 'reader.chapter', {'number': number.toString()});
        final pages = chapter['pageUrls'];
        final pageCount = pages is List ? pages.length : null;
        final isResumeTarget = progress?.episodeOrChapter == number;
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
            icon: Iconsax.book_copy,
            highlighted: isResumeTarget,
            onTap: () => openReader(context, item, chapter: number),
          ),
        );
      }, childCount: chapters.length),
    );
  }

  Widget _listRow(
    BuildContext context, {
    required int number,
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    final palette = context.palette;
    return Material(
      color: highlighted
          ? AppColors.brand.withValues(alpha: 0.12)
          : palette.card,
      // Material asserts when BOTH shape and borderRadius are set, so the
      // highlighted row carries the radius inside its shape and the plain
      // row uses borderRadius. (Passing both crashed the episode list.)
      borderRadius: highlighted
          ? null
          : BorderRadius.circular(AppColors.radiusM),
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusM),
              side: const BorderSide(color: AppColors.brand),
            )
          : null,
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
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: AppColors.brand),
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
