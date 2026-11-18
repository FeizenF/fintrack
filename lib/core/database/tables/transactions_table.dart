import 'package:drift/drift.dart';

import '../enums.dart';
import 'accounts_table.dart';
import 'categories_table.dart';

/// Append-only financial ledger rows (a row can be edited/deleted only through
/// an explicit user action). Monetary values use integer Rupiah.
@DataClassName('FinancialTransaction')
@TableIndex(name: 'idx_transactions_date', columns: {#transactionDate})
@TableIndex(name: 'idx_transactions_account_date', columns: {#accountId, #transactionDate})
@TableIndex(name: 'idx_transactions_category_date', columns: {#categoryId, #transactionDate})
@TableIndex(name: 'idx_transactions_type_date', columns: {#type, #transactionDate})
@TableIndex(name: 'idx_transactions_to_account_date', columns: {#toAccountId, #transactionDate})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get type => textEnum<TransactionType>()();

  /// Primary account: source for expense/transfer; destination for income.
  @ReferenceName('sourceTransactions')
  IntColumn get accountId => integer().references(
        Accounts,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  /// Category for income/expense. Null only for transfers.
  IntColumn get categoryId => integer()
      .nullable()
      .references(
        Categories,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  /// Destination for transfer, null for income/expense.
  @ReferenceName('destinationTransactions')
  IntColumn get toAccountId => integer()
      .nullable()
      .references(
        Accounts,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  IntColumn get amount => integer()();

  DateTimeColumn get transactionDate => dateTime()();

  TextColumn get note => text().nullable()();

  /// Local attachment path/URI. Backup excludes binary data; file backup may
  /// optionally include attachments in a later iteration.
  TextColumn get attachmentPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'CHECK (amount > 0)',
        "CHECK ((type = 'transfer' AND category_id IS NULL AND to_account_id IS NOT NULL AND to_account_id != account_id) OR (type IN ('income', 'expense') AND category_id IS NOT NULL AND to_account_id IS NULL))",
      ];
}
