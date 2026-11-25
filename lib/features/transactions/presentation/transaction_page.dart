import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/transaction_groups.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/tab_page_header.dart';
import '../../../shared/providers/database_providers.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  TransactionType? _filter;
  int? _accountFilter;
  TransactionGrouping _grouping = TransactionGrouping.month;
  final Set<String> _collapsed = <String>{};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleGroup(String key) {
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FinancialTransaction>> value = ref.watch(
      filteredTransactionsProvider(_filter),
    );
    final AsyncValue<List<Account>> accounts = ref.watch(accountsProvider);
    final AsyncValue<List<Category>> categories = ref.watch(categoriesProvider);
    final Map<int, String> accountNames = <int, String>{
      for (final Account account in accounts.value ?? const <Account>[])
        account.id: account.name,
    };
    final Map<int, String> categoryNames = <int, String>{
      for (final Category category in categories.value ?? const <Category>[])
        category.id: category.name,
    };

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabPageHeader(
            title: 'Transaksi',
            subtitle: 'Riwayat pemasukan, pengeluaran dan transfer',
            trailing: IconButton(
              tooltip: 'Tambah transaksi',
              onPressed: () => context.push(AppRoutes.transactionNew),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _search,
              onChanged: (String value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Cari catatan, kategori, atau akun',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ChipRow(
            children: <Widget>[
              _FilterChip(
                label: 'Semua',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final TransactionType type in TransactionType.values)
                _FilterChip(
                  label: type.label,
                  selected: _filter == type,
                  onTap: () => setState(() => _filter = type),
                ),
            ],
          ),
          if ((accounts.value?.length ?? 0) > 1)
            _ChipRow(
              children: <Widget>[
                _FilterChip(
                  label: 'Semua akun',
                  selected: _accountFilter == null,
                  onTap: () => setState(() => _accountFilter = null),
                ),
                for (final Account account
                    in accounts.value ?? const <Account>[])
                  _FilterChip(
                    label: account.name,
                    selected: _accountFilter == account.id,
                    onTap: () => setState(() => _accountFilter = account.id),
                  ),
              ],
            ),
          _ChipRow(
            children: <Widget>[
              for (final TransactionGrouping grouping
                  in TransactionGrouping.values)
                _FilterChip(
                  label: 'Per ${grouping.label.toLowerCase()}',
                  selected: _grouping == grouping,
                  onTap: () => setState(() => _grouping = grouping),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: value.when(
              loading: () => const LoadingState(message: 'Memuat transaksi...'),
              error: (Object error, StackTrace stack) => ErrorStateView(
                message: 'Transaksi gagal dimuat.',
                onRetry: () =>
                    ref.invalidate(filteredTransactionsProvider(_filter)),
              ),
              data: (List<FinancialTransaction> rows) {
                final List<FinancialTransaction> filtered = rows.where((row) {
                  if (_accountFilter != null &&
                      row.accountId != _accountFilter &&
                      row.toAccountId != _accountFilter) {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  final String searchable = <String>[
                    row.note ?? '',
                    categoryNames[row.categoryId] ?? '',
                    accountNames[row.accountId] ?? '',
                    accountNames[row.toAccountId] ?? '',
                    row.type.label,
                  ].join(' ').toLowerCase();
                  return searchable.contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  final bool emptyLedger =
                      rows.isEmpty &&
                      _query.isEmpty &&
                      _accountFilter == null &&
                      _filter == null;
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: emptyLedger
                        ? 'Belum ada transaksi'
                        : 'Tidak ada hasil',
                    message: emptyLedger
                        ? 'Catat pemasukan, pengeluaran, atau transfer pertama.'
                        : 'Coba kata kunci atau filter lain.',
                    action: emptyLedger
                        ? FilledButton.icon(
                            onPressed: () =>
                                context.push(AppRoutes.transactionNew),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Catat transaksi'),
                          )
                        : null,
                  );
                }
                final List<TransactionGroup> groups = groupTransactions(
                  filtered,
                  _grouping,
                );
                // While searching, keep every group open so no match can hide
                // behind a collapsed header.
                final bool forceOpen = _query.isNotEmpty;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxl * 4,
                  ),
                  children: <Widget>[
                    for (final TransactionGroup group in groups)
                      _GroupSection(
                        group: group,
                        grouping: _grouping,
                        collapsed:
                            !forceOpen && _collapsed.contains(group.key),
                        onToggle: () => _toggleGroup(group.key),
                        accountNames: accountNames,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One bucket header plus its transaction cards.
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.grouping,
    required this.collapsed,
    required this.onToggle,
    required this.accountNames,
  });

  final TransactionGroup group;
  final TransactionGrouping grouping;
  final bool collapsed;
  final VoidCallback onToggle;
  final Map<int, String> accountNames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _GroupHeader(
          group: group,
          grouping: grouping,
          collapsed: collapsed,
          onToggle: onToggle,
        ),
        if (!collapsed)
          for (final FinancialTransaction row in group.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TransactionTile(
                transaction: row,
                accountName: accountNames[row.accountId] ?? 'Akun',
                destinationName:
                    accountNames[row.toAccountId] ?? 'Akun tujuan',
              ),
            ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Sticky-looking header showing the bucket label and its totals.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.grouping,
    required this.collapsed,
    required this.onToggle,
  });

  final TransactionGroup group;
  final TransactionGrouping grouping;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final Color incomeColor = AppColors.incomeOf(brightness);
    final Color expenseColor = AppColors.expenseOf(brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: AppRadius.smallAll,
        child: InkWell(
          onTap: onToggle,
          borderRadius: AppRadius.smallAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SectionTitle(
                        transactionGroupLabel(group, grouping),
                      ),
                    ),
                    Text(
                      '${group.count} transaksi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    _TotalChip(
                      icon: Icons.south_west_rounded,
                      label: Formatters.currency(group.income),
                      color: incomeColor,
                    ),
                    _TotalChip(
                      icon: Icons.north_east_rounded,
                      label: Formatters.currency(group.expense),
                      color: expenseColor,
                    ),
                    if (group.transfer > 0)
                      _TotalChip(
                        icon: Icons.swap_horiz_rounded,
                        label: Formatters.currency(group.transfer),
                        color: theme.colorScheme.primary,
                      ),
                    _TotalChip(
                      icon: group.net >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      label: '${group.net >= 0 ? '+' : '−'}'
                          '${Formatters.currency(group.net.abs())}',
                      color: group.net >= 0
                          ? theme.colorScheme.primary
                          : expenseColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Row(children: children),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.sm),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      // Compact density keeps the three chip rows from eating the list area.
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.transaction,
    required this.accountName,
    required this.destinationName,
  });

  final FinancialTransaction transaction;
  final String accountName;
  final String destinationName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Category?> category = transaction.categoryId == null
        ? const AsyncValue<Category?>.data(null)
        : ref.watch(categoryByIdProvider(transaction.categoryId!));
    final Color tint = switch (transaction.type) {
      TransactionType.income => AppColors.incomeOf(
        Theme.of(context).brightness,
      ),
      TransactionType.expense => AppColors.expenseOf(
        Theme.of(context).brightness,
      ),
      TransactionType.transfer => Theme.of(context).colorScheme.primary,
    };
    final String sign = switch (transaction.type) {
      TransactionType.income => '+',
      TransactionType.expense => '−',
      TransactionType.transfer => '',
    };
    final String accountLine = transaction.type == TransactionType.transfer
        ? '$accountName  →  $destinationName'
        : accountName;

    return Card(
      child: ListTile(
        onTap: () => context.push(AppRoutes.transactionDetail(transaction.id)),
        leading: CircleAvatar(
          backgroundColor: tint.withValues(alpha: 0.12),
          foregroundColor: tint,
          child: Icon(switch (transaction.type) {
            TransactionType.income => Icons.south_west_rounded,
            TransactionType.expense => Icons.north_east_rounded,
            TransactionType.transfer => Icons.swap_horiz_rounded,
          }),
        ),
        title: Text(category.asData?.value?.name ?? transaction.type.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(accountLine),
            Text(
              transaction.note ??
                  Formatters.relativeDay(transaction.transactionDate),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Text(
          '$sign${Formatters.currency(transaction.amount)}',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: tint, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
