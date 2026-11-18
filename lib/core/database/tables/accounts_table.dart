import 'package:drift/drift.dart';

import '../enums.dart';

/// Financial accounts owned by the single app user.
///
/// `initialBalance` is the balance before any transaction. The current balance
/// is always derived from `initialBalance` plus the transaction and savings
/// ledger (see `AccountRepository`), never stored, so it cannot drift.
@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get type => textEnum<AccountType>()();

  IntColumn get initialBalance => integer().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();

  /// Archived accounts stay visible in reports but cannot receive new entries.
  BoolColumn get isArchived =>
      boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => <String>[
        'UNIQUE (name)',
        'CHECK (length(trim(name)) > 0)',
        'CHECK (initial_balance >= 0)',
        "CHECK (type IN ('cash', 'bank', 'eWallet', 'businessCash', 'other'))",
      ];
}
