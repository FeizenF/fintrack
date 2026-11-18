import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await Formatters.ensureInitialized();
  });

  group('Formatters.currency', () {
    test('formats whole Rupiah values', () {
      expect(Formatters.currency(0), 'Rp 0');
      expect(Formatters.currency(1000), 'Rp 1.000');
      expect(Formatters.currency(1250000), 'Rp 1.250.000');
      expect(Formatters.currency(1000000000000), 'Rp 1.000.000.000.000');
    });
  });

  group('Formatters.signedCurrency', () {
    test('keeps the direction of the amount', () {
      expect(Formatters.signedCurrency(50000), '+Rp 50.000');
      expect(Formatters.signedCurrency(-50000), '-Rp 50.000');
      expect(Formatters.signedCurrency(0), '+Rp 0');
    });
  });

  group('Formatters.parseAmount', () {
    test('accepts grouped and raw digits', () {
      expect(Formatters.parseAmount('1.250.000'), 1250000);
      expect(Formatters.parseAmount('1250000'), 1250000);
      expect(Formatters.parseAmount(' 25 000 '), 25000);
    });

    test('rejects empty and non-numeric input', () {
      expect(Formatters.parseAmount(''), isNull);
      expect(Formatters.parseAmount('   '), isNull);
      expect(Formatters.parseAmount('abc'), isNull);
    });

    test('ignores currency prefix and separators', () {
      expect(Formatters.parseAmount('Rp 1.500'), 1500);
    });
  });

  group('Formatters.formatAmountInput', () {
    test('groups digits while typing', () {
      expect(Formatters.formatAmountInput('1250000'), '1.250.000');
      expect(Formatters.formatAmountInput('1.250.000'), '1.250.000');
    });

    test('returns empty string for empty input', () {
      expect(Formatters.formatAmountInput(''), '');
    });
  });

  group('Formatters.percent', () {
    test('drops trailing decimals for whole numbers', () {
      expect(Formatters.percent(50), '50%');
    });

    test('uses a comma decimal separator with one fraction digit', () {
      expect(Formatters.percent(62.5), '62,5%');
    });
  });

  group('Formatters.relativeDay', () {
    final DateTime now = DateTime(2026, 3, 15, 10);

    test('labels today and yesterday', () {
      expect(
        Formatters.relativeDay(DateTime(2026, 3, 15, 8), now: now),
        'Hari ini',
      );
      expect(
        Formatters.relativeDay(DateTime(2026, 3, 14, 23), now: now),
        'Kemarin',
      );
    });

    test('falls back to a full date', () {
      expect(
        Formatters.relativeDay(DateTime(2026, 3, 1), now: now),
        '1 Maret 2026',
      );
    });
  });
}
