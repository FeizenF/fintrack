import 'package:drift/drift.dart';

/// Local application preferences. Values are versioned JSON primitives; do
/// not store secrets here (PIN hashes / keys belong in secure storage).
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 100)();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}
