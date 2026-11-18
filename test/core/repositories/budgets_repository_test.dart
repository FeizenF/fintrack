import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/budgets_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/errors/app_exception.dart';

void main() {
  late AppDatabase db;
  late int accountId;
  late int foodCategoryId;
  late int transportCategoryId;
  late BudgetsRepository budgets;
  late TransactionsRepository transactions;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    accountId = await AccountsRepository(
      db,
    ).create(name: 'Dompet', type: AccountType.cash, initialBalance: 1000000);
    final List<Category> expenseCategories = await CategoriesRepository(db)
        .list(kind: CategoryKind.expense);
    foodCategoryId = expenseCategories
        .firstWhere((category) => category.name == 'Makanan')
        .id;
    transportCategoryId = expenseCategories
        .firstWhere((category) => category.name == 'Transportasi')
        .id;
    budgets = BudgetsRepository(db);
    transactions = TransactionsRepository(db);
  });

  tearDown(() => db.close());

  test('monthly budget reports expense total and remaining amount', () async {
    final DateTime month = DateTime(2026, 5);
    await budgets.create(
      categoryId: foodCategoryId,
      monthStart: month,
      limitAmount: 300000,
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: foodCategoryId,
      amount: 125000,
      date: DateTime(2026, 5, 2),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: foodCategoryId,
      amount: 50000,
      date: DateTime(2026, 6, 1),
    );

    final List<BudgetProgress> rows = await budgets.list(month);

    expect(rows, hasLength(1));
    expect(rows.single.spent, 125000);
    expect(rows.single.remaining, 175000);
    expect(rows.single.ratio, closeTo(125000 / 300000, 0.0001));
  });

  test('budget flags near-limit and exceeded states', () async {
    await budgets.create(
      categoryId: foodCategoryId,
      monthStart: DateTime(2026, 5),
      limitAmount: 100000,
    );
    await budgets.create(
      categoryId: transportCategoryId,
      monthStart: DateTime(2026, 5),
      limitAmount: 100000,
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: foodCategoryId,
      amount: 80000,
      date: DateTime(2026, 5, 2),
    );
    await transactions.createExpense(
      accountId: accountId,
      categoryId: transportCategoryId,
      amount: 120000,
      date: DateTime(2026, 5, 2),
    );

    final List<BudgetProgress> rows = await budgets.list(DateTime(2026, 5));
    final BudgetProgress food = rows.firstWhere(
      (row) => row.budget.categoryId == foodCategoryId,
    );
    final BudgetProgress transport = rows.firstWhere(
      (row) => row.budget.categoryId == transportCategoryId,
    );
    expect(food.isNearLimit, isTrue);
    expect(food.isExceeded, isFalse);
    expect(transport.isNearLimit, isFalse);
    expect(transport.isExceeded, isTrue);
    expect(transport.remaining, -20000);
  });

  test('budget rejects income category and duplicate month/category', () async {
    final int incomeId = (await CategoriesRepository(
      db,
    ).list(kind: CategoryKind.income)).first.id;

    await expectLater(
      budgets.create(
        categoryId: incomeId,
        monthStart: DateTime(2026, 5),
        limitAmount: 100000,
      ),
      throwsA(isA<ValidationException>()),
    );

    await budgets.create(
      categoryId: foodCategoryId,
      monthStart: DateTime(2026, 5, 18),
      limitAmount: 100000,
    );
    await expectLater(
      budgets.create(
        categoryId: foodCategoryId,
        monthStart: DateTime(2026, 5),
        limitAmount: 200000,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('budget rejects non-positive limits', () async {
    await expectLater(
      budgets.create(
        categoryId: foodCategoryId,
        monthStart: DateTime(2026, 5),
        limitAmount: 0,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('copy from previous month skips existing budgets', () async {
    await budgets.create(
      categoryId: foodCategoryId,
      monthStart: DateTime(2026, 4),
      limitAmount: 150000,
    );
    await budgets.create(
      categoryId: transportCategoryId,
      monthStart: DateTime(2026, 4),
      limitAmount: 200000,
    );
    await budgets.create(
      categoryId: foodCategoryId,
      monthStart: DateTime(2026, 5),
      limitAmount: 300000,
    );

    final int copied = await budgets.copyFromPreviousMonth(
      DateTime(2026, 5, 9),
    );
    final List<BudgetProgress> rows = await budgets.list(DateTime(2026, 5));

    expect(copied, 1);
    expect(rows, hasLength(2));
    expect(
      rows.firstWhere((row) => row.budget.categoryId == foodCategoryId).limit,
      300000,
    );
    expect(
      rows
          .firstWhere((row) => row.budget.categoryId == transportCategoryId)
          .limit,
      200000,
    );
  });
}
