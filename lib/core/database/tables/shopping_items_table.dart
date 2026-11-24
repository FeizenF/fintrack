import 'package:drift/drift.dart';

import 'shopping_lists_table.dart';

/// One planned/purchased line inside a shopping note.
///
/// Quantity and unit price are both stored so the list can be reused as a
/// template ("2 kg beras") while the total stays a plain sum of the lines.
@DataClassName('ShoppingItem')
@TableIndex(name: 'idx_shopping_items_list', columns: {#listId, #sortOrder})
class ShoppingItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Deleting a note removes its lines; a line never outlives its note.
  IntColumn get listId => integer().references(
    ShoppingLists,
    #id,
    onDelete: KeyAction.cascade,
    onUpdate: KeyAction.cascade,
  )();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  IntColumn get quantity => integer().withDefault(const Constant(1))();

  /// Price per unit in Rupiah. Null when the user has not filled it yet, which
  /// keeps a checklist usable without hunting for prices.
  IntColumn get unitPrice => integer().nullable()();

  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
    'CHECK (quantity > 0)',
    'CHECK (unit_price IS NULL OR unit_price >= 0)',
    'CHECK (length(trim(name)) > 0)',
  ];
}
