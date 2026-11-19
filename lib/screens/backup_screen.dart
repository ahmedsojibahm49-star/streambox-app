import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../utils/code_generator.dart';
import '../widgets/widgets.dart';

/// Backup & restore (`/backup`), reached from Settings.
///
/// Export: enter the device code → encrypted `.sbbackup` file via the
/// save dialog. Import: pick a `.sbbackup` file → enter the code to unlock
/// it → confirm the replacement → data is restored and the user logs in
/// again with the restored account.
///
/// The screen states the honest limit: with no server, the code alone
/// cannot fetch data on a new device — the backup file is the carrier.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _busyLabelKey;

  BackupService get _backup => ref.read(backupServiceProvider);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(BackupException e) =>
      _showMessage(tr(context, e.key));

  void _showAuthError(AuthException e) =>
      _showMessage(tr(context, e.key));

  /// Ask for the device code. Returns the normalised code, or null when
  /// the user cancels.
  Future<String?> _askForCode() async {
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(dialogContext, 'backup.codePrompt')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(dialogContext, 'backup.codePromptBody'),
                style: Theme.of(dialogContext)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                      color: dialogContext.palette.muted,
                    ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: controller,
                label: tr(dialogContext, 'auth.deviceCode'),
                hint: tr(dialogContext, 'auth.codeHint'),
                prefixIcon: Iconsax.key,
                autofocus: true,
                onSubmitted: (_) => Navigator.of(dialogContext).pop(
                  DeviceCode.normalize(controller.text),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr(dialogContext, 'common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                DeviceCode.normalize(controller.text),
              ),
              child: Text(tr(dialogContext, 'backup.unlockBackup')),
            ),
          ],
        ),
      );
      if (!mounted) return null;
      if (code == null || code.isEmpty) return null;
      if (!DeviceCode.isValid(code)) {
        _showMessage(tr(context, 'auth.codeInvalid'));
        return null;
      }
      return code;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    final code = await _askForCode();
    if (code == null || !mounted) return;
    // The code must match this device's stored code before exporting.
    final valid = await ref.read(authServiceProvider).verifyCode(code);
    if (!mounted) return;
    if (!valid) {
      _showMessage(tr(context, 'auth.errorWrongCode'));
      return;
    }
    setState(() {
      _busy = true;
      _busyLabelKey = 'backup.exporting';
    });
    try {
      final path = await _backup.exportBackup(deviceCode: code);
      if (!mounted) return;
      _showMessage(
        trParams(context, 'backup.exportedTo', {'file': path}),
      );
    } on BackupException catch (e) {
      _showError(e);
    } catch (_) {
      if (!mounted) return;
      _showMessage(tr(context, 'backup.failed'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabelKey = null;
        });
      }
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['sbbackup'],
    );
    if (picked == null || !mounted) return;
    final code = await _askForCode();
    if (code == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabelKey = 'backup.restoring';
    });
    try {
      // Decrypt first (validates the code) WITHOUT changing any data.
      // readAsBytes works on every platform (web picks have no path).
      final pickedBytes = await picked.readAsBytes();
      final payload = await _backup.prepareImportFromContent(
        envelopeJson: utf8.decode(pickedBytes),
        deviceCode: code,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyLabelKey = null;
      });
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(dialogContext, 'backup.restoreConfirm')),
          content: Text(tr(dialogContext, 'backup.restoreConfirmBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr(dialogContext, 'common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr(dialogContext, 'common.confirm')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        _busy = true;
        _busyLabelKey = 'backup.restoring';
      });
      await _backup.applyImport(payload);
      if (!mounted) return;
      // The restored account has its own credentials — log in again.
      await ref.read(authServiceProvider).logout();
      if (!mounted) return;
      ref.read(authStateProvider.notifier).setLoggedIn(false);
      _showMessage(tr(context, 'backup.signInAgain'));
      context.go('/login');
    } on BackupException catch (e) {
      _showError(e);
    } on AuthException catch (e) {
      _showAuthError(e);
    } catch (_) {
      if (!mounted) return;
      _showMessage(tr(context, 'backup.failed'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabelKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'backup.title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(context, 'backup.subtitle'),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: palette.muted),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius:
                    BorderRadius.circular(AppColors.radiusM),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Iconsax.info_circle,
                    size: 20,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(context, 'backup.codeAloneNote'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _BackupCard(
              icon: Iconsax.export_1,
              title: tr(context, 'backup.export'),
              body: tr(context, 'backup.exportDesc'),
              busy: _busy,
              busyLabel: _busyLabelKey == null
                  ? null
                  : tr(context, _busyLabelKey!),
              buttonLabel: tr(context, 'backup.export'),
              onPressed: _export,
            ),
            const SizedBox(height: 16),
            _BackupCard(
              icon: Iconsax.import_1,
              title: tr(context, 'backup.import'),
              body: tr(context, 'backup.importDesc'),
              busy: _busy,
              busyLabel: _busyLabelKey == null
                  ? null
                  : tr(context, _busyLabelKey!),
              buttonLabel: tr(context, 'backup.chooseFile'),
              onPressed: _import,
              primary: false,
            ),
            const SizedBox(height: 24),
            Text(
              tr(context, 'backup.warning'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.primary = true,
  });

  final IconData icon;
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool busy;
  final String? busyLabel;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusL),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusS),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.muted),
          ),
          const SizedBox(height: 16),
          if (busy && busyLabel != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  busyLabel!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            )
          else if (primary)
            GradientButton(
              label: buttonLabel,
              onPressed: busy ? null : onPressed,
            )
          else
            GhostButton(
              label: buttonLabel,
              icon: Iconsax.folder_open,
              onPressed: busy ? null : onPressed,
            ),
        ],
      ),
    );
  }
}
