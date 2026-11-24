import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/account_balances.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/budgets_repository.dart';
import '../../../core/database/repositories/savings_repository.dart';
import '../../../core/database/repositories/summary_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/cash_flow_summary.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/tab_page_header.dart';
import '../../../shared/providers/database_providers.dart';

/// Home screen: wallet balance, period totals, budget and savings progress plus
/// the newest ledger rows.
///
/// The wallet balance is cumulative (`AccountBalanceCalculator`), while income,
/// expense and net follow the selected [DateRange]. Both are ledger sums, so the
/// dashboard can never disagree with the transaction list.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  PeriodFilter _filter = PeriodFilter.thisMonth;
  DateRange? _customRange;
  bool _savingPreference = false;

  DateRange get _range => _filter.resolve(customRange: _customRange);

  @override
  Widget build(BuildContext context) {
    final bool hidden = ref.watch(hideBalancesProvider).value ?? false;
    final AsyncValue<WalletBalance> wallet = ref.watch(walletBalanceProvider);
    final AsyncValue<MonthlyTotals> totals = ref.watch(
      summaryTotalsProvider(_range),
    );
    final AsyncValue<List<CategoryAmount>> categories = ref.watch(
      expenseByCategoryRangeProvider(_range),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(walletBalanceProvider);
            ref.invalidate(summaryTotalsProvider);
            ref.invalidate(expenseByCategoryRangeProvider);
            ref.invalidate(budgetProgressProvider);
            ref.invalidate(savingsProgressProvider);
            ref.invalidate(recentTransactionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 4),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              TabPageHeader(
                title: 'FinTrack',
                subtitle: 'Ringkasan keuangan kamu',
                trailing: IconButton(
                  tooltip: hidden ? 'Tampilkan saldo' : 'Sembunyikan saldo',
                  onPressed: _savingPreference
                      ? null
                      : () => _toggleHidden(hidden),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              _PeriodSelector(
                filter: _filter,
                range: _range,
                onChanged: _selectFilter,
                onPickRange: _pickCustomRange,
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _WalletCard(wallet: wallet, hidden: hidden),
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _TotalsCard(
                  totals: totals,
                  categories: categories,
                  hidden: hidden,
                  range: _range,
                  onRetry: () {
                    ref.invalidate(summaryTotalsProvider);
                    ref.invalidate(expenseByCategoryRangeProvider);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _BudgetSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _SavingsSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SectionHeader(
                  title: 'Transaksi terbaru',
                  subtitle: 'Lima catatan terakhir',
                  action: TextButton(
                    onPressed: () => context.go(AppRoutes.transactions),
                    child: const Text('Lihat semua'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _RecentSection(),
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

  Future<void> _toggleHidden(bool hidden) async {
    setState(() => _savingPreference = true);
    try {
      await setHideBalances(ref, !hidden);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferensi saldo gagal disimpan.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPreference = false);
    }
  }
}

/// Masked placeholder that keeps layout width stable while amounts are hidden.
String _amount(int value, bool hidden) =>
    hidden ? '••••••' : Formatters.currency(value);

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

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet, required this.hidden});

  final AsyncValue<WalletBalance> wallet;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int accounts = wallet.value?.accounts.length ?? 0;
    return AppCard(
      backgroundColor: AppColors.navy,
      borderColor: AppColors.navyDeep,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Saldo dompet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.goldSoft,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          wallet.when(
            loading: () => const SizedBox(
              height: 34,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
            error: (Object error, StackTrace stack) => Text(
              'Saldo tidak tersedia',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            data: (WalletBalance value) => Text(
              _amount(value.total, hidden),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            accounts == 0
                ? 'Belum ada akun. Tambahkan akun di Pengaturan.'
                : '$accounts akun aktif',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.totals,
    required this.categories,
    required this.hidden,
    required this.range,
    required this.onRetry,
  });

  final AsyncValue<MonthlyTotals> totals;
  final AsyncValue<List<CategoryAmount>> categories;
  final bool hidden;
  final DateRange range;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return totals.when(
      loading: () =>
          const AppCard(child: LoadingState(message: 'Memuat ringkasan...')),
      error: (Object error, StackTrace stack) => AppCard(
        child: ErrorStateView(
          message: 'Ringkasan gagal dimuat.',
          onRetry: onRetry,
        ),
      ),
      data: (MonthlyTotals value) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CashFlowSummary(
                income: value.income,
                expense: value.expense,
                hidden: hidden,
              ),
              if (!value.isEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                _CategoryBreakdown(categories: categories, hidden: hidden),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.categories, required this.hidden});

  final AsyncValue<List<CategoryAmount>> categories;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return categories.when(
      loading: () => const SizedBox(
        height: 24,
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
        'Rincian kategori tidak tersedia.',
        style: theme.textTheme.bodySmall,
      ),
      data: (List<CategoryAmount> rows) {
        if (rows.isEmpty) {
          return Text(
            'Belum ada pengeluaran pada periode ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        final int total = rows.fold<int>(
          0,
          (int sum, CategoryAmount row) => sum + row.amount,
        );
        final List<CategoryAmount> top = rows.take(4).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionTitle('Pengeluaran per kategori'),
            const SizedBox(height: AppSpacing.sm),
            for (final CategoryAmount row in top)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(row.name)),
                        Text(_amount(row.amount, hidden)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : row.amount / total,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BudgetSection extends ConsumerWidget {
  const _BudgetSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Normalised to the first day of the month: the family key must stay equal
    // across rebuilds, otherwise every frame would subscribe to a fresh stream.
    final DateTime now = DateTime.now();
    final DateTime month = DateTime(now.year, now.month);
    final AsyncValue<List<BudgetProgress>> value = ref.watch(
      budgetProgressProvider(month),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'Anggaran bulan ini',
          action: TextButton(
            onPressed: () => context.go(AppRoutes.budgets),
            child: const Text('Kelola'),
          ),
        ),
        value.when(
          loading: () => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Memuat anggaran...'),
            ),
          ),
          error: (Object error, StackTrace stack) => AppCard(
            child: ErrorStateView(
              message: 'Anggaran gagal dimuat.',
              compact: true,
              onRetry: () => ref.invalidate(budgetProgressProvider(month)),
            ),
          ),
          data: (List<BudgetProgress> rows) {
            if (rows.isEmpty) {
              return AppCard(
                child: EmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Belum ada anggaran',
                  message: 'Atur batas pengeluaran per kategori.',
                  compact: true,
                  action: TextButton(
                    onPressed: () => context.go(AppRoutes.budgets),
                    child: const Text('Buat anggaran'),
                  ),
                ),
              );
            }
            final List<BudgetProgress> top = rows
                .take(3)
                .toList(growable: false);
            return AppCard(
              child: Column(
                children: <Widget>[
                  for (final BudgetProgress progress in top)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _MiniProgress(
                        title: progress.categoryName,
                        detail:
                            '${Formatters.currency(progress.spent)} / ${Formatters.currency(progress.limit)}',
                        ratio: progress.ratio,
                        warning: progress.isNearLimit || progress.isExceeded,
                        exceeded: progress.isExceeded,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SavingsSection extends ConsumerWidget {
  const _SavingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SavingsProgress>> value = ref.watch(
      savingsProgressProvider,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'Target tabungan',
          action: TextButton(
            onPressed: () => context.push(AppRoutes.savings),
            child: const Text('Kelola'),
          ),
        ),
        value.when(
          loading: () => const AppCard(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Memuat target tabungan...'),
            ),
          ),
          error: (Object error, StackTrace stack) => AppCard(
            child: ErrorStateView(
              message: 'Target tabungan gagal dimuat.',
              compact: true,
              onRetry: () => ref.invalidate(savingsProgressProvider),
            ),
          ),
          data: (List<SavingsProgress> rows) {
            if (rows.isEmpty) {
              return AppCard(
                child: EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'Belum ada target',
                  message: 'Buat target untuk mulai menyisihkan dana.',
                  compact: true,
                  action: TextButton(
                    onPressed: () => context.push(AppRoutes.savings),
                    child: const Text('Buat target'),
                  ),
                ),
              );
            }
            return AppCard(
              child: Column(
                children: <Widget>[
                  for (final SavingsProgress progress in rows.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _MiniProgress(
                        title: progress.goal.name,
                        detail:
                            '${Formatters.currency(progress.saved)} / ${Formatters.currency(progress.target)}',
                        ratio: progress.ratio,
                        warning: false,
                        exceeded: false,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({
    required this.title,
    required this.detail,
    required this.ratio,
    required this.warning,
    required this.exceeded,
  });

  final String title;
  final String detail;
  final double ratio;
  final bool warning;
  final bool exceeded;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color color = exceeded
        ? AppColors.expenseOf(brightness)
        : warning
        ? AppColors.warningOf(brightness)
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(title)),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          minHeight: 6,
          color: color,
          backgroundColor: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FinancialTransaction>> value = ref.watch(
      recentTransactionsProvider,
    );
    final List<Account> accounts =
        ref.watch(accountsProvider).value ?? const <Account>[];
    final Map<int, String> accountNames = <int, String>{
      for (final Account account in accounts) account.id: account.name,
    };
    final Map<int, String> categoryNames = <int, String>{
      for (final Category category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category.name,
    };

    return value.when(
      loading: () =>
          const AppCard(child: LoadingState(message: 'Memuat transaksi...')),
      error: (Object error, StackTrace stack) => AppCard(
        child: ErrorStateView(
          message: 'Transaksi gagal dimuat.',
          compact: true,
          onRetry: () => ref.invalidate(recentTransactionsProvider),
        ),
      ),
      data: (List<FinancialTransaction> rows) {
        if (rows.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Belum ada transaksi',
              message: 'Catat pemasukan atau pengeluaran pertama.',
              compact: true,
              action: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.transactionNew),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Catat transaksi'),
              ),
            ),
          );
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (final FinancialTransaction row in rows)
                ListTile(
                  onTap: () =>
                      context.push(AppRoutes.transactionDetail(row.id)),
                  leading: Icon(
                    switch (row.type) {
                      TransactionType.income => Icons.south_west_rounded,
                      TransactionType.expense => Icons.north_east_rounded,
                      TransactionType.transfer => Icons.swap_horiz_rounded,
                    },
                    color: switch (row.type) {
                      TransactionType.income => AppColors.incomeOf(
                        Theme.of(context).brightness,
                      ),
                      TransactionType.expense => AppColors.expenseOf(
                        Theme.of(context).brightness,
                      ),
                      TransactionType.transfer => Theme.of(
                        context,
                      ).colorScheme.primary,
                    },
                  ),
                  title: Text(
                    row.categoryId == null
                        ? row.type.label
                        : categoryNames[row.categoryId] ?? row.type.label,
                  ),
                  subtitle: Text(
                    row.type == TransactionType.transfer
                        ? '${accountNames[row.accountId] ?? 'Akun'} → '
                              '${accountNames[row.toAccountId] ?? 'Akun'}'
                        : accountNames[row.accountId] ?? 'Akun',
                  ),
                  trailing: Text(switch (row.type) {
                    TransactionType.income =>
                      '+${Formatters.currency(row.amount)}',
                    TransactionType.expense =>
                      '−${Formatters.currency(row.amount)}',
                    TransactionType.transfer => Formatters.currency(row.amount),
                  }, style: Theme.of(context).textTheme.labelLarge),
                ),
            ],
          ),
        );
      },
    );
  }
}
