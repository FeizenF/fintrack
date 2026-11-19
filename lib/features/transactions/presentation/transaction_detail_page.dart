import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/transactions_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({super.key, required this.transactionId});

  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FinancialTransaction?> value = ref.watch(
      transactionByIdProvider(transactionId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Transaksi')),
      body: value.when(
        loading: () => const LoadingState(message: 'Memuat transaksi...'),
        error: (Object error, StackTrace stack) =>
            const ErrorStateView(message: 'Detail transaksi gagal dimuat.'),
        data: (FinancialTransaction? transaction) {
          if (transaction == null) {
            return const ErrorStateView(message: 'Transaksi tidak ditemukan.');
          }
          return _TransactionDetail(transaction: transaction);
        },
      ),
      bottomNavigationBar: value.asData?.value == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        AppRoutes.transactionEdit(transactionId),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Ubah'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _confirmDelete(context, ref),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Hapus'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Hapus transaksi?'),
            content: const Text('Tindakan ini tidak dapat dibatalkan.'),
            actions: <Widget>[
              DialogActions(
                onCancel: () => Navigator.pop(context, false),
                onConfirm: () => Navigator.pop(context, true),
                confirmLabel: 'Hapus',
                destructive: true,
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      final TransactionsRepository repository = await ref.read(
        transactionsRepositoryProvider.future,
      );
      await repository.delete(transactionId);
      ref.invalidate(transactionsProvider);
      if (context.mounted) context.pop();
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is AppException
                  ? error.message
                  : 'Transaksi gagal dihapus. Silakan coba lagi.',
            ),
          ),
        );
      }
    }
  }
}

class _TransactionDetail extends ConsumerWidget {
  const _TransactionDetail({required this.transaction});

  final FinancialTransaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Account?> account = ref.watch(
      accountByIdProvider(transaction.accountId),
    );
    final int? toAccountId = transaction.toAccountId;
    final AsyncValue<Account?>? destination = toAccountId == null
        ? null
        : ref.watch(accountByIdProvider(toAccountId));
    final int? categoryId = transaction.categoryId;
    final AsyncValue<Category?>? category = categoryId == null
        ? null
        : ref.watch(categoryByIdProvider(categoryId));
    final Color tint = switch (transaction.type) {
      TransactionType.income => AppColors.incomeOf(
        Theme.of(context).brightness,
      ),
      TransactionType.expense => AppColors.expenseOf(
        Theme.of(context).brightness,
      ),
      TransactionType.transfer => Theme.of(context).colorScheme.primary,
    };
    final String sign = transaction.type == TransactionType.income
        ? '+'
        : transaction.type == TransactionType.expense
        ? '−'
        : '';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 30,
                  backgroundColor: tint.withValues(alpha: 0.12),
                  foregroundColor: tint,
                  child: Icon(switch (transaction.type) {
                    TransactionType.income => Icons.south_west_rounded,
                    TransactionType.expense => Icons.north_east_rounded,
                    TransactionType.transfer => Icons.swap_horiz_rounded,
                  }, size: 28),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(transaction.type.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$sign${Formatters.currency(transaction.amount)}',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: tint, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Column(
            children: <Widget>[
              _DetailRow(
                label: 'Kategori',
                value:
                    category?.asData?.value?.name ??
                    (transaction.type.isTransfer ? 'Transfer antar akun' : '—'),
              ),
              const Divider(height: 1),
              _DetailRow(
                label: transaction.type == TransactionType.income
                    ? 'Akun tujuan'
                    : 'Akun sumber',
                value: account.asData?.value?.name ?? 'Memuat akun...',
              ),
              if (destination != null) ...<Widget>[
                const Divider(height: 1),
                _DetailRow(
                  label: 'Akun tujuan transfer',
                  value: destination.asData?.value?.name ?? 'Memuat akun...',
                ),
              ],
              const Divider(height: 1),
              _DetailRow(
                label: 'Tanggal',
                value: Formatters.shortDateTime(transaction.transactionDate),
              ),
              if (transaction.note != null) ...<Widget>[
                const Divider(height: 1),
                _DetailRow(label: 'Catatan', value: transaction.note!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(flex: 3, child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}
