import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'screen_helpers.dart';

/// Settings: theme (System / Dark / Light), language (English / বাংলা),
/// Providers → `/settings/providers`, Backup → `/backup`, notifications
/// toggle (in-app only — no push in this build), About and Developer.
///
/// Theme/locale changes apply immediately: the setting is persisted to
/// the settings box AND the provider is updated (CONTRACT.md §6 pattern);
/// `main.dart` watches both providers.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings _settings() {
    final box = Hive.box<AppSettings>(BoxNames.settings);
    return box.get('current') ?? AppSettings();
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final settings = _settings();
    settings.themeMode = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    try {
      await Hive.box<AppSettings>(BoxNames.settings)
          .put('current', settings);
    } catch (_) {
      // The setters are called unawaited from onTap — a Hive failure used
      // to be an unhandled async error. Keep the old theme and say so.
      if (mounted) {
        showSnack(context, tr(context, 'common.errorGeneric'));
      }
      return;
    }
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
  }

  Future<void> _setLocale(Locale locale) async {
    final settings = _settings();
    settings.localeCode = locale.languageCode;
    try {
      await Hive.box<AppSettings>(BoxNames.settings)
          .put('current', settings);
    } catch (_) {
      if (mounted) {
        showSnack(context, tr(context, 'common.errorGeneric'));
      }
      return;
    }
    ref.read(localeProvider.notifier).setLocale(locale);
  }

  Future<void> _setNotifications(bool value) async {
    final settings = _settings();
    settings.notificationsEnabled = value;
    try {
      await Hive.box<AppSettings>(BoxNames.settings)
          .put('current', settings);
    } catch (_) {
      if (mounted) {
        showSnack(context, tr(context, 'common.errorGeneric'));
      }
      return;
    }
    // No setState: the Switch reads the settings box through a
    // ValueListenableBuilder, so the box write rebuilds it — and the
    // switch can never go stale when the box changes elsewhere (e.g. a
    // backup restore replacing the settings).
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _sectionLabel(context, 'settings.appearance'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusL),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'settings.theme'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _optionPill(
                      context,
                      label: tr(context, 'settings.themeSystem'),
                      icon: Iconsax.monitor_copy,
                      selected: themeMode == ThemeMode.system,
                      onTap: () => _setTheme(ThemeMode.system),
                    ),
                    const SizedBox(width: 8),
                    _optionPill(
                      context,
                      label: tr(context, 'settings.themeDark'),
                      icon: Iconsax.moon_copy,
                      selected: themeMode == ThemeMode.dark,
                      onTap: () => _setTheme(ThemeMode.dark),
                    ),
                    const SizedBox(width: 8),
                    _optionPill(
                      context,
                      label: tr(context, 'settings.themeLight'),
                      icon: Iconsax.sun_1_copy,
                      selected: themeMode == ThemeMode.light,
                      onTap: () => _setTheme(ThemeMode.light),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  tr(context, 'settings.language'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _optionPill(
                      context,
                      label: tr(context, 'settings.languageEnglish'),
                      icon: Iconsax.translate_copy,
                      selected: locale.languageCode == 'en',
                      onTap: () => _setLocale(const Locale('en')),
                    ),
                    const SizedBox(width: 8),
                    _optionPill(
                      context,
                      label: tr(context, 'settings.languageBangla'),
                      icon: Iconsax.translate_copy,
                      selected: locale.languageCode == 'bn',
                      onTap: () => _setLocale(const Locale('bn')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'settings.account'),
          _row(
            context,
            icon: Iconsax.link_copy,
            label: tr(context, 'settings.providers'),
            onTap: () => context.push('/settings/providers'),
          ),
          _row(
            context,
            icon: Iconsax.cloud_copy,
            label: tr(context, 'settings.backup'),
            onTap: () => context.push('/backup'),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'settings.notifications'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusL),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.notification_copy, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        tr(context, 'settings.notifications'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    // v1.0.4: read the toggle straight from the box so
                    // it can never show a stale value (the old local
                    // `_notificationsEnabled` was snapshotted once in
                    // initState and missed later box writes, e.g. a
                    // backup restore replacing the settings).
                    ValueListenableBuilder<Box<AppSettings>>(
                      valueListenable:
                          Hive.box<AppSettings>(BoxNames.settings)
                              .listenable(keys: const ['current']),
                      builder: (context, box, _) {
                        final enabled = box
                                .get('current')
                                ?.notificationsEnabled ??
                            true;
                        return Switch(
                          value: enabled,
                          activeThumbColor: AppColors.brand,
                          onChanged: _setNotifications,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'settings.notificationsDesc'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'settings.notificationsNote'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'profile.about'),
          _row(
            context,
            icon: Iconsax.info_circle_copy,
            label: tr(context, 'settings.aboutApp'),
            trailing: tr(context, 'settings.aboutVersion'),
            onTap: () => _showAbout(context),
          ),
          _row(
            context,
            icon: Iconsax.code_copy,
            label: tr(context, 'settings.developer'),
            trailing: tr(context, 'settings.developerName'),
            onTap: () => context.push('/developer'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        tr(context, key),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.palette.muted,
            ),
      ),
    );
  }

  Widget _optionPill(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ChipToggle(
        label: label,
        icon: icon,
        selected: selected,
        onTap: onTap,
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? trailing,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
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
                Icon(icon, size: 22, color: palette.muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
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

}
