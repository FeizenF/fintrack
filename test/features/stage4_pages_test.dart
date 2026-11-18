import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/budgets_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/savings_repository.dart';
import 'package:fintrack/core/database/repositories/summary_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/report_series.dart';
import 'package:fintrack/features/budgets/presentation/budgets_page.dart';
import 'package:fintrack/features/dashboard/presentation/dashboard_page.dart';
import 'package:fintrack/features/savings/presentation/savings_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  late AppDatabase database;
  late AccountsRepository accounts;
  late BudgetsRepository budgets;
  late CategoriesRepository categories;
  late SavingsRepository savings;
  late TransactionsRepository transactions;
  late SummaryRepository summary;
  late int accountId;
  late int expenseCategoryId;
  late List<Account> accountRows;
  late List<Category> categoryRows;
  late DateTime month;

  setUp(() async {
    database = AppDatabase.forTesting();
    await database.customSelect('SELECT 1').get();
    await database.ensureSeeded();
    accounts = AccountsRepository(database);
    budgets = BudgetsRepository(database);
    categories = CategoriesRepository(database);
    savings = SavingsRepository(database);
    transactions = TransactionsRepository(database);
    summary = SummaryRepository(database);
    month = DateTime.now();
    accountId = await accounts.create(
      name: 'Dompet utama',
      type: AccountType.cash,
      initialBalance: 500000,
    );
    accountRows = await accounts.list(includeArchived: true);
    categoryRows = await categories.list(includeArchived: true);
    expenseCategoryId = categoryRows
        .firstWhere((Category row) => row.kind == CategoryKind.expense)
        .id;
  });

  tearDown(() async => database.close());

  /// Unmounts while drift's stream-store cleanup timers run on the real clock,
  /// otherwise `testWidgets` fails on pending timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  List<Override> overridesFor({
    List<BudgetProgress> budgetRows = const <BudgetProgress>[],
    List<SavingsProgress> savingsRows = const <SavingsProgress>[],
    List<FinancialTransaction> recentRows = const <FinancialTransaction>[],
    int walletTotal = 500000,
    bool hideBalances = false,
  }) {
    final DateTime now = DateTime.now();
    final DateRange range = DateRange.month(now);
    return <Override>[
      appDatabaseProvider.overrideWith((Ref ref) async => database),
      accountsRepositoryProvider.overrideWith((Ref ref) async => accounts),
      budgetsRepositoryProvider.overrideWith((Ref ref) async => budgets),
      categoriesRepositoryProvider.overrideWith((Ref ref) async => categories),
      savingsRepositoryProvider.overrideWith((Ref ref) async => savings),
      transactionsRepositoryProvider.overrideWith(
        (Ref ref) async => transactions,
      ),
      summaryRepositoryProvider.overrideWith((Ref ref) async => summary),
      categoriesProvider.overrideWithValue(
        AsyncData<List<Category>>(categoryRows),
      ),
      accountsProvider.overrideWithValue(AsyncData<List<Account>>(accountRows)),
      budgetProgressProvider(DateTime(month.year, month.month))
          .overrideWithValue(AsyncData<List<BudgetProgress>>(budgetRows)),
      savingsProgressProvider.overrideWithValue(
        AsyncData<List<SavingsProgress>>(savingsRows),
      ),
      archivedSavingsProgressProvider.overrideWithValue(
        AsyncData<List<SavingsProgress>>(savingsRows),
      ),
      recentTransactionsProvider.overrideWithValue(
        AsyncData<List<FinancialTransaction>>(recentRows),
      ),
      walletBalanceProvider.overrideWithValue(
        AsyncData<WalletBalance>(
          WalletBalance(accounts: const <AccountBalance>[], total: walletTotal),
        ),
      ),
      summaryTotalsProvider(range).overrideWithValue(
        const AsyncData<MonthlyTotals>(
          MonthlyTotals(income: 200000, expense: 75000),
        ),
      ),
      expenseByCategoryRangeProvider(range).overrideWithValue(
        const AsyncData<List<CategoryAmount>>(<CategoryAmount>[]),
      ),
      periodSeriesProvider(
        ReportSeriesRequest(
          range: range,
          granularity: ReportGranularity.day,
        ),
      ).overrideWithValue(
        const AsyncData<List<PeriodSeriesPoint>>(<PeriodSeriesPoint>[]),
      ),
      reportAccountBalancesProvider.overrideWithValue(
        const AsyncData<List<ReportAccountBalance>>(<ReportAccountBalance>[]),
      ),
      hideBalancesProvider.overrideWithValue(AsyncData<bool>(hideBalances)),
    ];
  }

  Widget host(List<Override> overrides, Widget child) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );

  testWidgets('budgets page shows ledger usage and creates another budget', (
    WidgetTester tester,
  ) async {
    late List<BudgetProgress> rows;
    await tester.runAsync(() async {
      await budgets.create(
        categoryId: expenseCategoryId,
        monthStart: month,
        limitAmount: 100000,
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: expenseCategoryId,
        amount: 85000,
        date: DateTime(month.year, month.month, 5),
      );
      rows = await budgets.list(month);
    });

    await tester.pumpWidget(
      host(overridesFor(budgetRows: rows), const BudgetsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text(rows.single.categoryName), findsOneWidget);
    expect(find.textContaining('Mendekati batas'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Terpakai Rp 85.000'), findsOneWidget);

    await tester.tap(find.text('Tambah anggaran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '250000');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      final List<BudgetProgress> updated = await budgets.list(month);
      expect(updated, hasLength(2));
      expect(updated.map((BudgetProgress row) => row.limit), contains(250000));
    });
  });

  testWidgets('savings page deposits into the goal and moves account balance', (
    WidgetTester tester,
  ) async {
    late SavingsProgress progress;
    late int goalId;
    await tester.runAsync(() async {
      goalId = await savings.createGoal(
        name: 'Dana darurat',
        targetAmount: 1000000,
        targetDate: DateTime(2027, 1, 1),
        note: 'Enam bulan biaya hidup',
      );
      progress = (await savings.progress()).single;
    });

    await tester.pumpWidget(
      host(
        overridesFor(savingsRows: <SavingsProgress>[progress]),
        const SavingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dana darurat'), findsOneWidget);
    expect(find.text('Rp 0 dari Rp 1.000.000'), findsOneWidget);

    await tester.tap(find.text('Setor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '150000');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan setoran'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      final SavingsProgress updated = (await savings.progress()).single;
      expect(updated.goal.id, goalId);
      expect(updated.saved, 150000);
      expect(
        (await AccountBalanceCalculator(database).forAccount(accountId))!
            .currentBalance,
        350000,
      );
    });
  });

  testWidgets('dashboard shows period totals and saves the hide toggle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(overridesFor(), const DashboardPage()));
    await tester.pumpAndSettle();

    expect(find.text('FinTrack'), findsOneWidget);
    expect(find.text('Rp 500.000'), findsOneWidget);
    expect(find.text('Rp 200.000'), findsOneWidget);
    expect(find.text('Rp 75.000'), findsOneWidget);

    await tester.tap(find.byTooltip('Sembunyikan saldo'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      expect(await database.readSetting(SettingKeys.hideBalances), '1');
    });
  });
}
