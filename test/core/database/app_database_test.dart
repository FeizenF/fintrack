import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/seed/default_data.dart';

void main() {
  // Tests intentionally open several database instances in the same process
  // (close/reopen flows), so Drift's multiple-instance warning is noise here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  group('schema bootstrap', () {
    test('creates every required table', () async {
      final List<QueryRow> rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          )
          .get();

      final Set<String> tables = rows
          .map((QueryRow row) => row.read<String>('name'))
          .toSet();

      expect(
        tables,
        containsAll(<String>[
          'accounts',
          'app_settings',
          'budgets',
          'categories',
          'savings_contributions',
          'savings_goals',
          'transactions',
        ]),
      );
    });

    test('reports the current schema version', () async {
      expect(db.schemaVersion, appDatabaseSchemaVersion);
      expect(db.schemaVersion, greaterThanOrEqualTo(3));
    });

    test('declares the expected indexes for query performance', () async {
      final List<QueryRow> rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_%' ORDER BY name",
          )
          .get();

      final Set<String> indexes = rows
          .map((QueryRow row) => row.read<String>('name'))
          .toSet();

      expect(
        indexes,
        containsAll(<String>[
          'idx_categories_kind',
          'idx_transactions_date',
          'idx_transactions_account_date',
          'idx_transactions_category_date',
          'idx_transactions_type_date',
          'idx_transactions_to_account_date',
          'idx_budgets_month',
          'idx_budgets_category_month',
          'idx_savings_goals_active',
          'idx_savings_contributions_goal_date',
          'idx_savings_contributions_account_date',
        ]),
      );
    });

    test('enables foreign key enforcement on every connection', () async {
      final QueryRow row = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(row.data.values.first, 1);
    });

    test('installs the category-kind integrity triggers', () async {
      final List<QueryRow> rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name LIKE 'trg_transactions_category_kind_%' ORDER BY name",
          )
          .get();

      expect(
        rows.map((QueryRow row) => row.read<String>('name')).toList(),
        <String>[
          'trg_transactions_category_kind_insert',
          'trg_transactions_category_kind_update',
        ],
      );
    });
  });

  group('seed data', () {
    test('seeds the default income and expense categories', () async {
      final List<Category> categories = await db.select(db.categories).get();

      final Set<String> income = categories
          .where((Category c) => c.kind == CategoryKind.income)
          .map((Category c) => c.name)
          .toSet();
      final Set<String> expense = categories
          .where((Category c) => c.kind == CategoryKind.expense)
          .map((Category c) => c.name)
          .toSet();

      expect(income, containsAll(defaultIncomeCategoryNames));
      expect(expense, containsAll(defaultExpenseCategoryNames));
      expect(income.length, defaultIncomeCategoryNames.length);
      expect(expense.length, defaultExpenseCategoryNames.length);
    }, skip: false);

    test('marks seeded categories as default', () async {
      final List<Category> categories = await db.select(db.categories).get();
      expect(categories.every((Category c) => c.isDefault), isTrue);
      expect(categories.every((Category c) => !c.isArchived), isTrue);
    });

    test('seeding is idempotent across repeated opens', () async {
      await db.ensureSeeded();
      await db.ensureSeeded();
      final int count = await db
          .customSelect('SELECT COUNT(*) AS c FROM categories')
          .map((QueryRow row) => row.read<int>('c'))
          .getSingle();
      expect(
        count,
        defaultIncomeCategoryNames.length + defaultExpenseCategoryNames.length,
      );
    });
  });

  group('account constraints', () {
    test('rejects duplicate account names', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'Cash', type: AccountType.cash),
          );

      expect(
        () => db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(name: 'Cash', type: AccountType.bank),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects blank account names', () async {
      expect(
        () => db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(name: '   ', type: AccountType.cash),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'rejects a negative initial balance at the database boundary',
      () async {
        expect(
          () => db
              .into(db.accounts)
              .insert(
                AccountsCompanion.insert(
                  name: 'Debt',
                  type: AccountType.cash,
                  initialBalance: const Value(-1),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('stores the enum type as readable text', () async {
      final int id = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'BCA',
              type: AccountType.bank,
              initialBalance: const Value(500000),
            ),
          );

      final QueryRow row = await db
          .customSelect(
            'SELECT type FROM accounts WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(id)],
          )
          .getSingle();

      expect(row.read<String>('type'), 'bank');
    });
  });

  group('transaction constraints', () {
    late int cashId;
    late int salaryId;

    setUp(() async {
      cashId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'Cash', type: AccountType.cash),
          );
      salaryId = await db
          .customSelect(
            "SELECT id FROM categories WHERE name = 'Gaji' AND kind = 'income'",
          )
          .map((QueryRow row) => row.read<int>('id'))
          .getSingle();
    });

    test('rejects amounts that are not greater than zero', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.income,
                accountId: cashId,
                categoryId: Value(salaryId),
                amount: 0,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects an expense row using an income category', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.expense,
                accountId: cashId,
                categoryId: Value(salaryId),
                amount: 10000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects an income row that names a destination account', () async {
      final int otherId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'BRI', type: AccountType.bank),
          );

      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.income,
                accountId: cashId,
                categoryId: Value(salaryId),
                toAccountId: Value(otherId),
                amount: 10000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a transfer that carries a category', () async {
      final int otherId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'BRI', type: AccountType.bank),
          );

      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.transfer,
                accountId: cashId,
                categoryId: Value(salaryId),
                toAccountId: Value(otherId),
                amount: 10000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a transfer to the same account', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.transfer,
                accountId: cashId,
                toAccountId: Value(cashId),
                amount: 10000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a transfer without a destination account', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.transfer,
                accountId: cashId,
                amount: 10000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('accepts a valid transfer row', () async {
      final int otherId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'BRI', type: AccountType.bank),
          );

      final int id = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.transfer,
              accountId: cashId,
              toAccountId: Value(otherId),
              amount: 25000,
              transactionDate: DateTime(2026, 1, 1),
            ),
          );

      final FinancialTransaction row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.type, TransactionType.transfer);
      expect(row.categoryId, isNull);
      expect(row.amount, 25000);
    });

    test('rejects a transaction pointing at a missing account', () async {
      expect(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.income,
                accountId: 9999,
                categoryId: Value(salaryId),
                amount: 1000,
                transactionDate: DateTime(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('restricts deleting an account that still has transactions', () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.income,
              accountId: cashId,
              categoryId: Value(salaryId),
              amount: 1000,
              transactionDate: DateTime(2026, 1, 1),
            ),
          );

      expect(
        () => (db.delete(db.accounts)..where((t) => t.id.equals(cashId))).go(),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('budget constraints', () {
    test('rejects duplicate budget for the same category and month', () async {
      final int expenseId = await db
          .customSelect(
            "SELECT id FROM categories WHERE kind = 'expense' LIMIT 1",
          )
          .map((QueryRow row) => row.read<int>('id'))
          .getSingle();

      final DateTime month = DateTime(2026, 2);

      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: expenseId,
              monthStart: month,
              limitAmount: 500000,
            ),
          );

      expect(
        () => db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: expenseId,
                monthStart: month,
                limitAmount: 750000,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a non-positive limit', () async {
      final int expenseId = await db
          .customSelect(
            "SELECT id FROM categories WHERE kind = 'expense' LIMIT 1",
          )
          .map((QueryRow row) => row.read<int>('id'))
          .getSingle();

      expect(
        () => db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: expenseId,
                monthStart: DateTime(2026, 3),
                limitAmount: -1,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('savings constraints', () {
    test('rejects a non-positive contribution', () async {
      final int accountId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'Cash', type: AccountType.cash),
          );
      final int goalId = await db
          .into(db.savingsGoals)
          .insert(
            SavingsGoalsCompanion.insert(
              name: 'Dana darurat',
              targetAmount: 10000000,
            ),
          );

      expect(
        () => db
            .into(db.savingsContributions)
            .insert(
              SavingsContributionsCompanion.insert(
                goalId: goalId,
                accountId: accountId,
                type: SavingsEntryType.deposit,
                amount: 0,
                contributionDate: DateTime(2026, 1, 5),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects a non-positive savings target', () async {
      expect(
        () => db
            .into(db.savingsGoals)
            .insert(
              SavingsGoalsCompanion.insert(name: 'Laptop', targetAmount: 0),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('app_settings', () {
    test('upserts a setting by key', () async {
      await db.saveSetting('theme_mode', 'dark');
      await db.saveSetting('theme_mode', 'light');

      expect(await db.readSetting('theme_mode'), 'light');
      final int count = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM app_settings WHERE key = 'theme_mode'",
          )
          .map((QueryRow row) => row.read<int>('c'))
          .getSingle();
      expect(count, 1);
    });

    test('returns null for an unknown key', () async {
      expect(await db.readSetting('missing'), isNull);
    });
  });

  group('migration and persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fintrack_db_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists rows across close and reopen without re-seeding', () async {
      final File file = File(p.join(tempDir.path, 'fintrack.sqlite'));

      final AppDatabase first = AppDatabase.atFile(file);
      await first.customSelect('SELECT 1').get();
      final int seeded = await first.categories.count().getSingle();
      final int accountId = await first
          .into(first.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Dompet',
              type: AccountType.cash,
              initialBalance: const Value(150000),
            ),
          );
      await first.close();

      final AppDatabase second = AppDatabase.atFile(file);
      await second.customSelect('SELECT 1').get();
      final List<Account> accounts = await second.select(second.accounts).get();
      final int reseeded = await second.categories.count().getSingle();
      await second.close();

      expect(accounts.single.id, accountId);
      expect(accounts.single.initialBalance, 150000);
      expect(reseeded, seeded, reason: 'seed must not run a second time');
    });

    test(
      'upgrades schema version 1 by installing category-kind triggers',
      () async {
        final File file = File(p.join(tempDir.path, 'fintrack.sqlite'));
        final AppDatabase versionOne = AppDatabase.atFile(file);
        await versionOne.customSelect('SELECT 1').get();
        final int accountId = await versionOne
            .into(versionOne.accounts)
            .insert(
              AccountsCompanion.insert(name: 'Cash', type: AccountType.cash),
            );
        final Category salary = await (versionOne.select(
          versionOne.categories,
        )..where((t) => t.name.equals('Gaji'))).getSingle();
        await versionOne.customStatement(
          'DROP TRIGGER trg_transactions_category_kind_insert',
        );
        await versionOne.customStatement(
          'DROP TRIGGER trg_transactions_category_kind_update',
        );
        await versionOne.customStatement(
          'DROP INDEX idx_transactions_to_account_date',
        );
        await versionOne.customStatement('PRAGMA user_version = 1');
        await versionOne.close();

        final AppDatabase upgraded = AppDatabase.atFile(file);
        await upgraded.customSelect('SELECT 1').get();
        expect(upgraded.schemaVersion, 3);
        expect(
          () => upgraded
              .into(upgraded.transactions)
              .insert(
                TransactionsCompanion.insert(
                  type: TransactionType.expense,
                  accountId: accountId,
                  categoryId: Value(salary.id),
                  amount: 10000,
                  transactionDate: DateTime(2026, 1, 1),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
        await upgraded.close();
      },
    );

    test('keeps foreign keys enforced after reopening', () async {
      final File file = File(p.join(tempDir.path, 'fintrack.sqlite'));

      final AppDatabase first = AppDatabase.atFile(file);
      await first.customSelect('SELECT 1').get();
      await first.close();

      final AppDatabase second = AppDatabase.atFile(file);
      final QueryRow row = await second
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      await second.close();

      expect(row.data.values.first, 1);
    });

    test('enables write-ahead logging for the file database', () async {
      final File file = File(p.join(tempDir.path, 'fintrack.sqlite'));
      final AppDatabase database = AppDatabase.atFile(file);
      final QueryRow row = await database
          .customSelect('PRAGMA journal_mode')
          .getSingle();
      await database.close();

      expect(row.read<String>('journal_mode').toLowerCase(), 'wal');
    });

    test('round-trips every enum value through text storage', () async {
      for (final AccountType type in AccountType.values) {
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(name: 'Acc ${type.name}', type: type),
            );
      }

      final List<Account> stored = await db.select(db.accounts).get();
      final Set<AccountType> types = stored.map((Account c) => c.type).toSet();

      expect(types, AccountType.values.toSet());
    });
  });
}
