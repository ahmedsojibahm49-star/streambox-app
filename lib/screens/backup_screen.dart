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
import 'screen_helpers.dart';

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
    showSnack(context, message);
  }

  void _showError(BackupException e) =>
      _showMessage(tr(context, e.key));

  void _showAuthError(AuthException e) =>
      _showMessage(tr(context, e.key));

  /// Ask for the device code. Returns the normalised code, or null when
  /// the user cancels.
  ///
  /// v1.0.4: a mistyped code does NOT close the dialog any more — the
  /// error shows inline and the user corrects it in place. The old
  /// dialog popped with the bad code and the caller showed a snackbar,
  /// so a typo forced the whole export/import to be restarted.
  Future<String?> _askForCode() async {
    // The dialog owns its TextEditingController (created in initState,
    // disposed in the dialog widget's dispose). Disposing it here in a
    // `finally` after showDialog returns is WRONG: showDialog's future
    // completes the moment the route pops, but the dialog widget stays
    // in the tree through the pop animation — and the text field
    // rebuilds during that animation, touching the disposed controller
    // ("used after being disposed").
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _CodeDialog(),
    );
    if (!mounted) return null;
    // Defense-in-depth: the dialog already validates, but never trust
    // a code that fails the format check.
    if (code == null || code.isEmpty || !DeviceCode.isValid(code)) {
      return null;
    }
    return code;
  }

  /// Ask for the device code until it matches this device's stored code
  /// (or the user cancels). A wrong code shows an error and re-asks —
  /// v1.0.4: the old export dropped back to the screen on a wrong code
  /// and the user had to tap Export and start over.
  Future<String?> _askForMatchingCode() async {
    while (true) {
      final code = await _askForCode();
      if (code == null || !mounted) return null;
      final valid = await ref.read(authServiceProvider).verifyCode(code);
      if (!mounted) return null;
      if (valid) return code;
      _showMessage(tr(context, 'auth.errorWrongCode'));
    }
  }

  /// Decrypt the picked backup, re-asking for the code on a wrong code.
  /// Returns null when the user cancels the code prompt. Other failures
  /// (not a backup file, corrupt data) rethrow to the caller's handler.
  ///
  /// v1.0.4: the file is already picked at this point, so a wrong code
  /// must not force the user to pick the file again.
  Future<Map<String, dynamic>?> _prepareImport(
    String envelopeJson,
  ) async {
    while (true) {
      final code = await _askForCode();
      if (code == null || !mounted) return null;
      try {
        return await _backup.prepareImportFromContent(
          envelopeJson: envelopeJson,
          deviceCode: code,
        );
      } on BackupException catch (e) {
        if (e.key == 'backup.wrongCode') {
          _showError(e);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    // The code must match this device's stored code before exporting.
    final code = await _askForMatchingCode();
    if (code == null || !mounted) return;
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
    setState(() {
      _busy = true;
      _busyLabelKey = 'backup.restoring';
    });
    try {
      // FilePicker is a platform-channel call — it can throw on a device
      // with a broken plugin layer. The old code called it OUTSIDE the
      // try block, so a throw here was an unhandled async error.
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['sbbackup'],
      );
      if (picked == null || !mounted) return;

      // readAsBytes works on every platform (web picks have no path).
      final pickedBytes = await picked.readAsBytes();
      // v1.0.4: a non-UTF-8 file is not a StreamBox backup at all — say
      // so specifically instead of the generic "backup failed" (the old
      // code let the FormatException fall into the generic catch).
      final String envelopeJson;
      try {
        envelopeJson = utf8.decode(pickedBytes);
      } on FormatException {
        if (mounted) _showMessage(tr(context, 'backup.invalidFile'));
        return;
      }

      // Decrypt first (validates the code) WITHOUT changing any data.
      final payload = await _prepareImport(envelopeJson);
      if (payload == null || !mounted) return;
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
                    Iconsax.info_circle_copy,
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
              icon: Iconsax.export_1_copy,
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
              icon: Iconsax.import_1_copy,
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
              icon: Iconsax.folder_open_copy,
              onPressed: busy ? null : onPressed,
            ),
        ],
      ),
    );
  }
}

/// The device-code prompt, as its own widget so it owns the
/// [TextEditingController] lifecycle: created in initState, disposed in
/// dispose — which runs only when the dialog actually leaves the tree
/// (after the pop animation), never while the text field can still
/// rebuild.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = DeviceCode.normalize(_controller.text);
    if (!DeviceCode.isValid(normalized)) {
      setState(() => _error = tr(context, 'auth.codeInvalid'));
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'backup.codePrompt')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'backup.codePromptBody'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _controller,
            label: tr(context, 'auth.deviceCode'),
            hint: tr(context, 'auth.codeHint'),
            prefixIcon: Iconsax.key_copy,
            autofocus: true,
            onChanged: (_) {
              // Clear the error as soon as the user edits.
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'common.cancel')),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(tr(context, 'backup.unlockBackup')),
        ),
      ],
    );
  }
}
