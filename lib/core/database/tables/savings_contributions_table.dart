import 'package:drift/drift.dart';

import '../enums.dart';
import 'accounts_table.dart';
import 'savings_goals_table.dart';

/// Savings deposits/withdrawals linked to both a savings goal and a financial
/// account. Balance logic: deposit reduces available account balance;
/// withdrawal increases it. Goal balance is the signed sum of ledger rows.
@DataClassName('SavingsContribution')
@TableIndex(name: 'idx_savings_contributions_goal_date', columns: {#goalId, #contributionDate})
@TableIndex(name: 'idx_savings_contributions_account_date', columns: {#accountId, #contributionDate})
class SavingsContributions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get goalId => integer().references(
        SavingsGoals,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  IntColumn get accountId => integer().references(
        Accounts,
        #id,
        onDelete: KeyAction.restrict,
        onUpdate: KeyAction.cascade,
      )();

  TextColumn get type => textEnum<SavingsEntryType>()();

  IntColumn get amount => integer()();

  DateTimeColumn get contributionDate => dateTime()();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'CHECK (amount > 0)',
        "CHECK (type IN ('deposit', 'withdrawal'))",
      ];
}
