import '../database/app_database.dart';
import '../database/enums.dart';
import 'date_range.dart';
import 'formatters.dart';

/// Bucket size for the transaction history list.
///
/// [day] groups into "Hari ini" / "Kemarin" / a full date so short sessions stay
/// scannable, while [month] and [year] give the roll-up totals that a flat list
/// never showed.
enum TransactionGrouping {
  day,
  month,
  year;

  String get label => switch (this) {
    TransactionGrouping.day => 'Hari',
    TransactionGrouping.month => 'Bulan',
    TransactionGrouping.year => 'Tahun',
  };
}

/// One bucket of transactions plus its ledger totals.
class TransactionGroup {
  const TransactionGroup({
    required this.start,
    required this.rows,
    required this.income,
    required this.expense,
    required this.transfer,
  });

  /// First instant of the bucket: the day, the month or the year.
  final DateTime start;
  final List<FinancialTransaction> rows;

  /// Sum of income rows in this bucket.
  final int income;

  /// Sum of expense rows in this bucket.
  final int expense;

  /// Sum moved by transfer rows. Kept apart from [income]/[expense] so a
  /// transfer is never counted as new money.
  final int transfer;

  int get net => income - expense;

  int get count => rows.length;

  /// Stable identity used for collapse state and keys.
  String get key => '${start.year}-${start.month}-${start.day}';
}

/// Normalises [value] to the start of its bucket.
DateTime bucketStart(DateTime value, TransactionGrouping grouping) =>
    switch (grouping) {
      TransactionGrouping.day => DateTime(value.year, value.month, value.day),
      TransactionGrouping.month => DateTime(value.year, value.month),
      TransactionGrouping.year => DateTime(value.year),
    };

/// Groups [rows] into newest-first buckets.
///
/// The repository already returns newest-first and the page appends stable
/// ordering, so groups keep the input order of their first row instead of being
/// re-sorted; that keeps same-day entries in the order the user saw them.
List<TransactionGroup> groupTransactions(
  List<FinancialTransaction> rows,
  TransactionGrouping grouping,
) {
  final Map<DateTime, List<FinancialTransaction>> buckets =
      <DateTime, List<FinancialTransaction>>{};
  final List<DateTime> order = <DateTime>[];

  for (final FinancialTransaction row in rows) {
    final DateTime bucket = bucketStart(row.transactionDate, grouping);
    final List<FinancialTransaction>? existing = buckets[bucket];
    if (existing == null) {
      buckets[bucket] = <FinancialTransaction>[row];
      order.add(bucket);
    } else {
      existing.add(row);
    }
  }

  int sum(TransactionType type, List<FinancialTransaction> bucketRows) {
    int total = 0;
    for (final FinancialTransaction row in bucketRows) {
      if (row.type == type) total += row.amount;
    }
    return total;
  }

  return order
      .map((DateTime start) {
        final List<FinancialTransaction> bucketRows = buckets[start]!;
        return TransactionGroup(
          start: start,
          rows: bucketRows,
          income: sum(TransactionType.income, bucketRows),
          expense: sum(TransactionType.expense, bucketRows),
          transfer: sum(TransactionType.transfer, bucketRows),
        );
      })
      .toList(growable: false);
}

/// Header label for [group].
String transactionGroupLabel(
  TransactionGroup group,
  TransactionGrouping grouping, {
  DateTime? now,
}) {
  final DateTime reference = now ?? DateTime.now();
  return switch (grouping) {
    TransactionGrouping.day => _dayLabel(group.start, reference),
    TransactionGrouping.month => Formatters.monthYear(group.start),
    TransactionGrouping.year => Formatters.year(group.start),
  };
}

String _dayLabel(DateTime day, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  if (diff == -1) return 'Besok';
  return Formatters.fullDate(day);
}

/// Range covered by [group], useful when a caller needs to filter further.
DateRange transactionGroupRange(
  TransactionGroup group,
  TransactionGrouping grouping,
) {
  final DateTime end = switch (grouping) {
    TransactionGrouping.day => DateTime(
      group.start.year,
      group.start.month,
      group.start.day + 1,
    ),
    TransactionGrouping.month => DateTime(
      group.start.year,
      group.start.month + 1,
    ),
    TransactionGrouping.year => DateTime(group.start.year + 1),
  };
  return DateRange(start: group.start, end: end);
}
