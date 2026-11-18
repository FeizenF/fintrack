/// Domain enums persisted as text in SQLite.
///
/// Text storage keeps backups readable and lets a future schema version add
/// values without rewriting existing rows.
library;

/// Kind of a financial account.
enum AccountType {
  cash('Tunai'),
  bank('Bank'),
  eWallet('E-Wallet'),
  businessCash('Dana Usaha'),
  other('Lainnya');

  const AccountType(this.label);

  final String label;
}

/// Kind of a category, which must match the transaction type.
enum CategoryKind {
  income('Pemasukan'),
  expense('Pengeluaran');

  const CategoryKind(this.label);

  final String label;
}

/// Kind of a transaction. A transfer is a single row with both an origin and a
/// destination account, so it can never be counted twice.
enum TransactionType {
  income('Pemasukan'),
  expense('Pengeluaran'),
  transfer('Transfer');

  const TransactionType(this.label);

  final String label;

  bool get isTransfer => this == TransactionType.transfer;
}

/// Direction of a savings contribution.
enum SavingsEntryType {
  deposit('Setoran'),
  withdrawal('Penarikan');

  const SavingsEntryType(this.label);

  final String label;
}
