import 'package:drift/drift.dart';

import '../enums.dart';

/// Income and expense categories. Defaults are seeded on first launch and
/// cannot be deleted, only archived.
@DataClassName('Category')
@TableIndex(name: 'idx_categories_kind', columns: {#kind})
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get kind => textEnum<CategoryKind>()();

  /// Icon key understood by the presentation layer, e.g. `restaurant`.
  TextColumn get iconKey => text().nullable()();

  /// ARGB color value for charts and chips.
  IntColumn get colorValue => integer().nullable()();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isArchived =>
      boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'UNIQUE (name, kind)',
        'CHECK (length(trim(name)) > 0)',
        "CHECK (kind IN ('income', 'expense'))",
      ];
}
