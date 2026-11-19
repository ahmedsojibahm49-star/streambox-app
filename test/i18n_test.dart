import 'package:flutter_test/flutter_test.dart';
import 'package:streambox/i18n/bn.dart';
import 'package:streambox/i18n/en.dart';

/// Guards the i18n key-adding rule (CONTRACT.md): bn.dart must mirror
/// en.dart key-for-key, with matching `{placeholder}` names.
void main() {
  test('bn.dart mirrors en.dart keys exactly', () {
    final enKeys = enStrings.keys.toSet();
    final bnKeys = bnStrings.keys.toSet();
    final missingInBn = enKeys.difference(bnKeys);
    final extraInBn = bnKeys.difference(enKeys);
    expect(
      missingInBn,
      isEmpty,
      reason: 'Keys in en.dart missing from bn.dart: $missingInBn',
    );
    expect(
      extraInBn,
      isEmpty,
      reason: 'Keys in bn.dart missing from en.dart: $extraInBn',
    );
  });

  test('no empty translations', () {
    for (final entry in enStrings.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: 'Empty en value for ${entry.key}',
      );
    }
    for (final entry in bnStrings.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: 'Empty bn value for ${entry.key}',
      );
    }
  });

  test('placeholder names match between locales', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final key in enStrings.keys) {
      final enParams = placeholder
          .allMatches(enStrings[key]!)
          .map((m) => m.group(1))
          .toSet();
      final bnParams = placeholder
          .allMatches(bnStrings[key]!)
          .map((m) => m.group(1))
          .toSet();
      expect(
        bnParams,
        enParams,
        reason: 'Placeholder mismatch for $key',
      );
    }
  });
}
