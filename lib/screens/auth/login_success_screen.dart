import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_theme.dart';

/// Brief animated success state shown after login: a gradient check that
/// scales in, then auto-continues to Home. Tapping anywhere skips ahead.
///
/// This is a transient state, not a route — the login screen swaps its
/// body to this widget and [onComplete] flips the session on and navigates
/// to `/home`.
class LoginSuccessScreen extends StatefulWidget {
  const LoginSuccessScreen({
    super.key,
    required this.name,
    required this.onComplete,
  });

  final String name;
  final VoidCallback onComplete;

  @override
  State<LoginSuccessScreen> createState() => _LoginSuccessScreenState();
}

class _LoginSuccessScreenState extends State<LoginSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1800), _complete);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _complete,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: AppColors.glowShadow,
                      ),
                      child: const Icon(
                        Iconsax.tick_circle_copy,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _fade,
                    child: Column(
                      children: [
                        Text(
                          tr(context, 'auth.loginSuccess'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          trParams(
                            context,
                            'auth.loginSuccessBody',
                            {'name': widget.name},
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: palette.muted),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          tr(context, 'auth.tapToContinue'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
