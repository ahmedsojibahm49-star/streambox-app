import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Library: 4 tabs — My List, Favorites, History, Continue Watching —
/// all from [LibraryService]. Rows show the poster, title, progress or
/// date, and a remove action. Entries whose catalog item is gone (provider
/// removed/disabled) are skipped — the list never shows dead rows.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'library.title')),
          actions: [
            if (history.isNotEmpty)
              IconButton(
                tooltip: tr(context, 'library.clearHistory'),
                icon: const Icon(Iconsax.trash_copy),
                onPressed: () => _confirmClearHistory(context, ref),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.brand,
            unselectedLabelColor: context.palette.muted,
            indicatorColor: AppColors.brand,
            tabs: [
              Tab(text: tr(context, 'home.myList')),
              Tab(text: tr(context, 'library.favorites')),
              Tab(text: tr(context, 'library.history')),
              Tab(text: tr(context, 'home.continueWatching')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LibraryListTab(list: LibraryList.myList),
            _LibraryListTab(list: LibraryList.favorite),
            _HistoryTab(),
            _ContinueWatchingTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'library.clearHistory')),
        content: Text(tr(context, 'library.clearHistoryConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              tr(context, 'common.delete'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref.read(historyProvider.notifier).clear();
      } catch (_) {
        if (context.mounted) {
          showSnack(context, tr(context, 'common.errorGeneric'));
        }
        return;
      }
      if (context.mounted) {
        showSnack(context, tr(context, 'library.historyCleared'));
      }
    }
  }
}

/// My List / Favorites tab: saved entries, newest first.
class _LibraryListTab extends ConsumerWidget {
  const _LibraryListTab({required this.list});

  final LibraryList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = list == LibraryList.myList
        ? ref.watch(myListProvider)
        : ref.watch(favoritesProvider);
    final allItems = ref.watch(allEnabledItemsProvider);
    final catalogByKey = {for (final item in allItems) item.boxKey: item};
    final resolved = <({LibraryEntry entry, ProviderItem item})>[];
    for (final entry in entries) {
      final item = catalogByKey[entry.catalogKey];
      if (item != null) resolved.add((entry: entry, item: item));
    }
    if (resolved.isEmpty) {
      final isMyList = list == LibraryList.myList;
      return EmptyState(
        title: tr(
          context,
          isMyList ? 'library.myListEmpty' : 'library.favoritesEmpty',
        ),
        body: tr(
          context,
          isMyList
              ? 'library.myListEmptyBody'
              : 'library.favoritesEmptyBody',
        ),
        icon: isMyList ? Iconsax.bookmark_copy : Iconsax.heart_copy,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: resolved.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pair = resolved[index];
        return _LibraryRow(
          item: pair.item,
          subtitle: _savedSubtitle(context, pair.entry),
          onRemove: () async {
            // Branch (don't unify the two notifiers in one variable —
            // the ternary would widen to Notifier and lose .toggle).
            try {
              if (list == LibraryList.myList) {
                await ref
                    .read(myListProvider.notifier)
                    .toggle(pair.item.id, pair.item.providerId);
              } else {
                await ref
                    .read(favoritesProvider.notifier)
                    .toggle(pair.item.id, pair.item.providerId);
              }
            } catch (_) {
              if (context.mounted) {
                showSnack(context, tr(context, 'common.errorGeneric'));
              }
              return;
            }
            if (context.mounted) {
              showSnack(
                context,
                tr(
                  context,
                  list == LibraryList.myList
                      ? 'library.removedFromList'
                      : 'library.removedFromFavorites',
                ),
              );
            }
          },
        );
      },
    );
  }

  String _savedSubtitle(BuildContext context, LibraryEntry entry) {
    final date = formatDate(context, entry.savedAt);
    return date;
  }
}

/// History tab: every watched/read item, newest first.
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final allItems = ref.watch(allEnabledItemsProvider);
    final catalogByKey = {for (final item in allItems) item.boxKey: item};
    final resolved = <({HistoryEntry entry, ProviderItem item})>[];
    for (final entry in history) {
      final item = catalogByKey[entry.catalogKey];
      if (item != null) resolved.add((entry: entry, item: item));
    }
    if (resolved.isEmpty) {
      return EmptyState(
        title: tr(context, 'library.historyEmpty'),
        body: tr(context, 'library.historyEmptyBody'),
        icon: Iconsax.clock_copy,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: resolved.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pair = resolved[index];
        final item = pair.item;
        final entry = pair.entry;
        final where = isReadable(item.type)
            ? trParams(context, 'reader.chapter', {
                'number': entry.episodeOrChapter.toString(),
              })
            : trParams(context, 'player.episode', {
                'number': entry.episodeOrChapter.toString(),
              });
        return _LibraryRow(
          item: item,
          subtitle: '$where · ${formatDate(context, entry.updatedAt)}',
          progress: watchProgress(entry, item),
          onTap: () => openPlay(
            context,
            item,
            episodeOrChapter: entry.episodeOrChapter,
          ),
          onRemove: () async {
            try {
              await ref.read(historyProvider.notifier).remove(
                    itemId: item.id,
                    providerId: item.providerId,
                  );
            } catch (_) {
              if (context.mounted) {
                showSnack(context, tr(context, 'common.errorGeneric'));
              }
            }
          },
        );
      },
    );
  }
}

/// Continue Watching tab: history entries with real progress.
class _ContinueWatchingTab extends ConsumerWidget {
  const _ContinueWatchingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(continueWatchingProvider);
    final allItems = ref.watch(allEnabledItemsProvider);
    final catalogByKey = {for (final item in allItems) item.boxKey: item};
    final resolved = <({HistoryEntry entry, ProviderItem item})>[];
    for (final entry in entries) {
      final item = catalogByKey[entry.catalogKey];
      if (item != null) resolved.add((entry: entry, item: item));
    }
    if (resolved.isEmpty) {
      return EmptyState(
        title: tr(context, 'library.continueEmpty'),
        body: tr(context, 'library.continueEmptyBody'),
        icon: Iconsax.play_circle_copy,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: resolved.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pair = resolved[index];
        final item = pair.item;
        final entry = pair.entry;
        final where = isReadable(item.type)
            ? trParams(context, 'reader.chapter', {
                'number': entry.episodeOrChapter.toString(),
              })
            : trParams(context, 'player.episode', {
                'number': entry.episodeOrChapter.toString(),
              });
        return _LibraryRow(
          item: item,
          subtitle: where,
          progress: watchProgress(entry, item),
          onTap: () => openPlay(
            context,
            item,
            episodeOrChapter: entry.episodeOrChapter,
          ),
          onRemove: () async {
            try {
              await ref.read(historyProvider.notifier).remove(
                    itemId: item.id,
                    providerId: item.providerId,
                  );
            } catch (_) {
              if (context.mounted) {
                showSnack(context, tr(context, 'common.errorGeneric'));
              }
            }
          },
        );
      },
    );
  }
}

/// One library row: poster thumb, title + subtitle, optional progress
/// bar, remove button. Tap → details (or resume, when [onTap] is set).
class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.item,
    required this.subtitle,
    required this.onRemove,
    this.progress,
    this.onTap,
  });

  final ProviderItem item;
  final String subtitle;
  final double? progress;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FocusableCard(
      borderRadius: AppColors.radiusM,
      onPressed: onTap ?? () => openDetails(context, item),
      child: Container(
        color: palette.card,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusS),
              child: AppImage(
                src: posterOf(item),
                width: 56,
                height: 84,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        minHeight: 3,
                        backgroundColor: palette.border,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(
                          AppColors.brand,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: tr(context, 'common.remove'),
              icon: Icon(Iconsax.close_circle_copy, color: palette.muted),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
