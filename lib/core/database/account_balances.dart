import 'package:drift/drift.dart';

import 'app_database.dart';
import 'enums.dart';

/// Derived balance figures for one account.
///
/// Every figure is computed from the ledger, never stored, so the balance can
/// not drift out of sync with the rows that produced it.
class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.initialBalance,
    required this.income,
    required this.expense,
    required this.transferIn,
    required this.transferOut,
    required this.savingsDeposit,
    required this.savingsWithdrawal,
  });

  final int accountId;
  final int initialBalance;

  /// Total income credited to this account.
  final int income;

  /// Total expense debited from this account.
  final int expense;

  /// Total transferred into this account.
  final int transferIn;

  /// Total transferred out of this account.
  final int transferOut;

  /// Total savings moved out of this account into goals.
  final int savingsDeposit;

  /// Total savings returned to this account from goals.
  final int savingsWithdrawal;

  /// Balance available to spend right now.
  int get currentBalance =>
      initialBalance +
      income +
      transferIn +
      savingsWithdrawal -
      expense -
      transferOut -
      savingsDeposit;

  /// Money that left the account for expenses or transfers.
  int get totalOutflow => expense + transferOut + savingsDeposit;

  /// Money that entered the account.
  int get totalInflow => income + transferIn + savingsWithdrawal;
}

/// Aggregated balances for the whole wallet, used by the dashboard.
class WalletBalance {
  const WalletBalance({required this.accounts, required this.total});

  final List<AccountBalance> accounts;
  final int total;
}

/// Read-only balance projections over the transaction and savings ledgers.
class AccountBalanceCalculator {
  const AccountBalanceCalculator(this._db);

  final AppDatabase _db;

  /// Balance for a single account, or `null` when the account does not exist.
  /// Archived accounts remain queryable so historical balances never disappear.
  Future<AccountBalance?> forAccount(int accountId) async {
    final List<AccountBalance> rows = await _query(
      accountId: accountId,
      includeArchived: true,
    );
    return rows.isEmpty ? null : rows.single;
  }

  /// Balances for every account, optionally including archived accounts.
  Future<List<AccountBalance>> all({bool includeArchived = false}) {
    return _query(includeArchived: includeArchived);
  }

  /// Summed balance across all non-archived accounts.
  Future<int> totalBalance() async {
    final List<AccountBalance> rows = await _query();
    int total = 0;
    for (final AccountBalance row in rows) {
      total += row.currentBalance;
    }
    return total;
  }

  Future<List<AccountBalance>> _query({
    int? accountId,
    bool includeArchived = false,
  }) async {
    final List<String> conditions = <String>[];
    final List<Variable<Object>> variables = <Variable<Object>>[];

    if (accountId != null) {
      conditions.add('a.id = ?');
      variables.add(Variable<int>(accountId));
    }
    if (!includeArchived) {
      conditions.add('a.is_archived = 0');
    }

    final String where =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final String sql = '''
SELECT
  a.id AS account_id,
  a.initial_balance AS initial_balance,
  COALESCE((
    SELECT SUM(t.amount) FROM transactions t
    WHERE t.account_id = a.id AND t.type = '${TransactionType.income.name}'
  ), 0) AS income,
  COALESCE((
    SELECT SUM(t.amount) FROM transactions t
    WHERE t.account_id = a.id AND t.type = '${TransactionType.expense.name}'
  ), 0) AS expense,
  COALESCE((
    SELECT SUM(t.amount) FROM transactions t
    WHERE t.to_account_id = a.id AND t.type = '${TransactionType.transfer.name}'
  ), 0) AS transfer_in,
  COALESCE((
    SELECT SUM(t.amount) FROM transactions t
    WHERE t.account_id = a.id AND t.type = '${TransactionType.transfer.name}'
  ), 0) AS transfer_out,
  COALESCE((
    SELECT SUM(s.amount) FROM savings_contributions s
    WHERE s.account_id = a.id AND s.type = '${SavingsEntryType.deposit.name}'
  ), 0) AS savings_deposit,
  COALESCE((
    SELECT SUM(s.amount) FROM savings_contributions s
    WHERE s.account_id = a.id AND s.type = '${SavingsEntryType.withdrawal.name}'
  ), 0) AS savings_withdrawal
FROM accounts a
$where
ORDER BY a.sort_order, a.id
''';

    final List<QueryRow> rows = await _db.customSelect(sql, variables: variables).get();

    return rows.map((QueryRow row) {
      return AccountBalance(
        accountId: row.read<int>('account_id'),
        initialBalance: row.read<int>('initial_balance'),
        income: row.read<int>('income'),
        expense: row.read<int>('expense'),
        transferIn: row.read<int>('transfer_in'),
        transferOut: row.read<int>('transfer_out'),
        savingsDeposit: row.read<int>('savings_deposit'),
        savingsWithdrawal: row.read<int>('savings_withdrawal'),
      );
    }).toList(growable: false);
  }

  /// Combined wallet balance plus per-account detail.
  Future<WalletBalance> wallet() async {
    final List<AccountBalance> accounts = await all();
    int total = 0;
    for (final AccountBalance account in accounts) {
      total += account.currentBalance;
    }
    return WalletBalance(accounts: accounts, total: total);
  }
}
