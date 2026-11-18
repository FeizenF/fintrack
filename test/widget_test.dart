import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/app.dart';
import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/budgets_repository.dart';
import 'package:fintrack/core/database/repositories/savings_repository.dart';
import 'package:fintrack/core/database/repositories/summary_repository.dart';
import 'package:fintrack/core/router/app_router.dart';
import 'package:fintrack/core/theme/app_colors.dart';
import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/report_series.dart';
import 'package:fintrack/shared/providers/database_providers.dart';
import 'package:fintrack/shared/providers/security_providers.dart';

/// Wraps the app with empty data overrides so routing tests never touch
/// SQLite. Real database work needs `tester.runAsync`, which `pumpAndSettle`
/// cannot drive, so any live query would hang the navigation tests.
Widget scopedApp() {
  final DateTime now = DateTime.now();
  final DateTime month = DateTime(now.year, now.month);
  return ProviderScope(
    overrides: [
      // The lock gate reads secure storage; pin it to "no PIN" so routing tests
      // never wait on a platform channel that has no plugin in the test host.
      pinProtectionEnabledProvider.overrideWithValue(const AsyncData<bool>(false)),
      accountsProvider.overrideWithValue(
        const AsyncData<List<Account>>(<Account>[]),
      ),
      categoriesProvider.overrideWithValue(
        const AsyncData<List<Category>>(<Category>[]),
      ),
      for (final TransactionType? type in <TransactionType?>[
        null,
        ...TransactionType.values,
      ])
        filteredTransactionsProvider(type).overrideWithValue(
          const AsyncData<List<FinancialTransaction>>(<FinancialTransaction>[]),
        ),
      walletBalanceProvider.overrideWithValue(
        const AsyncData<WalletBalance>(
          WalletBalance(accounts: <AccountBalance>[], total: 0),
        ),
      ),
      budgetProgressProvider(month).overrideWithValue(
        const AsyncData<List<BudgetProgress>>(<BudgetProgress>[]),
      ),
      savingsProgressProvider.overrideWithValue(
        const AsyncData<List<SavingsProgress>>(<SavingsProgress>[]),
      ),
      archivedSavingsProgressProvider.overrideWithValue(
        const AsyncData<List<SavingsProgress>>(<SavingsProgress>[]),
      ),
      recentTransactionsProvider.overrideWithValue(
        const AsyncData<List<FinancialTransaction>>(<FinancialTransaction>[]),
      ),
      hideBalancesProvider.overrideWithValue(const AsyncData<bool>(false)),
      // The dashboard resolves its default "bulan ini" period from the clock,
      // so both range-keyed families are pinned to the current month.
      summaryTotalsProvider(DateRange.month(now)).overrideWithValue(
        const AsyncData<MonthlyTotals>(MonthlyTotals.empty()),
      ),
      expenseByCategoryRangeProvider(DateRange.month(now)).overrideWithValue(
        const AsyncData<List<CategoryAmount>>(<CategoryAmount>[]),
      ),
      periodSeriesProvider(
        ReportSeriesRequest(
          range: DateRange.month(now),
          granularity: ReportGranularity.day,
        ),
      ).overrideWithValue(
        const AsyncData<List<PeriodSeriesPoint>>(<PeriodSeriesPoint>[]),
      ),
      reportAccountBalancesProvider.overrideWithValue(
        const AsyncData<List<ReportAccountBalance>>(<ReportAccountBalance>[]),
      ),
    ],
    child: const FinTrackApp(),
  );
}

/// Renders the app on a phone-sized surface so the compact shell (bottom
/// navigation bar + FAB) is used, mirroring the Android target.
Future<void> pumpPhoneApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(scopedApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app boots into the home tab with all five destinations', (
    WidgetTester tester,
  ) async {
    await pumpPhoneApp(tester);

    expect(find.text('FinTrack'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>[
      'Beranda',
      'Transaksi',
      'Anggaran',
      'Laporan',
      'Pengaturan',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing tab $label');
    }
    expect(find.widgetWithText(FloatingActionButton, 'Catat'), findsOneWidget);
  });

  testWidgets('tapping a tab switches the visible page', (
    WidgetTester tester,
  ) async {
    await pumpPhoneApp(tester);

    await tester.tap(find.text('Transaksi').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Riwayat pemasukan, pengeluaran dan transfer'),
      findsOneWidget,
    );

    await tester.tap(find.text('Pengaturan').first);
    await tester.pumpAndSettle();
    expect(find.text('Data, keamanan dan preferensi aplikasi'), findsOneWidget);
  });

  testWidgets('add-transaction button opens the transaction form route', (
    WidgetTester tester,
  ) async {
    await pumpPhoneApp(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Catat'));
    await tester.pumpAndSettle();

    expect(find.text('Transaksi Baru'), findsWidgets);
  });

  testWidgets('settings navigation reaches accounts page', (
    WidgetTester tester,
  ) async {
    await pumpPhoneApp(tester);

    await tester.tap(find.text('Pengaturan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Akun Keuangan'));
    await tester.pumpAndSettle();

    expect(find.text('Akun Keuangan'), findsWidgets);
    expect(
      find.text('Belum ada akun. Tambahkan akun untuk mencatat transaksi.'),
      findsOneWidget,
    );
  });

  testWidgets('wide layout uses a navigation rail and a single FAB', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(scopedApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  test('theme palette exposes semantic colors for both brightness values', () {
    expect(AppColors.incomeOf(Brightness.light), AppColors.income);
    expect(AppColors.incomeOf(Brightness.dark), AppColors.incomeDark);
    expect(AppColors.expenseOf(Brightness.light), AppColors.expense);
  });

  test('router provider creates a scoped router', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(routerProvider), isNotNull);
  });
}
