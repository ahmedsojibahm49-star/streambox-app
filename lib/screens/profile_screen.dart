import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/library_service.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../providers/catalog_providers.dart';
import 'screen_helpers.dart';

/// Profile: avatar (initials), name, email, stats (saved / favorites /
/// watched / chapters read), a device-code hint card (the full code is
/// NEVER shown casually — it lives behind Settings → Backup), and rows:
/// Settings, Backup, My Providers, About, Developer, Sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final profile =
        Hive.box<UserProfile>(BoxNames.profile).get('current');
    final myList = ref.watch(myListProvider);
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(historyProvider);
    final allItems = ref.watch(allEnabledItemsProvider);
    final catalogByKey = {for (final item in allItems) item.boxKey: item};

    var chaptersRead = 0;
    for (final entry in history) {
      final item = catalogByKey[entry.catalogKey];
      if (item != null && isReadable(item.type)) chaptersRead++;
    }
    final watched = history.length - chaptersRead;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'profile.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Identity card.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusL),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initialsOf(profile?.name ?? ''),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? tr(context, 'profile.noProfile'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile?.email ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: palette.muted),
                      ),
                      if (profile != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${tr(context, 'profile.memberSince')} '
                          '${formatDate(context, profile.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stats.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusL),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                _stat(
                  context,
                  value: myList.length,
                  label: tr(context, 'profile.saved'),
                ),
                _stat(
                  context,
                  value: favorites.length,
                  label: tr(context, 'library.favorites'),
                ),
                _stat(
                  context,
                  value: watched,
                  label: tr(context, 'profile.watched'),
                ),
                _stat(
                  context,
                  value: chaptersRead,
                  label: tr(context, 'profile.read'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Device-code hint (masked — never the full code here).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusL),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusM),
                  ),
                  child: const Icon(
                    Iconsax.key_copy,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'auth.deviceCode'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SB-••••-••••-••••',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: palette.muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'profile.codeHint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/backup'),
                  child: Text(tr(context, 'profile.viewCode')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _row(
            context,
            icon: Iconsax.setting_2_copy,
            label: tr(context, 'settings.title'),
            onTap: () => context.push('/settings'),
          ),
          _row(
            context,
            icon: Iconsax.cloud_copy,
            label: tr(context, 'settings.backup'),
            onTap: () => context.push('/backup'),
          ),
          _row(
            context,
            icon: Iconsax.link_copy,
            label: tr(context, 'profile.providers'),
            onTap: () => context.push('/settings/providers'),
          ),
          _row(
            context,
            icon: Iconsax.info_circle_copy,
            label: tr(context, 'profile.about'),
            onTap: () => _showAbout(context),
          ),
          _row(
            context,
            icon: Iconsax.code_copy,
            label: tr(context, 'profile.developer'),
            trailing: tr(context, 'profile.developerName'),
            onTap: () => context.push('/developer'),
          ),
          const SizedBox(height: 8),
          _row(
            context,
            icon: Iconsax.logout_copy,
            label: tr(context, 'settings.signOut'),
            danger: true,
            onTap: () => _confirmSignOut(context, ref),
          ),
          // Delete account (audit fix, Nov 19): the service method and
          // the i18n strings already existed, but no screen ever called
          // them — the feature was unreachable.
          _row(
            context,
            icon: Iconsax.trash_copy,
            label: tr(context, 'auth.deleteAccount'),
            danger: true,
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context,
      {required int value, required String label}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? trailing,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    final color = danger ? AppColors.danger : palette.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppColors.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.radiusM),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: danger ? color : palette.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: color),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: palette.muted),
                  ),
                // v1.0.5: no trailing chevron — the user asked for no
                // decorative entry icons on rows. The card + label +
                // InkWell ripple already say "tappable".
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'settings.aboutApp')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'settings.aboutVersion')),
            const SizedBox(height: 8),
            Text(tr(context, 'settings.aboutBody')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'common.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'settings.signOut')),
        content: Text(tr(context, 'settings.signOutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              tr(context, 'settings.signOut'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(authServiceProvider).logout();
      ref.read(authStateProvider.notifier).setLoggedIn(false);
      // The router redirect sends the signed-out user to /welcome.
    } catch (_) {
      if (context.mounted) {
        showSnack(context, tr(context, 'profile.signOutFailed'));
      }
    }
  }

  /// Delete the account after an explicit confirmation. Wipes the
  /// profile, credentials, library and history from this device (see
  /// [LocalAuthService.deleteAccount]); the providers/catalog stay —
  /// they are not account data. The router redirect sends the user to
  /// /welcome once the session is flipped off.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'auth.deleteAccount')),
        content: Text(tr(context, 'auth.deleteAccountConfirm')),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(authServiceProvider).deleteAccount();
      if (!context.mounted) return;
      showSnack(context, tr(context, 'auth.accountDeleted'));
      ref.read(authStateProvider.notifier).setLoggedIn(false);
    } catch (_) {
      if (context.mounted) {
        showSnack(context, tr(context, 'common.errorGeneric'));
      }
    }
  }
}
