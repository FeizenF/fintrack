import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/errors/app_exception.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late AccountsRepository repository;

  setUp(() {
    db = AppDatabase.forTesting();
    repository = AccountsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('accounts repository', () {
    test('creates an account and lists it', () async {
      final int id = await repository.create(
        name: 'Dompet',
        type: AccountType.cash,
        initialBalance: 125000,
      );

      final List<Account> accounts = await repository.list();

      expect(accounts, hasLength(1));
      expect(accounts.single.id, id);
      expect(accounts.single.name, 'Dompet');
      expect(accounts.single.type, AccountType.cash);
      expect(accounts.single.initialBalance, 125000);
      expect(accounts.single.isArchived, isFalse);
    });

    test('trims surrounding whitespace from the name', () async {
      await repository.create(name: '  Bank BCA  ', type: AccountType.bank);

      final List<Account> accounts = await repository.list();
      expect(accounts.single.name, 'Bank BCA');
    });

    test('rejects an empty name', () async {
      expect(
        () => repository.create(name: '   ', type: AccountType.cash),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Nama akun'),
          ),
        ),
      );
    });

    test('rejects a duplicate name', () async {
      await repository.create(name: 'Dompet', type: AccountType.cash);

      expect(
        () => repository.create(name: 'Dompet', type: AccountType.bank),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a negative initial balance', () async {
      expect(
        () => repository.create(
          name: 'Dompet',
          type: AccountType.cash,
          initialBalance: -1,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('Saldo awal'),
          ),
        ),
      );
    });

    test('updates name, type, balance and note', () async {
      final int id = await repository.create(
        name: 'Dompet',
        type: AccountType.cash,
      );

      await repository.update(
        id,
        name: 'Dompet Utama',
        type: AccountType.eWallet,
        initialBalance: 50000,
        note: 'Dipakai harian',
      );

      final Account account = (await repository.byId(id))!;
      expect(account.name, 'Dompet Utama');
      expect(account.type, AccountType.eWallet);
      expect(account.initialBalance, 50000);
      expect(account.note, 'Dipakai harian');
    });

    test('rejects updating a missing account', () async {
      expect(
        () => repository.update(999, name: 'X', type: AccountType.cash),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('archives and restores an account', () async {
      final int id = await repository.create(
        name: 'Lama',
        type: AccountType.bank,
      );

      await repository.setArchived(id, true);
      expect(await repository.list(), isEmpty);
      expect(
        (await repository.list(includeArchived: true)).single.isArchived,
        isTrue,
      );

      await repository.setArchived(id, false);
      expect(await repository.list(), hasLength(1));
    });

    test('deletes an account without entries', () async {
      final int id = await repository.create(
        name: 'Sementara',
        type: AccountType.other,
      );

      await repository.delete(id);

      expect(await repository.list(includeArchived: true), isEmpty);
    });

    test('refuses to delete an account that still has transactions', () async {
      final int id = await repository.create(
        name: 'Dompet',
        type: AccountType.cash,
      );
      final Category salary = await (db.select(
        db.categories,
      )..where((t) => t.name.equals('Gaji'))).getSingle();

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.income,
              accountId: id,
              categoryId: Value(salary.id),
              amount: 10000,
              transactionDate: DateTime(2026, 1, 1),
            ),
          );

      expect(
        () => repository.delete(id),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('transaksi'),
          ),
        ),
      );
    });

    test('refuses to delete an account used by a savings goal', () async {
      final int accountId = await repository.create(
        name: 'Dompet',
        type: AccountType.cash,
      );
      final int goalId = await db
          .into(db.savingsGoals)
          .insert(
            SavingsGoalsCompanion.insert(
              name: 'Dana darurat',
              targetAmount: 1000000,
            ),
          );
      await db
          .into(db.savingsContributions)
          .insert(
            SavingsContributionsCompanion.insert(
              goalId: goalId,
              accountId: accountId,
              type: SavingsEntryType.deposit,
              amount: 50000,
              contributionDate: DateTime(2026, 1, 2),
            ),
          );

      expect(
        () => repository.delete(accountId),
        throwsA(isA<ValidationException>()),
      );
    });

    test('first account becomes the default account', () async {
      expect(await repository.defaultAccountId(), isNull);

      final int first = await repository.create(
        name: 'Dompet',
        type: AccountType.cash,
      );
      await repository.create(name: 'BCA', type: AccountType.bank);

      expect(await repository.defaultAccountId(), first);
    });

    test('streams accounts in manual sort order, then name', () async {
      await repository.create(name: 'Zeta', type: AccountType.other);
      await repository.create(name: 'Alpha', type: AccountType.cash);

      final List<Account> accounts = await repository.watch().first;

      // Creation order decides `sortOrder`, so the first account stays first.
      expect(accounts.map((a) => a.name).toList(), <String>['Zeta', 'Alpha']);
    });
  });
}
