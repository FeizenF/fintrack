import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Salted PBKDF2 hash for the optional app PIN.
///
/// Only the derived hash and its salt are persisted (in secure storage); the
/// PIN itself is never written anywhere. The stored format is
/// `pbkdf2-sha256$<iterations>$<saltBase64>$<hashBase64>` so a future change of
/// iteration count can still verify old PINs.
class PinHasher {
  const PinHasher({this.iterations = 120000, this.saltLength = 16});

  final int iterations;
  final int saltLength;

  static const String _algorithm = 'pbkdf2-sha256';
  static const int minPinLength = 4;
  static const int maxPinLength = 8;
  static const int _maxIterations = 1000000;

  /// Checks stored format before presenting PIN entry. A malformed local record
  /// cannot be verified and must use the confirmed data-reset recovery path.
  static bool isWellFormedRecord(String stored) {
    final List<String> parts = stored.split(r'$');
    if (parts.length != 4 || parts.first != _algorithm) return false;
    final int? iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0 || iterations > _maxIterations) {
      return false;
    }
    try {
      final List<int> salt = base64Decode(parts[2]);
      final List<int> hash = base64Decode(parts[3]);
      return salt.isNotEmpty && hash.length == 32;
    } on FormatException {
      return false;
    }
  }

  static bool isValidPin(String pin) =>
      RegExp('^[0-9]{$minPinLength,$maxPinLength}\$').hasMatch(pin);

  Future<String> hash(String pin, {List<int>? salt}) async {
    _validatePin(pin);
    final List<int> usedSalt = salt ?? _randomBytes(saltLength);
    final List<int> derived = await _derive(pin, usedSalt);
    return '$_algorithm\$$iterations\$'
        '${base64Encode(usedSalt)}\$${base64Encode(derived)}';
  }

  /// Returns false for malformed records instead of throwing, so a corrupted
  /// record can be surfaced as "PIN tidak valid" rather than crashing startup.
  Future<bool> verify(String pin, String stored) async {
    if (!isValidPin(pin) || !isWellFormedRecord(stored)) return false;
    final List<String> parts = stored.split(r'$');
    final int storedIterations = int.parse(parts[1]);
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    if (salt.isEmpty || expected.isEmpty) return false;
    final List<int> actual = await _derive(
      pin,
      salt,
      iterations: storedIterations,
    );
    return _constantTimeEquals(actual, expected);
  }

  Future<List<int>> _derive(
    String pin,
    List<int> salt, {
    int? iterations,
  }) async {
    final Pbkdf2 kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations ?? this.iterations,
      bits: 256,
    );
    final SecretKey key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  void _validatePin(String pin) {
    if (!isValidPin(pin)) {
      throw ArgumentError.value(
        pin.length,
        'pin.length',
        'PIN harus $minPinLength–$maxPinLength digit angka.',
      );
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  List<int> _randomBytes(int count) {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(count, (_) => random.nextInt(256)),
    );
  }
}
