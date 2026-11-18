import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/errors/app_exception.dart';
import 'package:fintrack/core/utils/date_range.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AccountsRepository accounts;
  late CategoriesRepository categories;
  late TransactionsRepository transactions;
  late int accountId;
  late int otherAccountId;

  setUp(() async {
    db = AppDatabase.forTesting();
    accounts = AccountsRepository(db);
    categories = CategoriesRepository(db);
    transactions = TransactionsRepository(db);

    accountId = await accounts.create(
      name: 'Dompet',
      type: AccountType.cash,
      initialBalance: 1000000,
    );
    otherAccountId = await accounts.create(name: 'BCA', type: AccountType.bank);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> category(String name, CategoryKind kind) async {
    final Category row =
        await (db.select(db.categories)
              ..where((t) => t.name.equals(name) & t.kind.equalsValue(kind)))
            .getSingle();
    return row.id;
  }

  group('categories repository', () {
    test('seeds both kinds and splits them by kind', () async {
      final List<Category> income = await categories.list(
        kind: CategoryKind.income,
      );
      final List<Category> expense = await categories.list(
        kind: CategoryKind.expense,
      );

      expect(income.map((c) => c.name), contains('Gaji'));
      expect(expense.map((c) => c.name), contains('Makanan'));
      expect(income.every((c) => c.kind == CategoryKind.income), isTrue);
      expect(expense.every((c) => c.kind == CategoryKind.expense), isTrue);
    });

    test('creates a custom category', () async {
      final int id = await categories.create(
        name: 'Kopi',
        kind: CategoryKind.expense,
        iconKey: 'coffee',
        colorValue: 0xFF8D6E63,
      );

      final Category created = (await categories.byId(id))!;
      expect(created.name, 'Kopi');
      expect(created.isDefault, isFalse);
      expect(created.iconKey, 'coffee');
    });

    test('rejects a duplicate name within the same kind', () async {
      await categories.create(name: 'Kopi', kind: CategoryKind.expense);

      expect(
        () => categories.create(name: 'Kopi', kind: CategoryKind.expense),
        throwsA(isA<ValidationException>()),
      );
    });

    test('allows the same name in the other kind', () async {
      await categories.create(
        name: 'Lainnya khusus',
        kind: CategoryKind.expense,
      );

      final int incomeId = await categories.create(
        name: 'Lainnya khusus',
        kind: CategoryKind.income,
      );

      expect((await categories.byId(incomeId))!.kind, CategoryKind.income);
    });

    test('rejects renaming a default category', () async {
      final int defaultId = await category('Gaji', CategoryKind.income);

      expect(
        () => categories.update(defaultId, name: 'Gaji Baru'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('default'),
          ),
        ),
      );
    });

    test('archives a category instead of deleting it', () async {
      final int id = await categories.create(
        name: 'Kopi',
        kind: CategoryKind.expense,
      );

      await categories.setArchived(id, true);

      expect(
        await categories.list(kind: CategoryKind.expense),
        isNot(contains(predicate((Category c) => c.id == id))),
      );
      expect(
        (await categories.list(kind: CategoryKind.expense)).length,
        defaultExpenseCountWithoutKopi,
      );
    });

    test('refuses to delete a default category', () async {
      final int defaultId = await category('Makanan', CategoryKind.expense);

      expect(
        () => categories.delete(defaultId),
        throwsA(isA<ValidationException>()),
      );
    });

    test('refuses to delete a category used by a transaction', () async {
      final int id = await categories.create(
        name: 'Kopi',
        kind: CategoryKind.expense,
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: id,
        amount: 25000,
        date: DateTime(2026, 1, 5),
      );

      expect(() => categories.delete(id), throwsA(isA<ValidationException>()));
    });

    test('deletes an unused custom category', () async {
      final int id = await categories.create(
        name: 'Kopi',
        kind: CategoryKind.expense,
      );

      await categories.delete(id);

      expect(await categories.byId(id), isNull);
    });
  });

  group('transaction repository', () {
    test('creates an expense and stores integer Rupiah', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);

      final int id = await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 35000,
        date: DateTime(2026, 1, 5, 12, 30),
        note: '  Makan siang  ',
      );

      final FinancialTransaction row = (await transactions.byId(id))!;
      expect(row.type, TransactionType.expense);
      expect(row.amount, 35000);
      expect(row.note, 'Makan siang');
      expect(row.categoryId, foodId);
      expect(row.toAccountId, isNull);
    });

    test('rejects a zero amount', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);

      expect(
        () => transactions.createExpense(
          accountId: accountId,
          categoryId: foodId,
          amount: 0,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Nominal'),
          ),
        ),
      );
    });

    test('rejects an income category on an expense', () async {
      final int salaryId = await category('Gaji', CategoryKind.income);

      expect(
        () => transactions.createExpense(
          accountId: accountId,
          categoryId: salaryId,
          amount: 10000,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a missing account or category', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);

      expect(
        () => transactions.createExpense(
          accountId: 999,
          categoryId: foodId,
          amount: 10000,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => transactions.createExpense(
          accountId: accountId,
          categoryId: 999,
          amount: 10000,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects writing to an archived account', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);
      await accounts.setArchived(accountId, true);

      expect(
        () => transactions.createExpense(
          accountId: accountId,
          categoryId: foodId,
          amount: 10000,
          date: DateTime(2026, 1, 5),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('diarsipkan'),
          ),
        ),
      );
    });

    test('creates a transfer between two accounts', () async {
      final int id = await transactions.createTransfer(
        fromAccountId: accountId,
        toAccountId: otherAccountId,
        amount: 250000,
        date: DateTime(2026, 1, 6),
      );

      final FinancialTransaction row = (await transactions.byId(id))!;
      expect(row.type, TransactionType.transfer);
      expect(row.accountId, accountId);
      expect(row.toAccountId, otherAccountId);
      expect(row.categoryId, isNull);
    });

    test('rejects a transfer to the same account', () async {
      expect(
        () => transactions.createTransfer(
          fromAccountId: accountId,
          toAccountId: accountId,
          amount: 1000,
          date: DateTime(2026, 1, 6),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('berbeda'),
          ),
        ),
      );
    });

    test('updates a transaction and keeps the type invariants', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);
      final int transportId = await category(
        'Transportasi',
        CategoryKind.expense,
      );

      final int id = await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 20000,
        date: DateTime(2026, 1, 5),
      );

      await transactions.updateExpense(
        id,
        accountId: otherAccountId,
        categoryId: transportId,
        amount: 45000,
        date: DateTime(2026, 1, 8),
        note: 'Ojek',
      );

      final FinancialTransaction row = (await transactions.byId(id))!;
      expect(row.accountId, otherAccountId);
      expect(row.categoryId, transportId);
      expect(row.amount, 45000);
      expect(row.note, 'Ojek');
      expect(row.type, TransactionType.expense);
    });

    test('rejects updating a missing transaction', () async {
      expect(
        () => transactions.delete(4242),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('deletes a transaction', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);
      final int id = await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 20000,
        date: DateTime(2026, 1, 5),
      );

      await transactions.delete(id);

      expect(await transactions.byId(id), isNull);
    });

    test('filters by date range, type and account', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);
      final int salaryId = await category('Gaji', CategoryKind.income);

      await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 10000,
        date: DateTime(2026, 1, 5),
      );
      await transactions.createIncome(
        accountId: accountId,
        categoryId: salaryId,
        amount: 500000,
        date: DateTime(2026, 2, 5),
      );
      await transactions.createTransfer(
        fromAccountId: accountId,
        toAccountId: otherAccountId,
        amount: 50000,
        date: DateTime(2026, 1, 20),
      );

      final List<FinancialTransaction> january = await transactions.list(
        range: DateRange(start: DateTime(2026, 1), end: DateTime(2026, 2)),
      );
      final List<FinancialTransaction> expensesOnly = await transactions.list(
        type: TransactionType.expense,
      );
      final List<FinancialTransaction> byAccount = await transactions.list(
        accountId: otherAccountId,
      );

      expect(january, hasLength(2));
      expect(expensesOnly.single.amount, 10000);
      expect(byAccount.single.type, TransactionType.transfer);
    });

    test('searches notes and category names case-insensitively', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);

      await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 25000,
        date: DateTime(2026, 1, 5),
        note: 'Nasi Padang',
      );

      final List<FinancialTransaction> byNote = await transactions.list(
        search: 'padang',
      );
      final List<FinancialTransaction> byCategory = await transactions.list(
        search: 'makan',
      );

      expect(byNote, hasLength(1));
      expect(byCategory, hasLength(1));
    });

    test('orders newest transaction date first', () async {
      final int foodId = await category('Makanan', CategoryKind.expense);

      await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 10000,
        date: DateTime(2026, 1, 5),
      );
      await transactions.createExpense(
        accountId: accountId,
        categoryId: foodId,
        amount: 10000,
        date: DateTime(2026, 3, 5),
      );

      final List<FinancialTransaction> rows = await transactions.list();

      expect(rows.first.transactionDate, DateTime(2026, 3, 5));
    });
  });
}

/// Expense categories seeded by default, used by the archive test.
const int defaultExpenseCountWithoutKopi = 9;
