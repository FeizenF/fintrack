import 'package:drift/drift.dart';

import 'transactions_table.dart';

/// A shopping note: the "catatan belanja" a user writes before or while
/// shopping. Items live in [ShoppingItems]; once the user books the total it
/// points at the expense row it created, so the same money is never recorded
/// twice.
@DataClassName('ShoppingList')
@TableIndex(name: 'idx_shopping_lists_date', columns: {#shoppingDate})
class ShoppingLists extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 80)();

  TextColumn get note => text().nullable()();

  /// Day the shopping happened. Also used as the expense date when booked.
  DateTimeColumn get shoppingDate => dateTime()();

  /// Expense row created from this note's total. `setNull` keeps the note
  /// readable if the user deletes that transaction from the ledger.
  IntColumn get transactionId => integer()
      .nullable()
      .references(
        Transactions,
        #id,
        onDelete: KeyAction.setNull,
        onUpdate: KeyAction.cascade,
      )();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
    'CHECK (length(trim(title)) > 0)',
  ];
}
