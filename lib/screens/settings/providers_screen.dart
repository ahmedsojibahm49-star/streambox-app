import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../models/models.dart';
import '../../providers/catalog_providers.dart';
import '../../services/provider_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Settings > Providers: list of repos (built-in sample + added ones) with
/// item count, enabled toggle, last-fetched time, refresh + delete.
/// Route: `/settings/providers` (see app_router.dart).
class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  String? _refreshingId;
  bool _refreshingAll = false;

  /// Repo ids with a toggle in flight. Rapid taps used to fire overlapping
  /// toggles whose completion order (not tap order) decided the final
  /// state — ignore taps until the in-flight toggle lands.
  final _togglingIds = <String>{};

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  Future<void> _refreshRepo(ProviderRepo repo) async {
    final successMessage = tr(context, 'providers.providerRefreshed');
    final errorMessage = tr(context, 'common.errorGeneric');
    setState(() => _refreshingId = repo.id);
    try {
      await ref.read(providersListProvider.notifier).refresh(repo.id);
      _showMessage(successMessage);
    } on RepoException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      // Non-repo failures (e.g. a Hive write error) used to be unhandled
      // async errors — show a generic message instead.
      _showMessage(errorMessage, isError: true);
    } finally {
      if (mounted) setState(() => _refreshingId = null);
    }
  }

  Future<void> _refreshAll() async {
    final successMessage = tr(context, 'providers.providerRefreshed');
    final errorMessage = tr(context, 'common.errorGeneric');
    setState(() => _refreshingAll = true);
    try {
      await ref.read(providersListProvider.notifier).refreshAll();
      _showMessage(successMessage);
    } on RepoException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(errorMessage, isError: true);
    } finally {
      if (mounted) setState(() => _refreshingAll = false);
    }
  }

  Future<void> _confirmDelete(ProviderRepo repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'providers.removeProvider')),
        content: Text(
          trParams(dialogContext, 'providers.removeConfirm', {
            'name': repo.name,
            'count': repo.itemCount.toString(),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(dialogContext, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              tr(dialogContext, 'common.delete'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removedMessage = tr(context, 'providers.providerRemoved');
    final errorMessage = tr(context, 'common.errorGeneric');
    try {
      await ref.read(providersListProvider.notifier).delete(repo.id);
      _showMessage(removedMessage);
    } on RepoException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(errorMessage, isError: true);
    }
  }

  Future<void> _toggleRepo(ProviderRepo repo, bool enabled) async {
    if (_togglingIds.contains(repo.id)) return;
    final errorMessage = tr(context, 'common.errorGeneric');
    _togglingIds.add(repo.id);
    try {
      await ref.read(providersListProvider.notifier).toggle(repo.id, enabled);
    } on RepoException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(errorMessage, isError: true);
    } finally {
      _togglingIds.remove(repo.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final repos = ref.watch(providersListProvider);
    final addedRepos = repos.where((repo) => !repo.isBuiltIn).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'providers.title')),
        actions: [
          IconButton(
            icon: _refreshingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Iconsax.refresh_copy),
            tooltip: tr(context, 'providers.refreshAll'),
            // With no repos the button used to be live and reported a
            // misleading "Provider refreshed" for refreshing nothing.
            onPressed: (_refreshingAll || repos.isEmpty) ? null : _refreshAll,
          ),
        ],
      ),
      body: repos.isEmpty
          ? EmptyState(
              title: tr(context, 'providers.noAddedRepos'),
              body: tr(context, 'providers.subtitle'),
              icon: Iconsax.global_copy,
              actionLabel: tr(context, 'providers.addProvider'),
              onAction: () => context.push('/settings/providers/add'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  tr(context, 'providers.subtitle'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.muted),
                ),
                const SizedBox(height: 16),
                ...repos.map((repo) => _RepoCard(
                      repo: repo,
                      isRefreshing: _refreshingId == repo.id,
                      onRefresh: () => _refreshRepo(repo),
                      onDelete: repo.isBuiltIn
                          ? null
                          : () => _confirmDelete(repo),
                      onToggle: (enabled) => _toggleRepo(repo, enabled),
                    )),
                if (addedRepos.isEmpty) ...[
                  const SizedBox(height: 8),
                  _NoAddedReposCard(
                    onAdd: () => context.push('/settings/providers/add'),
                  ),
                ],
                const SizedBox(height: 20),
                GradientButton(
                  label: tr(context, 'providers.addProvider'),
                  icon: Iconsax.add_circle_copy,
                  onPressed: () => context.push('/settings/providers/add'),
                ),
              ],
            ),
    );
  }
}

/// Hint card shown when only the built-in catalog exists.
class _NoAddedReposCard extends StatelessWidget {
  const _NoAddedReposCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppColors.radiusM),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Iconsax.info_circle_copy, size: 24, color: palette.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'providers.noAddedRepos'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'providers.noAddedReposBody'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAdd,
            child: Text(tr(context, 'common.add')),
          ),
        ],
      ),
    );
  }
}

/// One repo row: name + built-in chip, item count, last-fetched time,
/// enabled switch, refresh + delete actions.
class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.repo,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onDelete,
    required this.onToggle,
  });

  final ProviderRepo repo;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback? onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lastFetched = repo.lastFetchedAt == null
        ? tr(context, 'providers.neverFetched')
        : formatDate(context, repo.lastFetchedAt!);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppColors.radiusM),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusS),
                ),
                child: Icon(
                  repo.isBuiltIn ? Iconsax.folder_copy : Iconsax.global_copy,
                  size: 20,
                  color: palette.onBrand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            repo.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (repo.isBuiltIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brand
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tr(context, 'providers.builtIn'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.brand),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trParams(context, 'providers.itemCount', {
                        'count': repo.itemCount.toString(),
                      }),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: repo.enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Iconsax.refresh_copy, size: 14, color: palette.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${tr(context, 'providers.lastFetched')}: $lastFetched',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: palette.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.refresh_copy, size: 16),
                label: Text(tr(context, 'providers.refresh')),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Iconsax.trash_copy, size: 20),
                  color: AppColors.danger,
                  tooltip: tr(context, 'providers.removeProvider'),
                  // Deleting while a refresh is in flight resurrects the
                  // repo: the refresh re-persists the row after the delete
                  // lands. Disable delete until the refresh finishes.
                  onPressed: isRefreshing ? null : onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
