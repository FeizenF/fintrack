import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/tab_page_header.dart';
import '../../../shared/providers/database_providers.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  TransactionType? _filter;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FinancialTransaction>> value = ref.watch(
      filteredTransactionsProvider(_filter),
    );
    final AsyncValue<List<Account>> accounts = ref.watch(accountsProvider);
    final Map<int, String> names = <int, String>{
      for (final Account account in accounts.value ?? const <Account>[])
        account.id: account.name,
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
                hintText: 'Cari catatan atau kategori',
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
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
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
                  if (_query.isEmpty) return true;
                  final String searchable =
                      '${row.note ?? ''} ${row.categoryId ?? ''}'.toLowerCase();
                  return searchable.contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: rows.isEmpty
                        ? 'Belum ada transaksi'
                        : 'Tidak ada hasil',
                    message: rows.isEmpty
                        ? 'Catat pemasukan, pengeluaran, atau transfer pertama.'
                        : 'Coba kata kunci atau filter lain.',
                    action: rows.isEmpty
                        ? FilledButton.icon(
                            onPressed: () =>
                                context.push(AppRoutes.transactionNew),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Catat transaksi'),
                          )
                        : null,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxl * 3,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (BuildContext context, int index) =>
                      _TransactionTile(
                        transaction: filtered[index],
                        accountName: names[filtered[index].accountId] ?? 'Akun',
                        destinationName:
                            names[filtered[index].toAccountId] ?? 'Akun tujuan',
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
