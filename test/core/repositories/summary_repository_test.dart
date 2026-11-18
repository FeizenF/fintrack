import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/summary_repository.dart';
import 'package:fintrack/core/database/repositories/savings_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/report_series.dart';

void main() {
  late AppDatabase db;
  late int accountId;
  late int incomeCategoryId;
  late int expenseCategoryId;
  late SummaryRepository summaries;
  late TransactionsRepository transactions;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    accountId = await AccountsRepository(db)
        .create(name: 'Dompet', type: AccountType.cash, initialBalance: 0);
    final CategoriesRepository categories = CategoriesRepository(db);
    incomeCategoryId = (await categories.list(kind: CategoryKind.income))
        .first
        .id;
    expenseCategoryId = (await categories.list(kind: CategoryKind.expense))
        .first
        .id;
    summaries = SummaryRepository(db);
    transactions = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  test(
    'monthly totals include income and expense but exclude transfers',
    () async {
      await transactions.createIncome(
        accountId: accountId,
        categoryId: incomeCategoryId,
        amount: 1000000,
        date: DateTime(2026, 5, 1),
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: expenseCategoryId,
        amount: 275000,
        date: DateTime(2026, 5, 31, 23, 59),
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: expenseCategoryId,
        amount: 50000,
        date: DateTime(2026, 6, 1),
      );

      final MonthlyTotals totals = await summaries.month(DateTime(2026, 5, 19));
      expect(totals.income, 1000000);
      expect(totals.expense, 275000);
      expect(totals.net, 725000);
    },
  );

  test('category totals rank expenses and do not count transfers', () async {
    final List<Category> expenseCategories = await CategoriesRepository(db)
        .list(kind: CategoryKind.expense);
    final int secondCategoryId = expenseCategories.last.id;
    await transactions.createExpense(
      accountId: accountId,
      categoryId: expenseCategoryId,
      amount: 50000,
      date: DateTime(2026, 5, 2),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: secondCategoryId,
      amount: 120000,
      date: DateTime(2026, 5, 3),
    );

    final List<CategoryAmount> totals = await summaries.expenseByCategory(
      DateTime(2026, 5),
    );
    expect(totals.map((row) => row.amount), <int>[120000, 50000]);
    expect(totals.first.categoryId, secondCategoryId);
  });

  test('empty month returns zero totals and no categories', () async {
    final MonthlyTotals totals = await summaries.month(DateTime(2026, 5));
    expect(totals.income, 0);
    expect(totals.expense, 0);
    expect(totals.net, 0);
    expect(await summaries.expenseByCategory(DateTime(2026, 5)), isEmpty);
  });

  test('monthly history groups ledger rows by calendar month', () async {
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 800000,
      date: DateTime(2026, 3, 4, 9),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: expenseCategoryId,
      amount: 300000,
      date: DateTime(2026, 3, 28, 21),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: expenseCategoryId,
      amount: 125000,
      date: DateTime(2026, 4, 1, 0, 30),
    );
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 900000,
      date: DateTime(2026, 4, 30, 23, 59),
    );
    // Outside the range: must not appear in the history.
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 5000000,
      date: DateTime(2026, 6, 2),
    );

    final List<MonthlyHistory> history = await summaries
        .watchMonthlyHistory(
          DateRange.inclusive(DateTime(2026, 3, 1), DateTime(2026, 4, 30)),
        )
        .first;

    expect(history, hasLength(2));
    expect(history[0].month, DateTime(2026, 3));
    expect(history[0].income, 800000);
    expect(history[0].expense, 300000);
    expect(history[0].net, 500000);
    expect(history[1].month, DateTime(2026, 4));
    expect(history[1].income, 900000);
    expect(history[1].expense, 125000);
  });

  test('monthly history excludes transfers from both buckets', () async {
    final int secondAccountId = await AccountsRepository(db)
        .create(name: 'Bank', type: AccountType.bank);

    await transactions.createTransfer(
      fromAccountId: accountId,
      toAccountId: secondAccountId,
      amount: 250000,
      date: DateTime(2026, 5, 10),
    );

    final List<MonthlyHistory> history = await summaries
        .watchMonthlyHistory(DateRange.month(DateTime(2026, 5)))
        .first;

    expect(history, hasLength(1));
    expect(history.single.income, 0);
    expect(history.single.expense, 0);
  });

  test(
    'account balances include transfers, savings and initial balance',
    () async {
      final int secondAccountId = await AccountsRepository(db)
          .create(name: 'Bank', type: AccountType.bank, initialBalance: 400000);
      await transactions.createIncome(
        accountId: accountId,
        categoryId: incomeCategoryId,
        amount: 300000,
        date: DateTime(2026, 5, 2),
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: expenseCategoryId,
        amount: 90000,
        date: DateTime(2026, 5, 3),
      );
      await transactions.createTransfer(
        fromAccountId: accountId,
        toAccountId: secondAccountId,
        amount: 150000,
        date: DateTime(2026, 5, 4),
      );
      final int goalId = await SavingsRepository(db)
          .createGoal(name: 'Liburan', targetAmount: 2000000);
      await SavingsRepository(db).deposit(
        goalId: goalId,
        accountId: secondAccountId,
        amount: 50000,
        date: DateTime(2026, 5, 5),
      );

      final List<ReportAccountBalance> balances = await summaries
          .watchAccountBalances()
          .first;

      expect(balances, hasLength(2));
      final ReportAccountBalance cash = balances.firstWhere(
        (ReportAccountBalance row) => row.accountId == accountId,
      );
      expect(cash.balance, 300000 - 90000 - 150000);
      expect(cash.type, AccountType.cash);
      expect(cash.isArchived, isFalse);

      final ReportAccountBalance bank = balances.firstWhere(
        (ReportAccountBalance row) => row.accountId == secondAccountId,
      );
      expect(bank.balance, 400000 + 150000 - 50000);
    },
  );

  test('period series groups per day for short ranges', () async {
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 100000,
      date: DateTime(2026, 5, 2, 8),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: expenseCategoryId,
      amount: 40000,
      date: DateTime(2026, 5, 2, 20),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: expenseCategoryId,
      amount: 15000,
      date: DateTime(2026, 5, 3),
    );

    final List<PeriodSeriesPoint> points = await summaries
        .watchPeriodSeries(
          DateRange.inclusive(DateTime(2026, 5, 1), DateTime(2026, 5, 3)),
          ReportGranularity.day,
        )
        .first;

    expect(points, hasLength(2));
    expect(points[0].bucket, DateTime(2026, 5, 2));
    expect(points[0].income, 100000);
    expect(points[0].expense, 40000);
    expect(points[1].bucket, DateTime(2026, 5, 3));
    expect(points[1].income, 0);
    expect(points[1].expense, 15000);
  });

  test('period series groups per month for long ranges', () async {
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 500000,
      date: DateTime(2026, 1, 15),
    );
    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 750000,
      date: DateTime(2026, 3, 15),
    );

    final List<PeriodSeriesPoint> points = await summaries
        .watchPeriodSeries(
          DateRange.year(DateTime(2026, 6)),
          ReportGranularity.month,
        )
        .first;

    expect(points.map((PeriodSeriesPoint point) => point.bucket), <DateTime>[
      DateTime(2026, 1),
      DateTime(2026, 3),
    ]);
    expect(points[1].income, 750000);
  });

  test('watchPeriodSeries emits a reactive updated aggregate', () async {
    final Stream<List<PeriodSeriesPoint>> stream = summaries.watchPeriodSeries(
      DateRange.month(DateTime(2026, 5)),
      ReportGranularity.day,
    );
    final dynamic subscription = stream.listen((_) {});

    await transactions.createIncome(
      accountId: accountId,
      categoryId: incomeCategoryId,
      amount: 300000,
      date: DateTime(2026, 5, 2),
    );

    final List<PeriodSeriesPoint> emitted = await stream.first;
    expect(emitted, hasLength(1));
    expect(emitted.single.income, 300000);
    await subscription.cancel();
  });

  test('account balances keep archived accounts visible', () async {
    final AccountsRepository accounts = AccountsRepository(db);
    final int archivedId = await accounts.create(
      name: 'Dompet lama',
      type: AccountType.cash,
      initialBalance: 75000,
    );
    await accounts.setArchived(archivedId, true);

    final List<ReportAccountBalance> balances = await summaries
        .watchAccountBalances()
        .first;

    final ReportAccountBalance archived = balances.firstWhere(
      (ReportAccountBalance row) => row.accountId == archivedId,
    );
    expect(archived.isArchived, isTrue);
    expect(archived.balance, 75000);
  });
}
