import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/account_balances.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/features/accounts/presentation/accounts_page.dart';
import 'package:fintrack/features/categories/presentation/categories_page.dart';
import 'package:fintrack/features/transactions/presentation/transaction_form_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  late AppDatabase database;
  late AccountsRepository accounts;
  late CategoriesRepository categories;
  late TransactionsRepository transactions;
  late int accountId;
  late List<Account> seededAccounts;
  late List<Category> seededCategories;
  late AccountBalance seededBalance;

  setUp(() async {
    database = AppDatabase.forTesting();
    await database.customSelect('SELECT 1').get();
    await database.ensureSeeded();
    accounts = AccountsRepository(database);
    categories = CategoriesRepository(database);
    transactions = TransactionsRepository(database);
    accountId = await accounts.create(
      name: 'Dompet utama',
      type: AccountType.cash,
      initialBalance: 125000,
    );
    seededAccounts = await accounts.list(includeArchived: true);
    seededCategories = await categories.list(includeArchived: true);
    seededBalance = (await AccountBalanceCalculator(database)
        .forAccount(accountId))!;
  });

  tearDown(() async {
    await database.close();
  });

  /// Unmounts the widget tree while letting drift's stream-store cleanup timers
  /// run on the real clock, otherwise `testWidgets` hangs on pending timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Widget app(Widget child) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((Ref ref) async => database),
      accountsRepositoryProvider.overrideWith((Ref ref) async => accounts),
      categoriesRepositoryProvider.overrideWith((Ref ref) async => categories),
      transactionsRepositoryProvider.overrideWith(
        (Ref ref) async => transactions,
      ),
      accountsProvider.overrideWithValue(
        AsyncData<List<Account>>(seededAccounts),
      ),
      categoriesProvider.overrideWithValue(
        AsyncData<List<Category>>(seededCategories),
      ),
      accountBalanceProvider(accountId)
          .overrideWithValue(AsyncData<AccountBalance?>(seededBalance)),
    ],
    child: MaterialApp(home: child),
  );

  testWidgets('accounts page shows derived balance and creates an account', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AccountsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Dompet utama'), findsOneWidget);
    expect(find.text('Rp 125.000'), findsOneWidget);

    await tester.tap(find.text('Tambah akun'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Rekening BCA');
    await tester.enterText(find.byType(TextField).at(1), '500000');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      final List<Account> rows = await accounts.list(includeArchived: true);
      expect(
        rows.map((Account account) => account.name),
        contains('Rekening BCA'),
      );
      final Account created = rows.firstWhere(
        (Account account) => account.name == 'Rekening BCA',
      );
      expect(created.initialBalance, 500000);
    });
  });

  testWidgets('categories page creates custom category under selected kind', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const CategoriesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Makanan'), findsWidgets);

    await tester.tap(find.text('Tambah kategori'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Kopi sore');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      final List<Category> rows = await categories.list(
        kind: CategoryKind.expense,
        includeArchived: true,
      );
      expect(
        rows.map((Category category) => category.name),
        contains('Kopi sore'),
      );
    });
  });

  testWidgets('transaction form saves expense and updates account balance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((Ref ref) async => database),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: const Center(child: Text('Transactions host')),
              floatingActionButton: FloatingActionButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransactionFormPage(),
                  ),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '25000');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan transaksi'));
    await tester.pumpAndSettle();
    await unmount(tester);

    await tester.runAsync(() async {
      final List<FinancialTransaction> rows = await transactions.list();
      expect(rows, hasLength(1));
      expect(rows.single.type, TransactionType.expense);
      expect(rows.single.amount, 25000);
      expect(rows.single.accountId, accountId);

      final AccountBalance? balance = await AccountBalanceCalculator(database)
          .forAccount(accountId);
      expect(balance!.currentBalance, 100000);
    });
  });
}
