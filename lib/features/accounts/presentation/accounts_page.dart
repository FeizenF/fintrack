import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/account_balances.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/accounts_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Account>> accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Akun Keuangan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAccountForm(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah akun'),
      ),
      body: accounts.when(
        loading: () => const LoadingState(message: 'Memuat akun...'),
        error: (Object error, StackTrace stack) =>
            const ErrorStateView(message: 'Akun gagal dimuat.'),
        data: (List<Account> rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Belum ada akun',
              message: 'Tambahkan akun untuk mencatat transaksi.',
              action: FilledButton.icon(
                onPressed: () => _showAccountForm(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah akun'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              final Account account = rows[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(_accountIcon(account.type)),
                  ),
                  title: Text(account.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(text: account.type.label),
                            if (account.isArchived)
                              TextSpan(
                                text: ' · Diarsipkan',
                                style: TextStyle(
                                  color: AppColors.warningOf(
                                    Theme.of(context).brightness,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Consumer(
                        builder: (BuildContext context, WidgetRef ref, _) {
                          final AsyncValue<AccountBalance?> balance = ref.watch(
                            accountBalanceProvider(account.id),
                          );
                          return balance.when(
                            loading: () => const Text('Memuat saldo...'),
                            error: (Object error, StackTrace stack) =>
                                const Text('Saldo tidak tersedia'),
                            data: (AccountBalance? value) => Text(
                              value == null
                                  ? 'Saldo tidak tersedia'
                                  : Formatters.currency(value.currentBalance),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Aksi akun ${account.name}',
                    onSelected: (String action) async {
                      if (action == 'edit') {
                        await _showAccountForm(context, ref, account: account);
                      } else if (action == 'archive') {
                        await _setArchived(
                          context,
                          ref,
                          account,
                          !account.isArchived,
                        );
                      } else if (action == 'delete') {
                        await _deleteAccount(context, ref, account);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Ubah'),
                          ),
                          PopupMenuItem<String>(
                            value: 'archive',
                            child: Text(
                              account.isArchived ? 'Pulihkan' : 'Arsipkan',
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Hapus'),
                          ),
                        ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static IconData _accountIcon(AccountType type) => switch (type) {
    AccountType.cash => Icons.account_balance_wallet_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.eWallet => Icons.phone_android_rounded,
    AccountType.businessCash => Icons.storefront_outlined,
    AccountType.other => Icons.savings_outlined,
  };

  Future<void> _showAccountForm(
    BuildContext context,
    WidgetRef ref, {
    Account? account,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _AccountFormDialog(account: account),
    );
    if (saved == true) ref.invalidate(accountsProvider);
  }

  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref,
    Account account,
    bool archived,
  ) async {
    final AccountsRepository repository = await ref.read(
      accountsRepositoryProvider.future,
    );
    try {
      await repository.setArchived(account.id, archived);
      ref.invalidate(accountsProvider);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          error is AppException
              ? error.message
              : 'Status akun gagal diubah. Silakan coba lagi.',
        );
      }
    }
  }

  Future<void> _deleteAccount(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Hapus akun?'),
            content: Text('Akun "${account.name}" akan dihapus permanen.'),
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

    final AccountsRepository repository = await ref.read(
      accountsRepositoryProvider.future,
    );
    try {
      await repository.delete(account.id);
      ref.invalidate(accountsProvider);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(
          context,
          error is AppException
              ? error.message
              : 'Akun gagal dihapus. Silakan coba lagi.',
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountFormDialog extends ConsumerStatefulWidget {
  const _AccountFormDialog({this.account});

  final Account? account;

  @override
  ConsumerState<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends ConsumerState<_AccountFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final TextEditingController _note;
  late AccountType _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account?.name ?? '');
    _balance = TextEditingController(
      text: widget.account == null
          ? ''
          : Formatters.number(widget.account!.initialBalance),
    );
    _note = TextEditingController(text: widget.account?.note ?? '');
    _type = widget.account?.type ?? AccountType.cash;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.account == null ? 'Tambah akun' : 'Ubah akun'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nama akun'),
          ),
          DropdownButtonFormField<AccountType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Jenis akun'),
            items: AccountType.values
                .map(
                  (AccountType type) => DropdownMenuItem<AccountType>(
                    value: type,
                    child: Text(type.label),
                  ),
                )
                .toList(),
            onChanged: (AccountType? value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          TextField(
            controller: _balance,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Saldo awal (Rp)'),
          ),
          TextField(
            controller: _note,
            maxLength: 240,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
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
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
      ),
    ],
  );

  Future<void> _save() async {
    final String name = _name.text.trim();
    final int initialBalance = Formatters.parseAmount(_balance.text) ?? 0;
    setState(() => _saving = true);
    try {
      final AccountsRepository repository = await ref.read(
        accountsRepositoryProvider.future,
      );
      if (widget.account == null) {
        await repository.create(
          name: name,
          type: _type,
          initialBalance: initialBalance,
          note: _note.text,
        );
      } else {
        await repository.update(
          widget.account!.id,
          name: name,
          type: _type,
          initialBalance: initialBalance,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is AppException
                  ? error.message
                  : 'Akun gagal disimpan. Silakan coba lagi.',
            ),
          ),
        );
      }
    }
  }
}
