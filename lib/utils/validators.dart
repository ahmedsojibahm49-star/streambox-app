/// Input validators shared by auth screens (sign-up, login, code entry) and
/// the provider-URL form. Every function returns `null` when the value is
/// valid, otherwise an i18n KEY (not a translated string) — callers translate
/// with `tr(context, key)`.
class Validators {
  Validators._();

  static final RegExp _emailPattern =
      RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  /// Email must look like name@domain.tld.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'validation.required';
    if (!_emailPattern.hasMatch(v)) return 'validation.emailInvalid';
    return null;
  }

  /// Password: at least 8 characters. (Local-only auth — no server policy;
  /// the auth agent may tighten this, but must keep the i18n key stable.)
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'validation.required';
    if (v.length < 8) return 'validation.passwordShort';
    return null;
  }

  /// Display name: 2–40 characters, letters/spaces only is NOT enforced
  /// (Bangla names are fine).
  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'validation.required';
    if (v.length < 2) return 'validation.nameShort';
    if (v.length > 40) return 'validation.nameLong';
    return null;
  }

  /// Provider repo URL: must be http(s) and end in .json.
  /// Providers are JSON catalogs ONLY — see CONTRACT.md hard boundaries.
  static String? providerUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'validation.required';
    final uri = Uri.tryParse(v);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'validation.urlInvalid';
    }
    if (!uri.path.toLowerCase().endsWith('.json')) {
      return 'validation.urlNotJson';
    }
    return null;
  }

  /// Non-empty check for generic required fields.
  static String? required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'validation.required';
    return null;
  }
}
