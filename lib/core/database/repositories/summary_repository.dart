import 'package:drift/drift.dart';

import '../../utils/date_range.dart';
import '../../utils/report_series.dart';
import '../account_balances.dart';
import '../app_database.dart';
import '../enums.dart';

class ReportAccountBalance {
  const ReportAccountBalance({
    required this.accountId,
    required this.name,
    required this.type,
    required this.isArchived,
    required this.balance,
  });

  final int accountId;
  final String name;
  final AccountType type;
  final bool isArchived;
  final int balance;
}

/// Income and expense totals for one month.
class MonthlyTotals {
  const MonthlyTotals({required this.income, required this.expense});

  const MonthlyTotals.empty() : income = 0, expense = 0;

  final int income;
  final int expense;

  /// Positive when the month ended with a surplus.
  int get net => income - expense;

  bool get isEmpty => income == 0 && expense == 0;
}

/// One category and the amount booked to it inside a period.
class CategoryAmount {
  const CategoryAmount({
    required this.categoryId,
    required this.name,
    required this.amount,
  });

  final int categoryId;
  final String name;
  final int amount;
}

/// Income and expense totals for one calendar month.
class MonthlyHistory {
  const MonthlyHistory({
    required this.month,
    required this.income,
    required this.expense,
  });

  final DateTime month;
  final int income;
  final int expense;

  int get net => income - expense;
}

/// Aggregations over the ledger used by the dashboard and reports.
///
/// Every figure is a SQL `SUM` over the ledger rows in a half-open date range,
/// so a total can never disagree with the transactions that produced it and
/// transfers never distort income or expense.
class SummaryRepository {
  SummaryRepository(this._db);

  final AppDatabase _db;

  /// Live income/expense totals for [range].
  Stream<MonthlyTotals> watchRange(DateRange range) {
    const String sql = '''
SELECT
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS income,
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS expense
FROM transactions
WHERE transaction_date >= ? AND transaction_date < ?
''';

    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(TransactionType.income.name),
            Variable<String>(TransactionType.expense.name),
            Variable<DateTime>(range.start),
            Variable<DateTime>(range.end),
          ],
          readsFrom: <TableInfo<Table, Object?>>{_db.transactions},
        )
        .watchSingle()
        .map(
          (QueryRow row) => MonthlyTotals(
            income: row.read<int>('income'),
            expense: row.read<int>('expense'),
          ),
        );
  }

  Future<MonthlyTotals> month(DateTime date) =>
      watchRange(DateRange.month(date)).first;

  /// Live totals for the calendar month containing [date].
  Stream<MonthlyTotals> watchMonth(DateTime date) =>
      watchRange(DateRange.month(date));

  /// Live expense totals per category for [range].
  Stream<List<CategoryAmount>> watchExpenseByCategoryInRange(DateRange range) {
    return _categoryTotals(range: range, type: TransactionType.expense);
  }

  /// Live income and expense totals grouped by calendar month inside [range].
  Stream<List<MonthlyHistory>> watchMonthlyHistory(DateRange range) {
    const String sql = '''
SELECT
  CAST(strftime('%Y', transaction_date, 'unixepoch', 'localtime') AS INTEGER) AS year,
  CAST(strftime('%m', transaction_date, 'unixepoch', 'localtime') AS INTEGER) AS month,
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS income,
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS expense
FROM transactions
WHERE transaction_date >= ? AND transaction_date < ?
GROUP BY year, month
ORDER BY year, month
''';
    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(TransactionType.income.name),
            Variable<String>(TransactionType.expense.name),
            Variable<DateTime>(range.start),
            Variable<DateTime>(range.end),
          ],
          readsFrom: <TableInfo<Table, Object?>>{_db.transactions},
        )
        .watch()
        .map(
          (List<QueryRow> rows) => rows
              .map(
                (QueryRow row) => MonthlyHistory(
                  month: DateTime(
                    row.read<int>('year'),
                    row.read<int>('month'),
                  ),
                  income: row.read<int>('income'),
                  expense: row.read<int>('expense'),
                ),
              )
              .toList(growable: false),
        );
  }

  /// Live income/expense totals grouped by day or month for [range].
  Stream<List<PeriodSeriesPoint>> watchPeriodSeries(
    DateRange range,
    ReportGranularity granularity,
  ) {
    final String bucketExpression = granularity == ReportGranularity.day
        ? "date(transaction_date, 'unixepoch', 'localtime')"
        : "strftime('%Y-%m', transaction_date, 'unixepoch', 'localtime')";
    final String sql =
        '''
SELECT
  $bucketExpression AS bucket,
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS income,
  COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS expense
FROM transactions
WHERE transaction_date >= ? AND transaction_date < ?
GROUP BY bucket
ORDER BY bucket
''';
    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(TransactionType.income.name),
            Variable<String>(TransactionType.expense.name),
            Variable<DateTime>(range.start),
            Variable<DateTime>(range.end),
          ],
          readsFrom: <TableInfo<Table, Object?>>{_db.transactions},
        )
        .watch()
        .map(
          (List<QueryRow> rows) => rows
              .map((QueryRow row) {
                final String key = row.read<String>('bucket');
                final List<String> parts = key.split('-');
                final DateTime bucket = granularity == ReportGranularity.day
                    ? DateTime(
                        int.parse(parts[0]),
                        int.parse(parts[1]),
                        int.parse(parts[2]),
                      )
                    : DateTime(int.parse(parts[0]), int.parse(parts[1]));
                return PeriodSeriesPoint(
                  bucket: bucket,
                  income: row.read<int>('income'),
                  expense: row.read<int>('expense'),
                );
              })
              .toList(growable: false),
        );
  }

  /// Current account balances derived from the shared balance calculator, so
  /// reports and the dashboard can never disagree about an account balance.
  Stream<List<ReportAccountBalance>> watchAccountBalances() {
    return _db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM accounts) AS accounts',
          readsFrom: <TableInfo<Table, Object?>>{
            _db.accounts,
            _db.transactions,
            _db.savingsContributions,
          },
        )
        .watch()
        .asyncMap((_) async {
          final List<Account> accounts =
              await (_db.select(_db.accounts)
                    ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
                      (t) => OrderingTerm.asc(t.isArchived),
                      (t) => OrderingTerm.asc(t.sortOrder),
                      (t) => OrderingTerm.asc(t.name),
                    ]))
                  .get();
          final List<AccountBalance> balances = await AccountBalanceCalculator(
            _db,
          ).all(includeArchived: true);
          final Map<int, int> byAccount = <int, int>{
            for (final AccountBalance balance in balances)
              balance.accountId: balance.currentBalance,
          };
          return <ReportAccountBalance>[
            for (final Account account in accounts)
              ReportAccountBalance(
                accountId: account.id,
                name: account.name,
                type: account.type,
                isArchived: account.isArchived,
                balance: byAccount[account.id] ?? 0,
              ),
          ];
        });
  }

  /// Live expense totals per category for the month containing [date].
  Stream<List<CategoryAmount>> watchExpenseByCategory(DateTime date) {
    return _categoryTotals(
      range: DateRange.month(date),
      type: TransactionType.expense,
    );
  }

  /// Months are separate calls so the dashboard and reports share one code path.
  Future<List<CategoryAmount>> expenseByCategory(DateTime date) =>
      watchExpenseByCategory(date).first;

  /// Live income totals per category for the month containing [date].
  Stream<List<CategoryAmount>> watchIncomeByCategory(DateTime date) {
    return _categoryTotals(
      range: DateRange.month(date),
      type: TransactionType.income,
    );
  }

  Stream<List<CategoryAmount>> _categoryTotals({
    required DateRange range,
    required TransactionType type,
  }) {
    const String sql = '''
SELECT
  t.category_id AS category_id,
  c.name AS category_name,
  COALESCE(SUM(t.amount), 0) AS total
FROM transactions t
JOIN categories c ON c.id = t.category_id
WHERE t.type = ? AND t.transaction_date >= ? AND t.transaction_date < ?
GROUP BY t.category_id
ORDER BY total DESC, c.name
''';

    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(type.name),
            Variable<DateTime>(range.start),
            Variable<DateTime>(range.end),
          ],
          readsFrom: <TableInfo<Table, Object?>>{
            _db.transactions,
            _db.categories,
          },
        )
        .watch()
        .map(
          (List<QueryRow> rows) => rows
              .map(
                (QueryRow row) => CategoryAmount(
                  categoryId: row.read<int>('category_id'),
                  name: row.read<String>('category_name'),
                  amount: row.read<int>('total'),
                ),
              )
              .toList(growable: false),
        );
  }
}
