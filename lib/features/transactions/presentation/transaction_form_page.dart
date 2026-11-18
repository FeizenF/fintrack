import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/transactions_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({super.key, this.transactionId});

  final int? transactionId;

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  TransactionType _type = TransactionType.expense;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  DateTime _date = DateTime.now();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Account>> accounts = ref.watch(accountsProvider);
    final AsyncValue<List<Category>> categories = ref.watch(categoriesProvider);
    final int? id = widget.transactionId;
    final AsyncValue<FinancialTransaction?>? existing = id == null
        ? null
        : ref.watch(transactionByIdProvider(id));

    if (accounts.isLoading ||
        categories.isLoading ||
        (existing?.isLoading ?? false)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(id == null ? 'Transaksi Baru' : 'Ubah Transaksi'),
        ),
        body: const LoadingState(message: 'Memuat data transaksi...'),
      );
    }
    if (accounts.hasError ||
        categories.hasError ||
        (existing?.hasError ?? false)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(id == null ? 'Transaksi Baru' : 'Ubah Transaksi'),
        ),
        body: ErrorStateView(
          message: 'Data transaksi gagal dimuat.',
          onRetry: () {
            ref.invalidate(accountsProvider);
            ref.invalidate(categoriesProvider);
            if (id != null) ref.invalidate(transactionByIdProvider(id));
          },
        ),
      );
    }

    final List<Account> allAccounts = accounts.value ?? const <Account>[];
    final List<Account> activeAccounts = allAccounts
        .where((Account account) => !account.isArchived)
        .toList();
    final List<Category> allCategories = categories.value ?? const <Category>[];
    final List<Category> applicableCategories = allCategories
        .where(
          (Category category) =>
              !category.isArchived && category.kind == _categoryKind,
        )
        .toList();
    final FinancialTransaction? transaction = existing?.value;

    if (id != null && transaction == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaksi')),
        body: const ErrorStateView(message: 'Transaksi tidak ditemukan.'),
      );
    }
    if (!_initialized) {
      _initialized = true;
      if (transaction != null) {
        _type = transaction.type;
        _accountId = transaction.accountId;
        _toAccountId = transaction.toAccountId;
        _categoryId = transaction.categoryId;
        _amount.text = Formatters.number(transaction.amount);
        _note.text = transaction.note ?? '';
        _date = transaction.transactionDate;
      } else if (activeAccounts.isNotEmpty) {
        _accountId = activeAccounts.first.id;
      }
    }
    if (_accountId == null && activeAccounts.isNotEmpty) {
      _accountId = activeAccounts.first.id;
    }
    if (_type.isTransfer) {
      if (_toAccountId == null || _toAccountId == _accountId) {
        _toAccountId = activeAccounts
            .where((Account account) => account.id != _accountId)
            .firstOrNull
            ?.id;
      }
    } else if (!applicableCategories.any((Category c) => c.id == _categoryId) &&
        applicableCategories.isNotEmpty) {
      _categoryId = applicableCategories.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? 'Transaksi Baru' : 'Ubah Transaksi'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            SegmentedButton<TransactionType>(
              segments: const <ButtonSegment<TransactionType>>[
                ButtonSegment<TransactionType>(
                  value: TransactionType.expense,
                  label: Text('Pengeluaran'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment<TransactionType>(
                  value: TransactionType.income,
                  label: Text('Pemasukan'),
                  icon: Icon(Icons.south_west_rounded),
                ),
                ButtonSegment<TransactionType>(
                  value: TransactionType.transfer,
                  label: Text('Transfer'),
                  icon: Icon(Icons.swap_horiz_rounded),
                ),
              ],
              selected: <TransactionType>{_type},
              onSelectionChanged: id == null
                  ? (Set<TransactionType> selected) {
                      setState(() {
                        _type = selected.first;
                        _categoryId = null;
                        if (_type.isTransfer) _toAccountId = null;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                final int? amount = Formatters.parseAmount(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Nominal harus lebih dari nol.';
                }
                if (amount > 999999999999) return 'Nominal terlalu besar.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (activeAccounts.isEmpty)
              const _InlineNotice(
                text: 'Tambahkan akun terlebih dahulu melalui Pengaturan > Akun Keuangan.',
              )
            else ...<Widget>[
              DropdownButtonFormField<int>(
                key: ValueKey<String>('source-$_accountId'),
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: _type == TransactionType.income
                      ? 'Akun tujuan'
                      : 'Akun sumber',
                  border: const OutlineInputBorder(),
                ),
                items: activeAccounts
                    .map(
                      (Account account) => DropdownMenuItem<int>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                onChanged: (int? value) => setState(() => _accountId = value),
                validator: (int? value) => value == null ? 'Pilih akun.' : null,
              ),
              if (_type.isTransfer) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>(
                    'destination-$_toAccountId-$_accountId',
                  ),
                  initialValue: _toAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Akun tujuan',
                    border: OutlineInputBorder(),
                  ),
                  items: activeAccounts
                      .where((Account account) => account.id != _accountId)
                      .map(
                        (Account account) => DropdownMenuItem<int>(
                          value: account.id,
                          child: Text(account.name),
                        ),
                      )
                      .toList(),
                  onChanged: (int? value) =>
                      setState(() => _toAccountId = value),
                  validator: (int? value) {
                    if (value == null) return 'Pilih akun tujuan yang berbeda.';
                    if (value == _accountId) return 'Akun harus berbeda.';
                    return null;
                  },
                ),
              ],
            ],
            if (!_type.isTransfer) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              if (applicableCategories.isEmpty)
                const _InlineNotice(
                  text: 'Tidak ada kategori aktif untuk jenis ini.',
                )
              else
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('category-$_categoryId-$_type'),
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: applicableCategories
                      .map(
                        (Category category) => DropdownMenuItem<int>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: (int? value) =>
                      setState(() => _categoryId = value),
                  validator: (int? value) =>
                      value == null ? 'Pilih kategori.' : null,
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Tanggal: ${Formatters.fullDate(_date)}'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _note,
              maxLength: 240,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _saving || activeAccounts.isEmpty ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan transaksi'),
            ),
          ],
        ),
      ),
    );
  }

  CategoryKind get _categoryKind => _type == TransactionType.income
      ? CategoryKind.income
      : CategoryKind.expense;

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final TransactionsRepository repository = await ref.read(
        transactionsRepositoryProvider.future,
      );
      final int amount = Formatters.parseAmount(_amount.text)!;
      final int accountId = _accountId!;
      final int? transactionId = widget.transactionId;
      if (_type == TransactionType.income) {
        if (transactionId == null) {
          await repository.createIncome(
            accountId: accountId,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            note: _note.text,
          );
        } else {
          await repository.updateIncome(
            transactionId,
            accountId: accountId,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            note: _note.text,
          );
        }
      } else if (_type == TransactionType.expense) {
        if (transactionId == null) {
          await repository.createExpense(
            accountId: accountId,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            note: _note.text,
          );
        } else {
          await repository.updateExpense(
            transactionId,
            accountId: accountId,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            note: _note.text,
          );
        }
      } else if (transactionId == null) {
        await repository.createTransfer(
          fromAccountId: accountId,
          toAccountId: _toAccountId!,
          amount: amount,
          date: _date,
          note: _note.text,
        );
      } else {
        await repository.updateTransfer(
          transactionId,
          fromAccountId: accountId,
          toAccountId: _toAccountId!,
          amount: amount,
          date: _date,
          note: _note.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
