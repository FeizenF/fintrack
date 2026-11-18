import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repositories/summary_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/report_series.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/tab_page_header.dart';
import '../../../shared/providers/database_providers.dart';

/// Financial reports: period trend, period-over-period comparison, category
/// breakdown, monthly history and per-account balances.
///
/// Every figure is a SQL aggregate over the ledger for the selected
/// [DateRange], so a report can never disagree with the transaction list.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  PeriodFilter _filter = PeriodFilter.thisMonth;
  DateRange? _customRange;

  DateRange get _range => _filter.resolve(customRange: _customRange);

  @override
  Widget build(BuildContext context) {
    final DateRange range = _range;
    final DateRange previous = previousReportRange(range, _filter);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(summaryTotalsProvider);
            ref.invalidate(expenseByCategoryRangeProvider);
            ref.invalidate(periodSeriesProvider);
            ref.invalidate(monthlyHistoryProvider);
            ref.invalidate(reportAccountBalancesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 3),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              const TabPageHeader(
                title: 'Laporan',
                subtitle: 'Pemasukan dan pengeluaran',
              ),
              _PeriodSelector(
                filter: _filter,
                range: range,
                onChanged: _selectFilter,
                onPickRange: _pickCustomRange,
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _TrendCard(
                  range: range,
                  series: ref.watch(
                    periodSeriesProvider(
                      ReportSeriesRequest(
                        range: range,
                        granularity: granularityFor(range),
                      ),
                    ),
                  ),
                  totals: ref.watch(summaryTotalsProvider(range)),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _ComparisonCard(
                  current: ref.watch(summaryTotalsProvider(range)),
                  previous: ref.watch(summaryTotalsProvider(previous)),
                  previousRange: previous,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _CategoryCard(
                  categories: ref.watch(expenseByCategoryRangeProvider(range)),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _HistoryCard(
                  history: ref.watch(monthlyHistoryProvider(range)),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _AccountsCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectFilter(PeriodFilter filter) {
    setState(() {
      _filter = filter;
      if (filter != PeriodFilter.custom) _customRange = null;
    });
    if (filter == PeriodFilter.custom) _pickCustomRange();
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialDateRange: _customRange == null
          ? null
          : DateTimeRange(
              start: _customRange!.start,
              end: _customRange!.end.subtract(const Duration(days: 1)),
            ),
    );
    if (picked == null) {
      if (mounted && _customRange == null) {
        setState(() => _filter = PeriodFilter.thisMonth);
      }
      return;
    }
    setState(() {
      _filter = PeriodFilter.custom;
      _customRange = DateRange.inclusive(picked.start, picked.end);
    });
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.filter,
    required this.range,
    required this.onChanged,
    required this.onPickRange,
  });

  final PeriodFilter filter;
  final DateRange range;
  final ValueChanged<PeriodFilter> onChanged;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: <Widget>[
              for (final PeriodFilter option in PeriodFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: filter == option,
                    onSelected: (_) => option == PeriodFilter.custom
                        ? onPickRange()
                        : onChanged(option),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.sm,
          ),
          child: Text(
            _rangeLabel(range),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _rangeLabel(DateRange range) {
    final DateTime last = range.end.subtract(const Duration(days: 1));
    return '${Formatters.fullDate(range.start)} – ${Formatters.fullDate(last)}';
  }
}

/// Income and expense trend for the selected period.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.range,
    required this.series,
    required this.totals,
  });

  final DateRange range;
  final AsyncValue<List<PeriodSeriesPoint>> series;
  final AsyncValue<MonthlyTotals> totals;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Tren periode'),
          series.when(
            loading: () =>
                const LoadingState(message: 'Memuat grafik periode...'),
            error: (Object error, StackTrace stack) => const ErrorStateView(
              message: 'Grafik periode gagal dimuat.',
              compact: true,
            ),
            data: (List<PeriodSeriesPoint> points) {
              final ReportGranularity granularity = granularityFor(range);
              final List<PeriodSeriesPoint> filled = completeSeries(
                range: range,
                granularity: granularity,
                points: points,
              );
              if (filled.every(
                (PeriodSeriesPoint p) => p.income == 0 && p.expense == 0,
              )) {
                return const EmptyState(
                  icon: Icons.show_chart_rounded,
                  title: 'Belum ada transaksi',
                  message:
                      'Grafik muncul setelah ada pemasukan atau pengeluaran.',
                  compact: true,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _TrendChart(points: filled, granularity: granularity),
                  const SizedBox(height: AppSpacing.md),
                  _Legend(
                    entries: <({String label, Color color})>[
                      (
                        label: 'Pemasukan',
                        color: AppColors.incomeOf(Theme.of(context).brightness),
                      ),
                      (
                        label: 'Pengeluaran',
                        color: AppColors.expenseOf(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  totals.when(
                    loading: () => const SizedBox(
                      height: 20,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    ),
                    error: (Object error, StackTrace stack) => Text(
                      'Total periode tidak tersedia.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    data: (MonthlyTotals value) => Row(
                      children: <Widget>[
                        Expanded(
                          child: _Metric(
                            label: 'Pemasukan',
                            value: Formatters.currency(value.income),
                            color: AppColors.incomeOf(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: 'Pengeluaran',
                            value: Formatters.currency(value.expense),
                            color: AppColors.expenseOf(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: 'Selisih',
                            value: Formatters.currency(value.net),
                            color: value.net < 0
                                ? AppColors.expenseOf(
                                    Theme.of(context).brightness,
                                  )
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.granularity});

  final List<PeriodSeriesPoint> points;
  final ReportGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final ThemeData theme = Theme.of(context);
    final int highest = points.fold<int>(
      0,
      (int max, PeriodSeriesPoint point) => <int>[
        max,
        point.income,
        point.expense,
      ].reduce((int a, int b) => a > b ? a : b),
    );
    final double maxY = highest <= 0 ? 1 : highest * 1.15;
    final int labelStep = (points.length / 4).ceil().clamp(1, points.length);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (double value) =>
                FlLine(color: AppColors.borderOf(brightness), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: maxY / 4,
                getTitlesWidget: (double value, TitleMeta meta) => Text(
                  Formatters.compactCurrency(value.round()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedTextOf(brightness),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (index % labelStep != 0 && index != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _bucketLabel(points[index].bucket, granularity),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedTextOf(brightness),
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: <LineChartBarData>[
            _line(
              points.map((PeriodSeriesPoint p) => p.income).toList(),
              AppColors.incomeOf(brightness),
            ),
            _line(
              points.map((PeriodSeriesPoint p) => p.expense).toList(),
              AppColors.expenseOf(brightness),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }

  static String _bucketLabel(DateTime bucket, ReportGranularity granularity) =>
      switch (granularity) {
        ReportGranularity.day => '${bucket.day}',
        ReportGranularity.month => Formatters.dayMonth(bucket),
      };

  static LineChartBarData _line(List<int> values, Color color) =>
      LineChartBarData(
        spots: <FlSpot>[
          for (int i = 0; i < values.length; i++)
            FlSpot(i.toDouble(), values[i].toDouble()),
        ],
        isCurved: false,
        color: color,
        barWidth: 2.4,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withValues(alpha: 0.12),
        ),
      );
}

/// Current period against the matching preceding period.
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.current,
    required this.previous,
    required this.previousRange,
  });

  final AsyncValue<MonthlyTotals> current;
  final AsyncValue<MonthlyTotals> previous;
  final DateRange previousRange;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final MonthlyTotals? now = current.value;
    final MonthlyTotals? before = previous.value;
    final bool ready = now != null && before != null;
    final String previousLabel =
        '${Formatters.fullDate(previousRange.start)} – '
        '${Formatters.fullDate(previousRange.end.subtract(const Duration(days: 1)))}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Perubahan dari periode sebelumnya'),
          Text(
            previousLabel,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.mutedTextOf(brightness)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (current.hasError || previous.hasError)
            const ErrorStateView(
              message: 'Perbandingan periode gagal dimuat.',
              compact: true,
            )
          else if (!ready)
            const LoadingState(message: 'Memuat perbandingan...')
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _ChangeMetric(
                    label: 'Pemasukan',
                    currentValue: now.income,
                    change: percentChange(
                      current: now.income,
                      previous: before.income,
                    ),
                    positiveIsGood: true,
                  ),
                ),
                Expanded(
                  child: _ChangeMetric(
                    label: 'Pengeluaran',
                    currentValue: now.expense,
                    change: percentChange(
                      current: now.expense,
                      previous: before.expense,
                    ),
                    positiveIsGood: false,
                  ),
                ),
                Expanded(
                  child: _ChangeMetric(
                    label: 'Selisih',
                    currentValue: now.net,
                    change: percentChange(
                      current: now.net,
                      previous: before.net,
                    ),
                    positiveIsGood: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _compareMaxY(now, before),
                  minY: 0,
                  barTouchData: BarTouchData(enabled: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: <BarChartGroupData>[
                    _group(
                      0,
                      left: before.income.toDouble(),
                      right: now.income.toDouble(),
                      leftColor: AppColors.incomeOf(brightness)
                          .withValues(alpha: 0.35),
                      rightColor: AppColors.incomeOf(brightness),
                    ),
                    _group(
                      1,
                      left: before.expense.toDouble(),
                      right: now.expense.toDouble(),
                      leftColor: AppColors.expenseOf(brightness)
                          .withValues(alpha: 0.35),
                      rightColor: AppColors.expenseOf(brightness),
                    ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Legend(
              entries: <({String label, Color color})>[
                (
                  label: 'Periode sebelumnya',
                  color: AppColors.mutedTextOf(brightness)
                      .withValues(alpha: 0.45),
                ),
                (
                  label: 'Periode ini',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static double _compareMaxY(MonthlyTotals now, MonthlyTotals before) {
    final int highest = <int>[
      now.income,
      now.expense,
      before.income,
      before.expense,
    ].reduce((int a, int b) => a > b ? a : b);
    return highest <= 0 ? 1 : highest * 1.2;
  }

  static BarChartGroupData _group(
    int x, {
    required double left,
    required double right,
    required Color leftColor,
    required Color rightColor,
  }) {
    return BarChartGroupData(
      x: x,
      barsSpace: 6,
      barRods: <BarChartRodData>[
        BarChartRodData(
          toY: left,
          color: leftColor,
          width: 18,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        BarChartRodData(
          toY: right,
          color: rightColor,
          width: 18,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ],
    );
  }
}

class _ChangeMetric extends StatelessWidget {
  const _ChangeMetric({
    required this.label,
    required this.currentValue,
    required this.change,
    required this.positiveIsGood,
  });

  final String label;
  final int currentValue;
  final double? change;
  final bool positiveIsGood;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final double? value = change;
    final bool good = value == null
        ? true
        : positiveIsGood
        ? value >= 0
        : value <= 0;
    final Color color = value == null
        ? AppColors.mutedTextOf(brightness)
        : good
        ? AppColors.incomeOf(brightness)
        : AppColors.expenseOf(brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.mutedTextOf(brightness),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Formatters.currency(currentValue),
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value == null
              ? 'Belum ada pembanding'
              : '${value > 0
                        ? '+'
                        : value < 0
                        ? '−'
                        : ''}'
                    '${Formatters.percent(value.abs())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Expense share per category with a pie chart.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.categories});

  final AsyncValue<List<CategoryAmount>> categories;

  static const List<Color> _palette = <Color>[
    Color(0xFFC0392B),
    Color(0xFFB7791F),
    Color(0xFF2C6E9B),
    Color(0xFF12855A),
    Color(0xFF7A4EAB),
    Color(0xFF5B6472),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Pengeluaran per kategori'),
          categories.when(
            loading: () => const LoadingState(message: 'Memuat kategori...'),
            error: (Object error, StackTrace stack) => const ErrorStateView(
              message: 'Rincian kategori gagal dimuat.',
              compact: true,
            ),
            data: (List<CategoryAmount> rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Belum ada pengeluaran',
                  message: 'Catat pengeluaran untuk melihat rincian kategori.',
                  compact: true,
                );
              }
              final int total = rows.fold<int>(
                0,
                (int sum, CategoryAmount row) => sum + row.amount,
              );
              final List<CategoryAmount> top = rows
                  .take(5)
                  .toList(growable: false);
              final int rest = rows.length > 5
                  ? rows
                        .skip(5)
                        .fold<int>(
                          0,
                          (int sum, CategoryAmount row) => sum + row.amount,
                        )
                  : 0;
              final List<({String name, int amount, Color color})> slices =
                  <({String name, int amount, Color color})>[
                    for (int i = 0; i < top.length; i++)
                      (
                        name: top[i].name,
                        amount: top[i].amount,
                        color: _palette[i % _palette.length],
                      ),
                    if (rest > 0)
                      (
                        name: 'Kategori lain',
                        amount: rest,
                        color: _palette.last,
                      ),
                  ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
                        sections: <PieChartSectionData>[
                          for (final ({String name, int amount, Color color})
                              slice
                              in slices)
                            PieChartSectionData(
                              value: slice.amount.toDouble(),
                              color: slice.color,
                              radius: 46,
                              showTitle: false,
                            ),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final ({String name, int amount, Color color}) slice
                      in slices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: slice.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(slice.name)),
                          Text(Formatters.currency(slice.amount)),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 48,
                            child: Text(
                              Formatters.percent(
                                total == 0 ? 0 : slice.amount / total * 100,
                              ),
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.mutedTextOf(
                                      Theme.of(context).brightness,
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Month-by-month income/expense recap for the selected period.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final AsyncValue<List<MonthlyHistory>> history;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Riwayat bulanan'),
          history.when(
            loading: () => const LoadingState(message: 'Memuat riwayat...'),
            error: (Object error, StackTrace stack) => const ErrorStateView(
              message: 'Riwayat bulanan gagal dimuat.',
              compact: true,
            ),
            data: (List<MonthlyHistory> rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'Belum ada riwayat',
                  message:
                      'Riwayat muncul setelah ada transaksi pada periode ini.',
                  compact: true,
                );
              }
              return Column(
                children: <Widget>[
                  for (final MonthlyHistory row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  Formatters.monthYear(row.month),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                row.net < 0
                                    ? Formatters.currency(row.net)
                                    : Formatters.signedCurrency(row.net),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: row.net < 0
                                      ? AppColors.expenseOf(brightness)
                                      : AppColors.incomeOf(brightness),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Masuk ${Formatters.currency(row.income)} · '
                            'Keluar ${Formatters.currency(row.expense)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.mutedTextOf(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Current balance per account, derived from the ledger.
class _AccountsCard extends ConsumerWidget {
  const _AccountsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ReportAccountBalance>> balances = ref.watch(
      reportAccountBalancesProvider,
    );
    final int total =
        balances.value?.fold<int>(
          0,
          (int sum, ReportAccountBalance row) => sum + row.balance,
        ) ??
        0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Ringkasan akun',
            subtitle: Formatters.currency(total),
          ),
          balances.when(
            loading: () => const LoadingState(message: 'Memuat akun...'),
            error: (Object error, StackTrace stack) => ErrorStateView(
              message: 'Ringkasan akun gagal dimuat.',
              compact: true,
              onRetry: () => ref.invalidate(reportAccountBalancesProvider),
            ),
            data: (List<ReportAccountBalance> rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Belum ada akun',
                  message: 'Tambahkan akun di halaman Pengaturan.',
                  compact: true,
                );
              }
              return Column(
                children: <Widget>[
                  for (final ReportAccountBalance row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(row.name),
                                Text(
                                  row.isArchived
                                      ? '${row.type.label} · Diarsipkan'
                                      : row.type.label,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.mutedTextOf(
                                          Theme.of(context).brightness,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Formatters.currency(row.balance),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<({String label, Color color})> entries;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final ({String label, Color color}) entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: entry.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                entry.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
