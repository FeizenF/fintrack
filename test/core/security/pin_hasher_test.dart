import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/security/pin_hasher.dart';

void main() {
  group('PinHasher', () {
    const PinHasher hasher = PinHasher(iterations: 1000);

    test('accepts only 4-8 digit pins', () {
      expect(PinHasher.isValidPin('1234'), isTrue);
      expect(PinHasher.isValidPin('12345678'), isTrue);
      expect(PinHasher.isValidPin('123'), isFalse);
      expect(PinHasher.isValidPin('123456789'), isFalse);
      expect(PinHasher.isValidPin('12a4'), isFalse);
      expect(PinHasher.isValidPin(''), isFalse);
    });

    test('verifies the correct pin and rejects another', () async {
      final String stored = await hasher.hash('4821');
      expect(stored, startsWith('pbkdf2-sha256\$1000\$'));
      expect(stored, isNot(contains('4821')));
      expect(await hasher.verify('4821', stored), isTrue);
      expect(await hasher.verify('4822', stored), isFalse);
    });

    test('same pin with different salts yields different records', () async {
      final String first = await hasher.hash('4821');
      final String second = await hasher.hash('4821');
      expect(first, isNot(second));
      expect(await hasher.verify('4821', first), isTrue);
      expect(await hasher.verify('4821', second), isTrue);
    });

    test(
      'records persist across hasher instances with another salt length',
      () async {
        final String stored = await hasher.hash('4821');
        const PinHasher verifier = PinHasher(iterations: 1000, saltLength: 32);
        expect(await verifier.verify('4821', stored), isTrue);
      },
    );

    test('rejects malformed records and invalid input', () async {
      expect(await hasher.verify('4821', 'garbage'), isFalse);
      expect(
        await hasher.verify('4821', 'pbkdf2-sha256\$0\$AAAA\$AAAA'),
        isFalse,
      );
      expect(
        await hasher.verify('4821', 'pbkdf2-sha256\$999999999\$AAAA\$AAAA'),
        isFalse,
      );
      expect(
        await hasher.verify('12', 'pbkdf2-sha256\$1000\$AAAA\$AAAA'),
        isFalse,
      );
      await expectLater(hasher.hash('12'), throwsA(isA<ArgumentError>()));
      await expectLater(hasher.hash('abcd'), throwsA(isA<ArgumentError>()));
    });
  });
}
