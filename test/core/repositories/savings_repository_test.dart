import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/savings_repository.dart';
import 'package:fintrack/core/errors/app_exception.dart';

void main() {
  late AppDatabase db;
  late int accountId;
  late SavingsRepository savings;
  late AccountBalanceCalculator balances;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    accountId = await AccountsRepository(
      db,
    ).create(name: 'Dompet', type: AccountType.cash, initialBalance: 1000000);
    savings = SavingsRepository(db);
    balances = AccountBalanceCalculator(db);
  });

  tearDown(() => db.close());

  test('goal progress is the signed sum of its contributions', () async {
    final int goalId = await savings.createGoal(
      name: 'Dana darurat',
      targetAmount: 5000000,
      targetDate: DateTime(2027, 1),
    );

    await savings.deposit(
      goalId: goalId,
      accountId: accountId,
      amount: 250000,
      date: DateTime(2026, 3, 1),
    );
    await savings.deposit(
      goalId: goalId,
      accountId: accountId,
      amount: 150000,
      date: DateTime(2026, 3, 2),
    );
    await savings.withdraw(
      goalId: goalId,
      accountId: accountId,
      amount: 50000,
      date: DateTime(2026, 3, 3),
    );

    final SavingsProgress progress = (await savings.progress()).single;
    expect(progress.goal.id, goalId);
    expect(progress.saved, 350000);
    expect(progress.remaining, 4650000);
    expect(progress.ratio, closeTo(350000 / 5000000, 0.0001));
  });

  test('deposits reduce and withdrawals restore the account balance', () async {
    final int goalId = await savings.createGoal(
      name: 'Laptop baru',
      targetAmount: 10000000,
    );

    await savings.deposit(
      goalId: goalId,
      accountId: accountId,
      amount: 400000,
      date: DateTime(2026, 3, 1),
    );
    expect((await balances.forAccount(accountId))!.currentBalance, 600000);

    await savings.withdraw(
      goalId: goalId,
      accountId: accountId,
      amount: 100000,
      date: DateTime(2026, 3, 2),
    );
    expect((await balances.forAccount(accountId))!.currentBalance, 700000);

    await expectLater(
      savings.withdraw(
        goalId: goalId,
        accountId: accountId,
        amount: 400000,
        date: DateTime(2026, 3, 3),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect((await balances.forAccount(accountId))!.currentBalance, 700000);
    expect((await savings.progress()).single.saved, 300000);
  });

  test('goal rejects non-positive target and blank name', () async {
    await expectLater(
      savings.createGoal(name: '   ', targetAmount: 1000),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      savings.createGoal(name: 'Target', targetAmount: 0),
      throwsA(isA<ValidationException>()),
    );
  });

  test('contribution rejects a non-positive amount', () async {
    final int goalId = await savings.createGoal(
      name: 'Modal usaha',
      targetAmount: 2000000,
    );

    await expectLater(
      savings.deposit(
        goalId: goalId,
        accountId: accountId,
        amount: 0,
        date: DateTime(2026, 3, 1),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
    'goal with contributions cannot be deleted but can be archived',
    () async {
      final int goalId = await savings.createGoal(
        name: 'Tabungan pribadi',
        targetAmount: 1000000,
      );
      await savings.deposit(
        goalId: goalId,
        accountId: accountId,
        amount: 100000,
        date: DateTime(2026, 3, 1),
      );

      await expectLater(
        savings.deleteGoal(goalId),
        throwsA(isA<ValidationException>()),
      );

      await savings.setGoalArchived(goalId, true);
      expect(await savings.progress(), isEmpty);
    },
  );

  test('progress excludes archived goals by default', () async {
    final int activeId = await savings.createGoal(
      name: 'Aktif',
      targetAmount: 1000000,
    );
    final int archivedId = await savings.createGoal(
      name: 'Arsip',
      targetAmount: 1000000,
    );
    await savings.setGoalArchived(archivedId, true);

    expect((await savings.progress()).map((row) => row.goal.id), <int>[
      activeId,
    ]);
    expect((await savings.progress(includeArchived: true)).length, 2);
  });
}
