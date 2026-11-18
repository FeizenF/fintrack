import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AccountBalanceCalculator calculator;

  setUp(() {
    db = AppDatabase.forTesting();
    calculator = AccountBalanceCalculator(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createAccount({
    required String name,
    int initialBalance = 0,
    AccountType type = AccountType.cash,
    bool archived = false,
  }) {
    return db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            initialBalance: Value(initialBalance),
            isArchived: Value(archived),
          ),
        );
  }

  Future<int> categoryId(String name, CategoryKind kind) async {
    final Category row =
        await (db.select(db.categories)
              ..where((t) => t.name.equals(name) & t.kind.equalsValue(kind)))
            .getSingle();
    return row.id;
  }

  group('account balance', () {
    test('equals the initial balance when the ledger is empty', () async {
      final int id = await createAccount(
        name: 'Dompet',
        initialBalance: 250000,
      );

      final AccountBalance balance = (await calculator.forAccount(id))!;

      expect(balance.currentBalance, 250000);
      expect(balance.income, 0);
      expect(balance.expense, 0);
    });

    test(
      'adds income and subtracts expenses without double counting',
      () async {
        final int account = await createAccount(
          name: 'Dompet',
          initialBalance: 100000,
        );
        final int salary = await categoryId('Gaji', CategoryKind.income);
        final int food = await categoryId('Makanan', CategoryKind.expense);

        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.income,
                accountId: account,
                categoryId: Value(salary),
                amount: 500000,
                transactionDate: DateTime(2026, 1, 2),
              ),
            );
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                type: TransactionType.expense,
                accountId: account,
                categoryId: Value(food),
                amount: 125000,
                transactionDate: DateTime(2026, 1, 3),
              ),
            );

        final AccountBalance balance = (await calculator.forAccount(account))!;

        expect(balance.income, 500000);
        expect(balance.expense, 125000);
        expect(balance.currentBalance, 475000);
      },
    );

    test('moves money between accounts on transfer exactly once', () async {
      final int cash = await createAccount(
        name: 'Tunai',
        initialBalance: 300000,
      );
      final int bank = await createAccount(name: 'BCA', initialBalance: 0);

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.transfer,
              accountId: cash,
              toAccountId: Value(bank),
              amount: 200000,
              transactionDate: DateTime(2026, 1, 4),
            ),
          );

      final AccountBalance cashBalance = (await calculator.forAccount(cash))!;
      final AccountBalance bankBalance = (await calculator.forAccount(bank))!;

      expect(cashBalance.currentBalance, 100000);
      expect(cashBalance.transferOut, 200000);
      expect(cashBalance.transferIn, 0);
      expect(bankBalance.currentBalance, 200000);
      expect(bankBalance.transferIn, 200000);
      expect(bankBalance.transferOut, 0);

      expect(
        cashBalance.currentBalance + bankBalance.currentBalance,
        300000,
        reason: 'a transfer must conserve total money',
      );
    });

    test('debits savings deposits and credits savings withdrawals', () async {
      final int account = await createAccount(
        name: 'Dompet',
        initialBalance: 1000000,
      );
      final int goal = await db
          .into(db.savingsGoals)
          .insert(
            SavingsGoalsCompanion.insert(
              name: 'Dana darurat',
              targetAmount: 5000000,
            ),
          );

      await db
          .into(db.savingsContributions)
          .insert(
            SavingsContributionsCompanion.insert(
              goalId: goal,
              accountId: account,
              type: SavingsEntryType.deposit,
              amount: 400000,
              contributionDate: DateTime(2026, 1, 5),
            ),
          );
      await db
          .into(db.savingsContributions)
          .insert(
            SavingsContributionsCompanion.insert(
              goalId: goal,
              accountId: account,
              type: SavingsEntryType.withdrawal,
              amount: 100000,
              contributionDate: DateTime(2026, 1, 6),
            ),
          );

      final AccountBalance balance = (await calculator.forAccount(account))!;

      expect(balance.savingsDeposit, 400000);
      expect(balance.savingsWithdrawal, 100000);
      expect(balance.currentBalance, 700000);
    });

    test('separates accounts and keeps the wallet total consistent', () async {
      final int cash = await createAccount(
        name: 'Tunai',
        initialBalance: 50000,
      );
      final int bank = await createAccount(name: 'BRI', initialBalance: 750000);

      final WalletBalance wallet = await calculator.wallet();

      expect(wallet.accounts, hasLength(2));
      expect(wallet.total, 800000);
      expect(await calculator.totalBalance(), 800000);

      final AccountBalance cashBalance = (await calculator.forAccount(cash))!;
      final AccountBalance bankBalance = (await calculator.forAccount(bank))!;
      expect(
        cashBalance.currentBalance + bankBalance.currentBalance,
        wallet.total,
      );
    });

    test('excludes archived accounts by default', () async {
      await createAccount(name: 'Aktif', initialBalance: 100000);
      await createAccount(name: 'Lama', initialBalance: 900000, archived: true);

      final List<AccountBalance> visible = await calculator.all();
      final List<AccountBalance> everything = await calculator.all(
        includeArchived: true,
      );

      expect(visible, hasLength(1));
      expect(everything, hasLength(2));
      expect(await calculator.totalBalance(), 100000);
    });

    test('includes archived accounts when queried by ID', () async {
      final int archivedId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Akun lama',
              type: AccountType.bank,
              initialBalance: const Value(42000),
              isArchived: const Value(true),
            ),
          );

      final AccountBalance? balance = await calculator.forAccount(archivedId);

      expect(balance, isNotNull);
      expect(balance!.currentBalance, 42000);
    });

    test('returns null for an account that does not exist', () async {
      expect(await calculator.forAccount(4242), isNull);
    });

    test('recomputes after a transaction is deleted', () async {
      final int account = await createAccount(
        name: 'Dompet',
        initialBalance: 100000,
      );
      final int food = await categoryId('Makanan', CategoryKind.expense);

      final int txId = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.expense,
              accountId: account,
              categoryId: Value(food),
              amount: 40000,
              transactionDate: DateTime(2026, 1, 7),
            ),
          );

      expect((await calculator.forAccount(account))!.currentBalance, 60000);

      await (db.delete(db.transactions)..where((t) => t.id.equals(txId))).go();

      expect((await calculator.forAccount(account))!.currentBalance, 100000);
    });
  });
}
