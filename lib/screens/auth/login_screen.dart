import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../i18n/i18n.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/code_generator.dart';
import '../../utils/validators.dart';
import '../../widgets/widgets.dart';
import 'auth_header.dart';
import 'login_success_screen.dart';

/// Log in (`/login`): email + password + device code, show/hide password,
/// and a forgot-code hint (the code was shown once at sign-up).
///
/// Login errors are specific: wrong email / wrong password / wrong code
/// each show their own message. On success a brief animated success state
/// plays, and only then is the session flipped on and the user sent to
/// `/home` (flipping earlier would let the router redirect skip the
/// success state).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _formErrorKey;
  String? _loggedInName;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String? _translate(String? Function(String?) validator, String? value) {
    final key = validator(value);
    return key == null ? null : tr(context, key);
  }

  String? _codeValidator(String? value) {
    final required = Validators.required(value);
    if (required != null) return tr(context, required);
    if (!DeviceCode.isValid(DeviceCode.normalize(value ?? ''))) {
      return tr(context, 'auth.codeInvalid');
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _formErrorKey = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final profile = await ref.read(authServiceProvider).login(
            email: _emailController.text,
            password: _passwordController.text,
            deviceCode: _codeController.text,
          );
      if (mounted) setState(() => _loggedInName = profile.name);
    } on AuthException catch (e) {
      if (mounted) setState(() => _formErrorKey = e.key);
    } catch (_) {
      if (mounted) setState(() => _formErrorKey = 'auth.loginFailed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onSuccessComplete() {
    ref.read(authStateProvider.notifier).setLoggedIn(true);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final loggedInName = _loggedInName;
    if (loggedInName != null) {
      return LoginSuccessScreen(
        name: loggedInName,
        onComplete: _onSuccessComplete,
      );
    }

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
                  title: tr(context, 'auth.loginTitle'),
                  subtitle: tr(context, 'auth.loginSubtitle'),
                  onBack: () => context.pop(),
                ),
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
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: 16),
                AppTextField(
                  controller: _codeController,
                  label: tr(context, 'auth.deviceCode'),
                  hint: tr(context, 'auth.codeHint'),
                  prefixIcon: Iconsax.key_copy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: _codeValidator,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Iconsax.info_circle_copy,
                      size: 18,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(context, 'auth.forgotCodeHint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
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
                      ? tr(context, 'auth.loggingIn')
                      : tr(context, 'auth.login'),
                  loading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 24),
                AuthFooterLink(
                  text: tr(context, 'auth.noAccount'),
                  linkText: tr(context, 'auth.signup'),
                  onTap: () => context.go('/signup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
