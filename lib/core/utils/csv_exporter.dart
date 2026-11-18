import 'dart:convert';

import '../database/app_database.dart';

/// One ledger row plus the display names needed by a CSV export.
class ExportTransaction {
  const ExportTransaction({
    required this.transaction,
    required this.sourceAccount,
    required this.category,
    this.destinationAccount,
  });

  final FinancialTransaction transaction;
  final String sourceAccount;
  final String? destinationAccount;
  final String? category;
}

/// Renders ledger rows as UTF-8 CSV with a BOM so spreadsheet apps detect the
/// encoding, and neutralises cells that would be executed as formulas.
abstract final class CsvExporter {
  static const List<String> headers = <String>[
    'ID',
    'Tanggal',
    'Jenis',
    'Akun asal',
    'Akun tujuan',
    'Kategori',
    'Nominal (Rupiah)',
    'Catatan',
  ];
  static const String _newline = '\r\n';

  static List<int> encode(List<ExportTransaction> transactions) {
    final StringBuffer output = StringBuffer('\uFEFF');
    output.write(headers.map(_escape).join(','));
    output.write(_newline);
    for (final ExportTransaction row in transactions) {
      final FinancialTransaction transaction = row.transaction;
      output.write(
        <String>[
          transaction.id.toString(),
          transaction.transactionDate.toIso8601String(),
          transaction.type.label,
          row.sourceAccount,
          row.destinationAccount ?? '',
          row.category ?? '',
          transaction.amount.toString(),
          transaction.note ?? '',
        ].map(_escape).join(','),
      );
      output.write(_newline);
    }
    return utf8.encode(output.toString());
  }

  static String _escape(String value) =>
      '"${_neutraliseFormula(value).replaceAll('"', '""')}"';

  static String _neutraliseFormula(String value) {
    final String trimmed = value.trimLeft();
    if (trimmed.isEmpty) return value;
    const String dangerous = '=+-@\t\r';
    return dangerous.contains(trimmed[0]) ? "'$value" : value;
  }
}
