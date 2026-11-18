import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/summary_repository.dart';
import 'package:fintrack/core/utils/date_range.dart';
import 'package:fintrack/core/utils/report_series.dart';
import 'package:fintrack/features/reports/presentation/reports_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  testWidgets('reports show period charts, categories, history and accounts', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now();
    final DateRange range = DateRange.month(now);
    final List<Override> overrides = <Override>[
      accountsProvider.overrideWithValue(
        const AsyncData<List<Account>>(<Account>[]),
      ),
      categoriesProvider.overrideWithValue(
        const AsyncData<List<Category>>(<Category>[]),
      ),
      walletBalanceProvider.overrideWithValue(
        const AsyncData<WalletBalance>(
          WalletBalance(accounts: <AccountBalance>[], total: 0),
        ),
      ),
      summaryTotalsProvider(range).overrideWithValue(
        const AsyncData<MonthlyTotals>(
          MonthlyTotals(income: 1200000, expense: 450000),
        ),
      ),
      summaryTotalsProvider(previousReportRange(range, PeriodFilter.thisMonth))
          .overrideWithValue(
            const AsyncData<MonthlyTotals>(
              MonthlyTotals(income: 1000000, expense: 500000),
            ),
          ),
      expenseByCategoryRangeProvider(range).overrideWithValue(
        const AsyncData<List<CategoryAmount>>(<CategoryAmount>[
          CategoryAmount(categoryId: 1, name: 'Makanan', amount: 300000),
          CategoryAmount(categoryId: 2, name: 'Transportasi', amount: 150000),
        ]),
      ),
      periodSeriesProvider(
        ReportSeriesRequest(range: range, granularity: granularityFor(range)),
      ).overrideWithValue(
        AsyncData<List<PeriodSeriesPoint>>(<PeriodSeriesPoint>[
          PeriodSeriesPoint(
            bucket: DateTime(now.year, now.month, 2),
            income: 1200000,
            expense: 450000,
          ),
        ]),
      ),
      monthlyHistoryProvider(range).overrideWithValue(
        AsyncData<List<MonthlyHistory>>(<MonthlyHistory>[
          MonthlyHistory(
            month: DateTime(now.year, now.month),
            income: 1200000,
            expense: 450000,
          ),
        ]),
      ),
      reportAccountBalancesProvider.overrideWithValue(
        const AsyncData<List<ReportAccountBalance>>(<ReportAccountBalance>[
          ReportAccountBalance(
            accountId: 1,
            name: 'Dompet',
            type: AccountType.cash,
            isArchived: false,
            balance: 750000,
          ),
        ]),
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: ReportsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Pemasukan dan pengeluaran'), findsOneWidget);
    expect(find.text('Pengeluaran per kategori'), findsOneWidget);
    expect(find.text('Makanan'), findsOneWidget);
    expect(find.text('Riwayat bulanan'), findsOneWidget);
    expect(find.text('Ringkasan akun'), findsOneWidget);
    expect(find.text('Dompet'), findsOneWidget);
    expect(find.text('Perubahan dari periode sebelumnya'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets(
    'reports switch period and show no comparator when previous is empty',
    (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final DateRange month = DateRange.month(now);
      final DateRange year = DateRange.year(now);
      final DateRange lastYear = previousReportRange(
        year,
        PeriodFilter.thisYear,
      );
      final List<Override> overrides = <Override>[
        summaryTotalsProvider(month).overrideWithValue(
          const AsyncData<MonthlyTotals>(
            MonthlyTotals(income: 1000000, expense: 250000),
          ),
        ),
        summaryTotalsProvider(
          previousReportRange(month, PeriodFilter.thisMonth),
        ).overrideWithValue(
          const AsyncData<MonthlyTotals>(
            MonthlyTotals(income: 800000, expense: 500000),
          ),
        ),
        summaryTotalsProvider(year).overrideWithValue(
          const AsyncData<MonthlyTotals>(
            MonthlyTotals(income: 9000000, expense: 3000000),
          ),
        ),
        summaryTotalsProvider(lastYear).overrideWithValue(
          const AsyncData<MonthlyTotals>(MonthlyTotals.empty()),
        ),
        expenseByCategoryRangeProvider(month).overrideWithValue(
          const AsyncData<List<CategoryAmount>>(<CategoryAmount>[]),
        ),
        expenseByCategoryRangeProvider(year).overrideWithValue(
          const AsyncData<List<CategoryAmount>>(<CategoryAmount>[]),
        ),
        periodSeriesProvider(
          ReportSeriesRequest(range: month, granularity: granularityFor(month)),
        ).overrideWithValue(
          const AsyncData<List<PeriodSeriesPoint>>(<PeriodSeriesPoint>[]),
        ),
        periodSeriesProvider(
          ReportSeriesRequest(range: year, granularity: granularityFor(year)),
        ).overrideWithValue(
          const AsyncData<List<PeriodSeriesPoint>>(<PeriodSeriesPoint>[]),
        ),
        monthlyHistoryProvider(month).overrideWithValue(
          const AsyncData<List<MonthlyHistory>>(<MonthlyHistory>[]),
        ),
        monthlyHistoryProvider(year).overrideWithValue(
          const AsyncData<List<MonthlyHistory>>(<MonthlyHistory>[]),
        ),
        reportAccountBalancesProvider.overrideWithValue(
          const AsyncData<List<ReportAccountBalance>>(<ReportAccountBalance>[]),
        ),
      ];

      await tester.binding.setSurfaceSize(const Size(1000, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: ReportsPage()),
        ),
      );
      await tester.pump();

      // Income grew, expenses fell, so both are shown as a percentage.
      expect(find.text('+25%'), findsOneWidget);
      expect(find.text('−50%'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tahun ini'));
      await tester.pumpAndSettle();

      expect(find.text('Belum ada pembanding'), findsNWidgets(3));
      expect(find.text('Tren periode'), findsOneWidget);
    },
  );
}
