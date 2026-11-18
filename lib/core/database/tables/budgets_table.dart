import 'package:drift/drift.dart';

import 'categories_table.dart';

/// Monthly spending limits by expense category.
@DataClassName('Budget')
@TableIndex(name: 'idx_budgets_month', columns: {#monthStart})
@TableIndex(name: 'idx_budgets_category_month', columns: {#categoryId, #monthStart})
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get categoryId => integer().references(
        Categories,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  /// Normalised to first day of month at 00:00 local time.
  DateTimeColumn get monthStart => dateTime()();

  IntColumn get limitAmount => integer()();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'CHECK (limit_amount > 0)',
        'UNIQUE (category_id, month_start)',
      ];
}
