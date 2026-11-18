import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/budgets_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

/// Monthly spending limits per expense category.
///
/// Every number on this page comes from [BudgetsRepository.watch], which sums
/// the ledger for the selected month, so "terpakai" can never drift from the
/// transactions that produced it.
class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  late DateTime _month = _monthOf(DateTime.now());

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<BudgetProgress>> value = ref.watch(
      budgetProgressProvider(_month),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggaran'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Bulan sebelumnya',
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Center(
            child: Text(
              Formatters.monthYear(_month),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Bulan berikutnya',
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah anggaran'),
      ),
      body: value.when(
        loading: () => const LoadingState(message: 'Memuat anggaran...'),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Anggaran gagal dimuat.',
          onRetry: () => ref.invalidate(budgetProgressProvider(_month)),
        ),
        data: (List<BudgetProgress> rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'Belum ada anggaran',
              message:
                  'Atur batas pengeluaran per kategori untuk ${Formatters.monthYear(_month)}.',
              action: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah anggaran'),
              ),
            );
          }

          final int totalLimit = rows.fold<int>(
            0,
            (int sum, BudgetProgress row) => sum + row.limit,
          );
          final int totalSpent = rows.fold<int>(
            0,
            (int sum, BudgetProgress row) => sum + row.spent,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl * 4,
            ),
            children: <Widget>[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ringkasan bulan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SummaryRow(label: 'Terpakai', amount: totalSpent),
                    const SizedBox(height: AppSpacing.xs),
                    _SummaryRow(label: 'Total batas', amount: totalLimit),
                    const SizedBox(height: AppSpacing.xs),
                    _SummaryRow(label: 'Sisa', amount: totalLimit - totalSpent),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final BudgetProgress progress in rows) ...<Widget>[
                _BudgetCard(
                  progress: progress,
                  onEdit: () => _openForm(progress: progress),
                  onDelete: () => _confirmDelete(progress),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm({BudgetProgress? progress}) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BudgetFormDialog(month: _month, progress: progress),
    );
    if (saved == true) ref.invalidate(budgetProgressProvider(_month));
  }

  Future<void> _confirmDelete(BudgetProgress progress) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Hapus anggaran?'),
            content: Text(
              'Anggaran ${progress.categoryName} bulan ini akan dihapus. '
              'Transaksi yang sudah tercatat tidak berubah.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      final BudgetsRepository repository = await ref.read(
        budgetsRepositoryProvider.future,
      );
      await repository.delete(progress.budget.id);
      if (mounted) ref.invalidate(budgetProgressProvider(_month));
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Text(label),
      Text(
        Formatters.currency(amount),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ],
  );
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.progress,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color color = progress.isExceeded
        ? AppColors.expenseOf(brightness)
        : progress.isNearLimit
        ? AppColors.warningOf(brightness)
        : Theme.of(context).colorScheme.primary;
    final String status = progress.isExceeded
        ? 'Terlampaui ${Formatters.currency(-progress.remaining)}'
        : 'Sisa ${Formatters.currency(progress.remaining)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  progress.categoryName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                Formatters.percent(progress.ratio * 100),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: color),
              ),
              PopupMenuButton<String>(
                tooltip: 'Aksi anggaran ${progress.categoryName}',
                onSelected: (String action) =>
                    action == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Ubah batas'),
                  ),
                  PopupMenuItem<String>(value: 'delete', child: Text('Hapus')),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Terpakai ${Formatters.currency(progress.spent)}'),
              Text('Batas ${Formatters.currency(progress.limit)}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: progress.ratio.clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            progress.isNearLimit && !progress.isExceeded
                ? 'Mendekati batas. $status'
                : status,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _BudgetFormDialog extends ConsumerStatefulWidget {
  const _BudgetFormDialog({required this.month, this.progress});

  final DateTime month;
  final BudgetProgress? progress;

  @override
  ConsumerState<_BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends ConsumerState<_BudgetFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: widget.progress == null
        ? ''
        : Formatters.number(widget.progress!.limit),
  );
  int? _categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Expense categories that do not already own a budget in the target month,
  /// excluding the category of the budget being edited.
  List<Category> _selectable() {
    final List<Category> expense =
        (ref.watch(categoriesProvider).value ?? const <Category>[])
            .where(
              (Category category) =>
                  category.kind == CategoryKind.expense && !category.isArchived,
            )
            .toList(growable: false);
    final Set<int> taken =
        (ref.watch(budgetProgressProvider(widget.month)).value ??
                const <BudgetProgress>[])
            .map((BudgetProgress row) => row.budget.categoryId)
            .where((int id) => id != widget.progress?.budget.categoryId)
            .toSet();
    return expense
        .where((Category category) => !taken.contains(category.id))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Category> selectable = _selectable();
    final int? selected =
        widget.progress?.budget.categoryId ??
        (_categoryId != null &&
                selectable.any((Category c) => c.id == _categoryId)
            ? _categoryId
            : (selectable.isEmpty ? null : selectable.first.id));

    return AlertDialog(
      title: Text(
        widget.progress == null ? 'Tambah anggaran' : 'Ubah anggaran',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.progress == null)
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: selectable
                    .map(
                      (Category category) => DropdownMenuItem<int>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (int? id) => setState(() => _categoryId = id),
                validator: (int? id) => id == null ? 'Pilih kategori.' : null,
              )
            else
              Text('Kategori: ${widget.progress!.categoryName}'),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Batas bulanan (Rp)',
              ),
              validator: (String? value) =>
                  (Formatters.parseAmount(value ?? '') ?? 0) <= 0
                  ? 'Masukkan nominal lebih dari nol.'
                  : null,
            ),
            if (widget.progress == null && selectable.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Semua kategori pengeluaran sudah punya anggaran bulan ini.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving || selected == null ? null : _save,
          child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final int? amount = Formatters.parseAmount(_amount.text);
    if (amount == null) return;
    final int? categoryId =
        widget.progress?.budget.categoryId ?? _categoryId ?? _firstSelectable();
    if (categoryId == null) return;

    setState(() => _saving = true);
    try {
      final BudgetsRepository repository = await ref.read(
        budgetsRepositoryProvider.future,
      );
      final BudgetProgress? progress = widget.progress;
      if (progress == null) {
        await repository.create(
          categoryId: categoryId,
          monthStart: widget.month,
          limitAmount: amount,
        );
      } else {
        await repository.updateLimit(progress.budget.id, amount);
      }
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  int? _firstSelectable() {
    final List<Category> selectable = _selectable();
    return selectable.isEmpty ? null : selectable.first.id;
  }
}
