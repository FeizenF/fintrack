import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/savings_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

/// Savings goal ledger. Contributions link a goal and account, so each deposit
/// updates both saved progress and available wallet balance exactly once.
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SavingsProgress>> goals = ref.watch(
      archivedSavingsProgressProvider,
    );
    final List<Account> accounts =
        (ref.watch(accountsProvider).value ?? const <Account>[])
            .where((Account account) => !account.isArchived)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Target Tabungan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openGoalForm(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah target'),
      ),
      body: goals.when(
        loading: () => const LoadingState(message: 'Memuat target tabungan...'),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Target tabungan gagal dimuat.',
          onRetry: () => ref.invalidate(archivedSavingsProgressProvider),
        ),
        data: (List<SavingsProgress> rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.savings_outlined,
              title: 'Belum ada target tabungan',
              message: 'Buat target, lalu catat setoran dan penarikan.',
              action: FilledButton.icon(
                onPressed: () => _openGoalForm(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah target'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl * 4,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) => _GoalCard(
              progress: rows[index],
              canContribute: accounts.isNotEmpty,
              onDeposit: () => _openContribution(
                context,
                ref,
                rows[index],
                SavingsEntryType.deposit,
              ),
              onWithdraw: () => _openContribution(
                context,
                ref,
                rows[index],
                SavingsEntryType.withdrawal,
              ),
              onEdit: () => _openGoalForm(context, ref, rows[index].goal),
              onArchive: () => _setArchived(context, ref, rows[index]),
              onDelete: () => _deleteGoal(context, ref, rows[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openGoalForm(
    BuildContext context,
    WidgetRef ref, [
    SavingsGoal? goal,
  ]) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GoalFormDialog(goal: goal),
    );
    if (saved == true) ref.invalidate(archivedSavingsProgressProvider);
  }

  Future<void> _openContribution(
    BuildContext context,
    WidgetRef ref,
    SavingsProgress progress,
    SavingsEntryType type,
  ) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ContributionDialog(progress: progress, type: type),
    );
    if (saved == true) {
      ref.invalidate(archivedSavingsProgressProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(accountBalanceCalculatorProvider);
    }
  }

  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref,
    SavingsProgress progress,
  ) async {
    final bool archive = !progress.goal.isArchived;
    try {
      final SavingsRepository repository = await ref.read(
        savingsRepositoryProvider.future,
      );
      await repository.setGoalArchived(progress.goal.id, archive);
      ref.invalidate(archivedSavingsProgressProvider);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          error is AppException
              ? error.message
              : 'Status target gagal diubah. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _deleteGoal(
    BuildContext context,
    WidgetRef ref,
    SavingsProgress progress,
  ) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Hapus target?'),
            content: Text(
              'Target "${progress.goal.name}" hanya dapat dihapus jika belum '
              'memiliki setoran. Target dengan riwayat dapat diarsipkan.',
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
    if (!confirmed || !context.mounted) return;
    try {
      final SavingsRepository repository = await ref.read(
        savingsRepositoryProvider.future,
      );
      await repository.deleteGoal(progress.goal.id);
      ref.invalidate(archivedSavingsProgressProvider);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          error is AppException
              ? error.message
              : 'Target gagal dihapus. Silakan coba lagi.',
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.progress,
    required this.canContribute,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  final SavingsProgress progress;
  final bool canContribute;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Color color = progress.isComplete
        ? AppColors.incomeOf(Theme.of(context).brightness)
        : Theme.of(context).colorScheme.primary;
    final double barValue = progress.ratio.clamp(0.0, 1.0);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  progress.goal.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Aksi target ${progress.goal.name}',
                onSelected: (String action) {
                  switch (action) {
                    case 'edit':
                      onEdit();
                    case 'archive':
                      onArchive();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Ubah target'),
                  ),
                  PopupMenuItem<String>(
                    value: 'archive',
                    child: Text(
                      progress.goal.isArchived ? 'Pulihkan' : 'Arsipkan',
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Hapus'),
                  ),
                ],
              ),
            ],
          ),
          Text(
            '${Formatters.currency(progress.saved)} dari ${Formatters.currency(progress.target)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: barValue,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            progress.isComplete
                ? 'Target tercapai · ${Formatters.percent(progress.ratio * 100)}'
                : 'Terkumpul ${Formatters.percent(progress.ratio * 100)} · Sisa ${Formatters.currency(progress.remaining)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
          if (progress.goal.targetDate != null ||
              progress.goal.note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            if (progress.goal.targetDate != null)
              Text('Target ${Formatters.fullDate(progress.goal.targetDate!)}'),
            if (progress.goal.note != null)
              Text(
                progress.goal.note!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          if (progress.goal.isArchived)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Diarsipkan'),
            )
          else ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: canContribute ? onDeposit : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Setor'),
                ),
                OutlinedButton.icon(
                  onPressed: canContribute && progress.saved > 0
                      ? onWithdraw
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('Tarik'),
                ),
                if (!canContribute)
                  const Text('Tambahkan akun aktif sebelum mencatat setoran.'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalFormDialog extends ConsumerStatefulWidget {
  const _GoalFormDialog({this.goal});

  final SavingsGoal? goal;

  @override
  ConsumerState<_GoalFormDialog> createState() => _GoalFormDialogState();
}

class _GoalFormDialogState extends ConsumerState<_GoalFormDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.goal?.name ?? '',
  );
  late final TextEditingController _target = TextEditingController(
    text: widget.goal == null
        ? ''
        : Formatters.number(widget.goal!.targetAmount),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.goal?.note ?? '',
  );
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _targetDate = widget.goal?.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.goal == null ? 'Tambah target' : 'Ubah target'),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Nama target'),
              validator: (String? value) =>
                  value == null || value.trim().isEmpty
                  ? 'Nama wajib diisi.'
                  : null,
            ),
            TextFormField(
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nominal target (Rp)',
              ),
              validator: (String? value) =>
                  (Formatters.parseAmount(value ?? '') ?? 0) <= 0
                  ? 'Masukkan nominal lebih dari nol.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _targetDate == null
                    ? 'Pilih tanggal target (opsional)'
                    : Formatters.fullDate(_targetDate!),
              ),
            ),
            if (_targetDate != null)
              TextButton(
                onPressed: () => setState(() => _targetDate = null),
                child: const Text('Hapus tanggal'),
              ),
            TextFormField(
              controller: _note,
              maxLength: 240,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? result = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 50),
    );
    if (result != null) setState(() => _targetDate = result);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final int? amount = Formatters.parseAmount(_target.text);
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      final SavingsRepository repository = await ref.read(
        savingsRepositoryProvider.future,
      );
      if (widget.goal == null) {
        await repository.createGoal(
          name: _name.text,
          targetAmount: amount,
          targetDate: _targetDate,
          note: _note.text,
        );
      } else {
        await repository.updateGoal(
          widget.goal!.id,
          name: _name.text,
          targetAmount: amount,
          targetDate: _targetDate,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Data gagal disimpan. Silakan coba lagi.',
          ),
        ),
      );
    }
  }
}

class _ContributionDialog extends ConsumerStatefulWidget {
  const _ContributionDialog({required this.progress, required this.type});

  final SavingsProgress progress;
  final SavingsEntryType type;

  @override
  ConsumerState<_ContributionDialog> createState() =>
      _ContributionDialogState();
}

class _ContributionDialogState extends ConsumerState<_ContributionDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int? _accountId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> accounts =
        (ref.watch(accountsProvider).value ?? const <Account>[])
            .where((Account account) => !account.isArchived)
            .toList(growable: false);
    final int? selected =
        accounts.any((Account account) => account.id == _accountId)
        ? _accountId
        : (accounts.isEmpty ? null : accounts.first.id);
    final bool deposit = widget.type == SavingsEntryType.deposit;

    return AlertDialog(
      title: Text(deposit ? 'Setor tabungan' : 'Tarik tabungan'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Akun keuangan'),
              items: accounts
                  .map(
                    (Account account) => DropdownMenuItem<int>(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (int? id) => setState(() => _accountId = id),
              validator: (int? id) => id == null ? 'Pilih akun.' : null,
            ),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: deposit
                    ? 'Nominal setoran (Rp)'
                    : 'Nominal penarikan (Rp)',
                helperText: deposit
                    ? null
                    : 'Dana tersedia ${Formatters.currency(widget.progress.saved)}',
              ),
              validator: (String? value) {
                final int amount = Formatters.parseAmount(value ?? '') ?? 0;
                if (amount <= 0) return 'Masukkan nominal lebih dari nol.';
                if (!deposit && amount > widget.progress.saved) {
                  return 'Melebihi dana terkumpul.';
                }
                return null;
              },
            ),
            TextField(
              controller: _note,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
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
          child: Text(
            _saving
                ? 'Menyimpan...'
                : 'Simpan ${deposit ? 'setoran' : 'penarikan'}',
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final int amount = Formatters.parseAmount(_amount.text)!;
    final List<Account> accounts =
        ref.read(accountsProvider).value ?? const <Account>[];
    final int? accountId =
        accounts.any((Account account) => account.id == _accountId)
        ? _accountId
        : accounts
              .where((Account account) => !account.isArchived)
              .firstOrNull
              ?.id;
    if (accountId == null) return;
    setState(() => _saving = true);
    try {
      final SavingsRepository repository = await ref.read(
        savingsRepositoryProvider.future,
      );
      final int goalId = widget.progress.goal.id;
      final DateTime date = DateTime.now();
      if (widget.type == SavingsEntryType.deposit) {
        await repository.deposit(
          goalId: goalId,
          accountId: accountId,
          amount: amount,
          date: date,
          note: _note.text,
        );
      } else {
        await repository.withdraw(
          goalId: goalId,
          accountId: accountId,
          amount: amount,
          date: date,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Data gagal disimpan. Silakan coba lagi.',
          ),
        ),
      );
    }
  }
}
