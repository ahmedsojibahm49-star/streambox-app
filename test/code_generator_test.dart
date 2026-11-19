import 'package:flutter_test/flutter_test.dart';
import 'package:streambox/utils/code_generator.dart';

void main() {
  group('DeviceCode', () {
    test('generate returns SB-XXXX-XXXX-XXXX format', () {
      final code = DeviceCode.generate();
      expect(DeviceCode.isValid(code), isTrue);
      expect(code.startsWith('SB-'), isTrue);
      expect(code.length, 17);
    });

    test('generated codes are unique', () {
      final codes = List.generate(1000, (_) => DeviceCode.generate());
      expect(codes.toSet().length, 1000);
    });

    test('uses only the unambiguous alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = DeviceCode.generate();
        final body = code.replaceAll('SB-', '').replaceAll('-', '');
        for (final ch in body.split('')) {
          expect(
            DeviceCode.alphabet.contains(ch),
            isTrue,
            reason: 'Character $ch in $code is not in the alphabet',
          );
        }
      }
    });

    test('generate with seed is still valid and unique', () {
      final a = DeviceCode.generate(seed: 'device-123');
      final b = DeviceCode.generate(seed: 'device-123');
      expect(DeviceCode.isValid(a), isTrue);
      expect(DeviceCode.isValid(b), isTrue);
      expect(a, isNot(b)); // crypto-random bytes differ each call
    });

    test('isValid rejects bad codes', () {
      expect(DeviceCode.isValid('SB-AAAA-BBBB-CCCC'), isTrue);
      expect(DeviceCode.isValid('SB-AAAA-BBBB-CCC'), isFalse);
      expect(DeviceCode.isValid('SB-AAAA-BBBB-CCCC-DDDD'), isFalse);
      expect(DeviceCode.isValid('SB-0000-0000-0000'), isFalse);
      expect(DeviceCode.isValid('SB-OOOO-IIII-LLLL'), isFalse);
      expect(DeviceCode.isValid('sb-aaaa-bbbb-cccc'), isFalse);
      expect(DeviceCode.isValid(''), isFalse);
    });

    test('normalize cleans user input', () {
      expect(
        DeviceCode.normalize('sb aaaa bbbb cccc'),
        'SB-AAAA-BBBB-CCCC',
      );
      expect(
        DeviceCode.normalize('SB-AAAA-BBBB-CCCC'),
        'SB-AAAA-BBBB-CCCC',
      );
      expect(
        DeviceCode.normalize('  aaaabbbbcccc  '),
        'SB-AAAA-BBBB-CCCC',
      );
    });
  });
}
