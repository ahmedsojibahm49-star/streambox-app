import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import 'gradient_button.dart';

/// The device-code popup shown right after sign-up.
///
/// NOTE: this is a DIALOG, not a route — there is intentionally no `/code`
/// route in app_router.dart. The auth screen calls [showCodePopup] after a
/// successful sign-up and navigates to /login (or /home) when the user taps
/// Continue.
Future<void> showCodePopup(
  BuildContext context, {
  required String code,
  required VoidCallback onContinue,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppColors.glowShadow,
            ),
            child: const Icon(Iconsax.key_copy, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'auth.codeTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'auth.codeSubtitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.palette.muted,
                ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(AppColors.radiusM),
              border: Border.all(color: context.palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(letterSpacing: 1.5),
                  ),
                ),
                IconButton(
                  icon: const Icon(Iconsax.copy_copy, size: 20),
                  tooltip: tr(context, 'auth.codeCopied'),
                  onPressed: () async {
                    // Clipboard is a platform-channel call — guard it
                    // (a broken plugin layer used to crash the copy
                    // button with an unhandled async error).
                    bool copied = false;
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: code),
                      );
                      copied = true;
                    } catch (_) {
                      copied = false;
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              context,
                              copied
                                  ? 'auth.codeCopied'
                                  : 'common.errorGeneric',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(context, 'auth.codeWarning'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: tr(context, 'auth.iSavedMyCode'),
            onPressed: () {
              Navigator.of(context).pop();
              onContinue();
            },
          ),
        ],
      ),
    ),
  );
}
