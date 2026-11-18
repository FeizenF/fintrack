import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Formatting helpers for Rupiah amounts and dates.
///
/// Amounts are stored as integer Rupiah in the database, so all helpers here
/// work on [int] and never introduce floating point rounding.
abstract final class Formatters {
  static const String locale = 'id_ID';

  static bool _dateLocaleReady = false;

  /// Loads Indonesian date symbols. Call once during app startup so dates can
  /// be rendered with Indonesian month names.
  static Future<void> ensureInitialized() async {
    if (_dateLocaleReady) return;
    await initializeDateFormatting(locale);
    _dateLocaleReady = true;
  }

  static bool get isDateLocaleReady => _dateLocaleReady;

  static final NumberFormat _currency =
      NumberFormat.currency(locale: locale, symbol: 'Rp ', decimalDigits: 0);

  static final NumberFormat _compactCurrency =
      NumberFormat.compactCurrency(
    locale: locale,
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final NumberFormat _plainNumber = NumberFormat.decimalPattern(locale);

  /// Date formatting depends on locale data being loaded. When it is not
  /// available yet (e.g. a unit test that skips startup) we fall back to the
  /// default locale instead of throwing.
  static DateFormat _date(String pattern) {
    if (_dateLocaleReady) return DateFormat(pattern, locale);
    try {
      return DateFormat(pattern, locale);
    } on Object {
      return DateFormat(pattern);
    }
  }

  /// `Rp 1.250.000`
  static String currency(int amount) => _currency.format(amount);

  /// Rupiah amount, or a fixed-width mask when balances are hidden.
  ///
  /// The mask keeps the layout width stable so hiding balances does not make
  /// the surrounding cards jump.
  static String maskedCurrency(int amount, {required bool hidden}) =>
      hidden ? '••••••' : currency(amount);

  /// `Rp 1,2 jt` — for tight spaces such as charts.
  static String compactCurrency(int amount) => _compactCurrency.format(amount);

  /// Signed amount, e.g. `+Rp 50.000` or `-Rp 50.000`.
  static String signedCurrency(int amount) {
    final String formatted = currency(amount.abs());
    return amount < 0 ? '-$formatted' : '+$formatted';
  }

  /// `1.250.000` — used inside text fields and CSV exports.
  static String number(int value) => _plainNumber.format(value);

  static String dayMonth(DateTime date) => _date('d MMM').format(date);

  static String fullDate(DateTime date) => _date('d MMMM yyyy').format(date);

  static String monthYear(DateTime date) => _date('MMMM yyyy').format(date);

  static String shortDateTime(DateTime date) =>
      _date('d MMM yyyy, HH:mm').format(date);

  /// File-safe timestamp such as `20260130_141233`.
  static String fileStamp(DateTime date) => _date('yyyyMMdd_HHmmss').format(date);

  /// Human friendly "Hari ini" / "Kemarin" / full date label.
  static String relativeDay(DateTime date, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime a = DateTime(date.year, date.month, date.day);
    final DateTime b = DateTime(reference.year, reference.month, reference.day);
    final int diff = b.difference(a).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff == -1) return 'Besok';
    return fullDate(date);
  }

  /// Parses user input like `1.250.000` or `1250000` into an integer amount.
  ///
  /// Returns `null` when the input is empty or contains non-digits.
  static int? parseAmount(String input) {
    final String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final int? value = int.tryParse(digits);
    if (value == null) return null;
    return value;
  }

  /// Formats digits from a text field into grouped form while typing.
  static String formatAmountInput(String input) {
    final int? value = parseAmount(input);
    if (value == null) return '';
    return _plainNumber.format(value);
  }

  /// Percentage label with one decimal at most, e.g. `62,5%`.
  static String percent(double value) {
    final String text = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return '${text.replaceAll('.', ',')}%';
  }
}
