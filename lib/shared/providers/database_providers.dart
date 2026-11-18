import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Table, TableInfo, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/account_balances.dart';
import '../../core/database/app_database.dart';
import '../../core/database/enums.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/report_series.dart';
import '../../core/database/repositories/accounts_repository.dart';
import '../../core/database/repositories/categories_repository.dart';
import '../../core/database/repositories/transactions_repository.dart';
import '../../core/database/repositories/budgets_repository.dart';
import '../../core/database/repositories/savings_repository.dart';
import '../../core/database/repositories/summary_repository.dart';

final FutureProvider<AppDatabase> appDatabaseProvider =
    FutureProvider<AppDatabase>((Ref ref) async {
      final File file = await AppDatabase.defaultDatabaseFile();
      final AppDatabase database = AppDatabase.atFile(file);
      await database.customSelect('SELECT 1').get();
      await database.ensureSeeded();
      ref.onDispose(database.close);
      return database;
    });

final FutureProvider<AccountsRepository> accountsRepositoryProvider =
    FutureProvider<AccountsRepository>(
      (Ref ref) async =>
          AccountsRepository(await ref.watch(appDatabaseProvider.future)),
    );

final FutureProvider<CategoriesRepository> categoriesRepositoryProvider =
    FutureProvider<CategoriesRepository>(
      (Ref ref) async =>
          CategoriesRepository(await ref.watch(appDatabaseProvider.future)),
    );

final FutureProvider<TransactionsRepository> transactionsRepositoryProvider =
    FutureProvider<TransactionsRepository>(
      (Ref ref) async =>
          TransactionsRepository(await ref.watch(appDatabaseProvider.future)),
    );

final FutureProvider<BudgetsRepository> budgetsRepositoryProvider =
    FutureProvider<BudgetsRepository>(
      (Ref ref) async =>
          BudgetsRepository(await ref.watch(appDatabaseProvider.future)),
    );

final FutureProvider<SavingsRepository> savingsRepositoryProvider =
    FutureProvider<SavingsRepository>(
      (Ref ref) async =>
          SavingsRepository(await ref.watch(appDatabaseProvider.future)),
    );

final FutureProvider<SummaryRepository> summaryRepositoryProvider =
    FutureProvider<SummaryRepository>(
      (Ref ref) async =>
          SummaryRepository(await ref.watch(appDatabaseProvider.future)),
    );

final StreamProvider<List<Account>> accountsProvider =
    StreamProvider<List<Account>>((Ref ref) async* {
      final AccountsRepository repository = await ref.watch(
        accountsRepositoryProvider.future,
      );
      yield* repository.watch(includeArchived: true);
    });

final StreamProvider<List<Category>> categoriesProvider =
    StreamProvider<List<Category>>((Ref ref) async* {
      final CategoriesRepository repository = await ref.watch(
        categoriesRepositoryProvider.future,
      );
      yield* repository.watch(includeArchived: true);
    });

final StreamProvider<List<FinancialTransaction>> transactionsProvider =
    StreamProvider<List<FinancialTransaction>>((Ref ref) async* {
      final TransactionsRepository repository = await ref.watch(
        transactionsRepositoryProvider.future,
      );
      yield* repository.watch();
    });

final FutureProvider<AccountBalanceCalculator>
accountBalanceCalculatorProvider = FutureProvider<AccountBalanceCalculator>(
  (Ref ref) async =>
      AccountBalanceCalculator(await ref.watch(appDatabaseProvider.future)),
);

final accountByIdProvider = FutureProvider.family<Account?, int>((
  Ref ref,
  int id,
) async {
  final AccountsRepository repository = await ref.watch(
    accountsRepositoryProvider.future,
  );
  return repository.byId(id);
});

final categoryByIdProvider = FutureProvider.family<Category?, int>((
  Ref ref,
  int id,
) async {
  final CategoriesRepository repository = await ref.watch(
    categoriesRepositoryProvider.future,
  );
  return repository.byId(id);
});

final transactionByIdProvider =
    FutureProvider.family<FinancialTransaction?, int>((Ref ref, int id) async {
      final TransactionsRepository repository = await ref.watch(
        transactionsRepositoryProvider.future,
      );
      return repository.byId(id);
    });

final accountBalanceProvider = StreamProvider.family<AccountBalance?, int>((
  Ref ref,
  int id,
) async* {
  final AppDatabase database = await ref.watch(appDatabaseProvider.future);
  final AccountBalanceCalculator calculator = AccountBalanceCalculator(
    database,
  );
  yield* database
      .customSelect(
        'SELECT id FROM accounts WHERE id = ?',
        variables: <Variable<Object>>[Variable<int>(id)],
        readsFrom: <TableInfo<Table, Object?>>{
          database.accounts,
          database.transactions,
          database.savingsContributions,
        },
      )
      .watch()
      .asyncMap((_) => calculator.forAccount(id));
});

final filteredTransactionsProvider =
    StreamProvider.family<List<FinancialTransaction>, TransactionType?>((
      Ref ref,
      TransactionType? type,
    ) async* {
      final TransactionsRepository repository = await ref.watch(
        transactionsRepositoryProvider.future,
      );
      yield* repository.watch(type: type);
    });

/// Live wallet balance: re-computes whenever an account, transaction or savings
/// row changes, because those are exactly the tables the balance reads.
final StreamProvider<WalletBalance> walletBalanceProvider =
    StreamProvider<WalletBalance>((Ref ref) async* {
      final AppDatabase database = await ref.watch(appDatabaseProvider.future);
      final AccountBalanceCalculator calculator = AccountBalanceCalculator(
        database,
      );
      yield* database
          .customSelect(
            'SELECT (SELECT COUNT(*) FROM accounts) AS accounts, '
            '(SELECT COUNT(*) FROM transactions) AS transactions, '
            '(SELECT COUNT(*) FROM savings_contributions) AS savings',
            readsFrom: <TableInfo<Table, Object?>>{
              database.accounts,
              database.transactions,
              database.savingsContributions,
            },
          )
          .watch()
          .asyncMap((_) => calculator.wallet());
    });

/// Live income/expense totals for the month containing the given date.
final monthlyTotalsProvider = StreamProvider.family<MonthlyTotals, DateTime>((
  Ref ref,
  DateTime month,
) async* {
  final SummaryRepository repository = await ref.watch(
    summaryRepositoryProvider.future,
  );
  yield* repository.watchMonth(month);
});

/// Live expense totals per category for the month containing the given date.
final expenseByCategoryProvider =
    StreamProvider.family<List<CategoryAmount>, DateTime>((
      Ref ref,
      DateTime month,
    ) async* {
      final SummaryRepository repository = await ref.watch(
        summaryRepositoryProvider.future,
      );
      yield* repository.watchExpenseByCategory(month);
    });

/// Live budgets plus spent totals for the month containing the given date.
final budgetProgressProvider =
    StreamProvider.family<List<BudgetProgress>, DateTime>((
      Ref ref,
      DateTime month,
    ) async* {
      final BudgetsRepository repository = await ref.watch(
        budgetsRepositoryProvider.future,
      );
      yield* repository.watch(month);
    });

/// Live savings goals with their saved amounts.
final StreamProvider<List<SavingsProgress>> savingsProgressProvider =
    StreamProvider<List<SavingsProgress>>((Ref ref) async* {
      final SavingsRepository repository = await ref.watch(
        savingsRepositoryProvider.future,
      );
      yield* repository.watch();
    });

/// Same as [savingsProgressProvider] but including archived goals, so a goal
/// that was archived can still be reviewed and restored.
final StreamProvider<List<SavingsProgress>> archivedSavingsProgressProvider =
    StreamProvider<List<SavingsProgress>>((Ref ref) async* {
      final SavingsRepository repository = await ref.watch(
        savingsRepositoryProvider.future,
      );
      yield* repository.watch(includeArchived: true);
    });

/// Live income/expense totals for an arbitrary date range.
final summaryTotalsProvider = StreamProvider.family<MonthlyTotals, DateRange>((
  Ref ref,
  DateRange range,
) async* {
  final SummaryRepository repository = await ref.watch(
    summaryRepositoryProvider.future,
  );
  yield* repository.watchRange(range);
});

/// Live income and expense totals grouped into chart buckets for a range.
final periodSeriesProvider =
    StreamProvider.family<List<PeriodSeriesPoint>, ReportSeriesRequest>((
      Ref ref,
      ReportSeriesRequest request,
    ) async* {
      final SummaryRepository repository = await ref.watch(
        summaryRepositoryProvider.future,
      );
      yield* repository.watchPeriodSeries(request.range, request.granularity);
    });

/// Live current balances grouped by account, including archived accounts.
final reportAccountBalancesProvider =
    StreamProvider<List<ReportAccountBalance>>((Ref ref) async* {
      final SummaryRepository repository = await ref.watch(
        summaryRepositoryProvider.future,
      );
      yield* repository.watchAccountBalances();
    });

/// Live income/expense totals grouped by calendar month for a range.
final monthlyHistoryProvider =
    StreamProvider.family<List<MonthlyHistory>, DateRange>((
      Ref ref,
      DateRange range,
    ) async* {
      final SummaryRepository repository = await ref.watch(
        summaryRepositoryProvider.future,
      );
      yield* repository.watchMonthlyHistory(range);
    });

/// Live expense totals per category for an arbitrary date range.
final expenseByCategoryRangeProvider =
    StreamProvider.family<List<CategoryAmount>, DateRange>((
      Ref ref,
      DateRange range,
    ) async* {
      final SummaryRepository repository = await ref.watch(
        summaryRepositoryProvider.future,
      );
      yield* repository.watchExpenseByCategoryInRange(range);
    });

/// Newest transactions for the dashboard preview.
final recentTransactionsProvider = StreamProvider<List<FinancialTransaction>>((
  Ref ref,
) async* {
  final TransactionsRepository repository = await ref.watch(
    transactionsRepositoryProvider.future,
  );
  yield* repository.watch(limit: 5);
});

/// Whether amounts should be masked on screen. Stored in `app_settings`, so the
/// preference survives restarts without touching any financial data.
final StreamProvider<bool> hideBalancesProvider = StreamProvider<bool>((
  Ref ref,
) async* {
  final AppDatabase database = await ref.watch(appDatabaseProvider.future);
  yield* database
      .customSelect(
        'SELECT value FROM app_settings WHERE key = ?',
        variables: <Variable<Object>>[
          Variable<String>(SettingKeys.hideBalances),
        ],
        readsFrom: <TableInfo<Table, Object?>>{database.appSettings},
      )
      .watch()
      .map(
        (List<QueryRow> rows) =>
            rows.isNotEmpty && rows.single.read<String>('value') == '1',
      );
});

/// Writes the balance-masking preference. The stream above re-emits afterwards.
Future<void> setHideBalances(WidgetRef ref, bool value) async {
  final AppDatabase database = await ref.read(appDatabaseProvider.future);
  await database.saveSetting(SettingKeys.hideBalances, value ? '1' : '0');
}
