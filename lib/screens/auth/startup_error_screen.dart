import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

/// Shown INSTEAD of the app when local storage cannot be started
/// (see `bootstrap()` in main.dart). A visible, branded error screen with
/// a Retry button — never a white screen.
///
/// The FULL error is shown (scrollable) with a Copy button, so the user
/// can send us the complete diagnosis instead of a truncated snippet.
///
/// Strings are hardcoded English on purpose: this is a last-resort screen
/// and must not depend on the i18n maps.
class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  /// The storage error that blocked startup (shown in full).
  final Object error;

  /// Re-runs the bootstrap (see `StartupNotifier.retry`).
  final VoidCallback onRetry;

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyError() async {
    // Clipboard is a platform-channel call — guard it (this screen
    // exists precisely for devices whose platform layer is broken).
    try {
      await Clipboard.setData(
        ClipboardData(text: widget.error.toString()),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(
                            AppColors.radiusXl,
                          ),
                          boxShadow: AppColors.glowShadow,
                        ),
                        child: const Icon(
                          Iconsax.play_copy,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'StreamBox',
                      textAlign: TextAlign.center,
                      style: textTheme.displayMedium?.copyWith(
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Couldn't start StreamBox",
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Local storage could not be opened on this device. '
                      'Your library and settings live in local storage, so '
                      'the app cannot continue without it.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.darkMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints:
                          const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(
                          AppColors.radiusM,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.error.toString(),
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.darkMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copyError,
                        icon: Icon(
                          _copied
                              ? Iconsax.copy_success_copy
                              : Iconsax.copy_copy,
                          size: 18,
                          color: AppColors.brand,
                        ),
                        label: Text(
                          _copied ? 'Copied!' : 'Copy error',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GradientButton(
                      label: 'Try again',
                      onPressed: widget.onRetry,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'If this keeps happening, clear the app data in '
                      'Android Settings → Apps → StreamBox → Storage → '
                      'Clear data, then open the app again.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.darkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dependency-free fallback for `ErrorWidget.builder` (main.dart): when a
/// widget build fails anywhere, Flutter shows this instead of a blank
/// screen. Uses no Theme, no icons, no i18n — only explicit styles — so
/// it renders even if the failure was in the theme or fonts themselves.
class StartupErrorFallback extends StatelessWidget {
  const StartupErrorFallback({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF09090D),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF7700), Color(0xFFF03A02)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Text(
                '!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF5F5F7),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'StreamBox hit an unexpected error. Please close the app '
              'completely and open it again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9C9CA6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
