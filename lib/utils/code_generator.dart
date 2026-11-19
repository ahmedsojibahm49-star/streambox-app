import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Device-code generation for StreamBox code login.
///
/// A device code looks like `SB-XXXX-XXXX-XXXX` — 12 characters drawn from an
/// unambiguous alphabet (no 0/O, 1/I/L) so users can type it from the popup
/// without mistakes.
///
/// This file is pure Dart: no platform, storage or network dependency, so the
/// auth workstream can call it from anywhere (sign-up popup, login screen,
/// backup export) and the unit tests can run without a device.
///
/// The code is derived from a SHA-256 hash of (device-seed + crypto-random
/// bytes). The device seed is supplied by the caller (auth agent: pass the
/// device id from device_info_plus); when no seed is given the code is still
/// fully random. Two devices never share a code unless both the seed and the
/// random bytes collide.
class DeviceCode {
  DeviceCode._();

  /// Characters allowed in a code. 32 unambiguous characters.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static const String prefix = 'SB';

  /// `SB-XXXX-XXXX-XXXX` where every X is from [alphabet].
  static final RegExp pattern =
      RegExp(r'^SB-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$');

  /// Generate a new device code.
  ///
  /// [seed] is optional extra entropy, typically the device id. It is mixed
  /// with 32 bytes from [Random.secure] and hashed with SHA-256; the first
  /// 12 hash bytes pick characters from [alphabet].
  static String generate({String? seed}) {
    final random = Random.secure();
    final entropy = List<int>.generate(32, (_) => random.nextInt(256));
    final material = <int>[
      ...utf8.encode(seed ?? ''),
      ...entropy,
      ...utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()),
    ];
    final digest = sha256.convert(material).bytes;
    final chars = List<String>.generate(
      12,
      (i) => alphabet[digest[i] % alphabet.length],
    );
    final body = chars.join();
    return '$prefix-${body.substring(0, 4)}-${body.substring(4, 8)}-${body.substring(8, 12)}';
  }

  /// True when [code] matches the `SB-XXXX-XXXX-XXXX` format exactly
  /// (uppercase, dashes in place, alphabet only).
  static bool isValid(String code) => pattern.hasMatch(code.trim());

  /// Normalise user-typed input: strip spaces/dashes, uppercase, re-insert
  /// dashes. Returns the normalised code, or the trimmed input unchanged
  /// when it cannot be normalised into the 12-character body.
  static String normalize(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .replaceFirst(RegExp(r'^SB'), '');
    if (cleaned.length != 12) return input.trim();
    return '$prefix-${cleaned.substring(0, 4)}-${cleaned.substring(4, 8)}-${cleaned.substring(8, 12)}';
  }
}
