import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/transaction_groups.dart';

FinancialTransaction _row({
  required int id,
  required DateTime date,
  required int amount,
  TransactionType type = TransactionType.expense,
}) {
  return FinancialTransaction(
    id: id,
    type: type,
    accountId: 1,
    categoryId: type == TransactionType.transfer ? null : 1,
    toAccountId: type == TransactionType.transfer ? 2 : null,
    amount: amount,
    transactionDate: date,
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  group('groupTransactions', () {
    test('splits rows into day buckets keeping input order', () {
      final DateTime today = DateTime(2026, 5, 20, 9);
      final List<FinancialTransaction> rows = <FinancialTransaction>[
        _row(id: 1, date: DateTime(2026, 5, 20, 8), amount: 50000),
        _row(id: 2, date: DateTime(2026, 5, 19, 20), amount: 25000),
        _row(id: 3, date: DateTime(2026, 5, 20, 7), amount: 15000),
      ];

      final List<TransactionGroup> groups = groupTransactions(
        rows,
        TransactionGrouping.day,
      );

      expect(groups, hasLength(2));
      expect(groups.first.start, DateTime(2026, 5, 20));
      expect(groups.first.count, 2);
      expect(groups.first.rows.map((r) => r.id), <int>[1, 3]);
      expect(groups.last.start, DateTime(2026, 5, 19));
      expect(groups.last.count, 1);
      expect(today.year, 2026);
    });

    test('sums income, expense and transfer separately per group', () {
      final List<FinancialTransaction> rows = <FinancialTransaction>[
        _row(
          id: 1,
          date: DateTime(2026, 5, 2),
          amount: 100000,
          type: TransactionType.income,
        ),
        _row(id: 2, date: DateTime(2026, 5, 3), amount: 40000),
        _row(id: 3, date: DateTime(2026, 5, 4), amount: 10000),
        _row(
          id: 4,
          date: DateTime(2026, 5, 5),
          amount: 25000,
          type: TransactionType.transfer,
        ),
      ];

      final TransactionGroup group = groupTransactions(
        rows,
        TransactionGrouping.month,
      ).single;

      expect(group.start, DateTime(2026, 5));
      expect(group.income, 100000);
      expect(group.expense, 50000);
      expect(group.transfer, 25000);
      // Transfers must never inflate the net figure.
      expect(group.net, 50000);
    });

    test('year grouping merges every month of the same year', () {
      final List<FinancialTransaction> rows = <FinancialTransaction>[
        _row(id: 1, date: DateTime(2025, 12, 31), amount: 1000),
        _row(id: 2, date: DateTime(2026, 1, 1), amount: 2000),
        _row(id: 3, date: DateTime(2026, 11, 20), amount: 3000),
      ];

      final List<TransactionGroup> groups = groupTransactions(
        rows,
        TransactionGrouping.year,
      );

      expect(groups.map((g) => g.start), <DateTime>[
        DateTime(2025),
        DateTime(2026),
      ]);
      expect(groups.last.count, 2);
      expect(groups.last.expense, 5000);
    });

    test('empty input yields no groups', () {
      expect(
        groupTransactions(const <FinancialTransaction>[], TransactionGrouping.day),
        isEmpty,
      );
    });
  });

  group('transactionGroupLabel', () {
    final DateTime now = DateTime(2026, 5, 20, 12);

    TransactionGroup groupFor(DateTime start) => TransactionGroup(
      start: start,
      rows: const <FinancialTransaction>[],
      income: 0,
      expense: 0,
      transfer: 0,
    );

    test('day labels use relative names for today and yesterday', () {
      expect(
        transactionGroupLabel(
          groupFor(DateTime(2026, 5, 20)),
          TransactionGrouping.day,
          now: now,
        ),
        'Hari ini',
      );
      expect(
        transactionGroupLabel(
          groupFor(DateTime(2026, 5, 19)),
          TransactionGrouping.day,
          now: now,
        ),
        'Kemarin',
      );
    });

    test('older days fall back to a full date', () {
      final String label = transactionGroupLabel(
        groupFor(DateTime(2026, 5, 12)),
        TransactionGrouping.day,
        now: now,
      );
      expect(label, isNot('Hari ini'));
      expect(label, isNot('Kemarin'));
      expect(label, contains('12'));
      expect(label, contains('2026'));
    });

    test('month and year labels are stable', () {
      expect(
        transactionGroupLabel(
          groupFor(DateTime(2026, 5)),
          TransactionGrouping.month,
          now: now,
        ),
        contains('2026'),
      );
      expect(
        transactionGroupLabel(
          groupFor(DateTime(2026)),
          TransactionGrouping.year,
          now: now,
        ),
        '2026',
      );
    });
  });

  group('transactionGroupRange', () {
    test('day range covers exactly one day', () {
      final DateRange range = transactionGroupRange(
        TransactionGroup(
          start: DateTime(2026, 5, 20),
          rows: const <FinancialTransaction>[],
          income: 0,
          expense: 0,
          transfer: 0,
        ),
        TransactionGrouping.day,
      );
      expect(range.start, DateTime(2026, 5, 20));
      expect(range.end, DateTime(2026, 5, 21));
    });

    test('year range rolls over to the next year', () {
      final DateRange range = transactionGroupRange(
        TransactionGroup(
          start: DateTime(2026),
          rows: const <FinancialTransaction>[],
          income: 0,
          expense: 0,
          transfer: 0,
        ),
        TransactionGrouping.year,
      );
      expect(range.start, DateTime(2026));
      expect(range.end, DateTime(2027));
    });
  });
}
