import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/widgets.dart';
import 'auth_header.dart';

/// Sign-up (`/signup`): name / email / password, gradient CTA.
///
/// On success the device-code popup appears — the code is shown ONCE and
/// the user must tap "I saved my code" before continuing to `/login`
/// (sign-up does not start a session; login does).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _formErrorKey;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _translate(String? Function(String?) validator, String? value) {
    final key = validator(value);
    return key == null ? null : tr(context, key);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _formErrorKey = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final result = await ref.read(authServiceProvider).signUp(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      await showCodePopup(
        context,
        code: result.deviceCode,
        onContinue: () {
          if (mounted) context.go('/login');
        },
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _formErrorKey = e.key);
    } catch (_) {
      if (mounted) setState(() => _formErrorKey = 'auth.signupFailed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthHeader(
                  title: tr(context, 'auth.signupTitle'),
                  subtitle: tr(context, 'auth.signupSubtitle'),
                  onBack: () => context.pop(),
                ),
                AppTextField(
                  controller: _nameController,
                  label: tr(context, 'auth.name'),
                  hint: tr(context, 'auth.nameHint'),
                  prefixIcon: Iconsax.user_copy,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      _translate(Validators.displayName, v),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emailController,
                  label: tr(context, 'auth.email'),
                  hint: tr(context, 'auth.emailHint'),
                  prefixIcon: Iconsax.sms_copy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => _translate(Validators.email, v),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _passwordController,
                  label: tr(context, 'auth.password'),
                  hint: tr(context, 'auth.passwordHint'),
                  prefixIcon: Iconsax.lock_copy,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Iconsax.eye_copy : Iconsax.eye_slash_copy,
                      size: 20,
                    ),
                    tooltip: tr(
                      context,
                      _obscurePassword
                          ? 'auth.showPassword'
                          : 'auth.hidePassword',
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                  validator: (v) => _translate(Validators.password, v),
                ),
                if (_formErrorKey != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    tr(context, _formErrorKey!),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.danger,
                        ),
                  ),
                ],
                const SizedBox(height: 24),
                GradientButton(
                  label: _submitting
                      ? tr(context, 'auth.creatingAccount')
                      : tr(context, 'auth.createAccount'),
                  loading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 24),
                AuthFooterLink(
                  text: tr(context, 'auth.haveAccount'),
                  linkText: tr(context, 'auth.login'),
                  onTap: () => context.go('/login'),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Iconsax.shield_tick_copy,
                      size: 18,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(context, 'auth.codeWarning'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
