import 'package:drift/drift.dart';

/// User-defined savings targets. Contributions live in a separate ledger so
/// deposits/withdrawals affect account balance exactly once.
@DataClassName('SavingsGoal')
@TableIndex(name: 'idx_savings_goals_active', columns: {#isArchived, #targetDate})
class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 80)();

  IntColumn get targetAmount => integer()();

  DateTimeColumn get targetDate => dateTime().nullable()();

  TextColumn get note => text().nullable()();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'CHECK (target_amount > 0)',
        'CHECK (length(trim(name)) > 0)',
      ];
}
