import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/utils/formatters.dart';
import 'package:fintrack/features/transactions/presentation/transaction_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day, 9);
  final DateTime yesterday = DateTime(now.year, now.month, now.day - 1, 9);

  Account account(int id, String name) => Account(
    id: id,
    name: name,
    type: AccountType.cash,
    initialBalance: 0,
    isArchived: false,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );

  Category category(int id, String name, CategoryKind kind) => Category(
    id: id,
    name: name,
    kind: kind,
    iconKey: 'wallet',
    colorValue: 0xFF12855A,
    isArchived: false,
    isDefault: false,
    sortOrder: 0,
    createdAt: now,
  );

  FinancialTransaction row({
    required int id,
    required TransactionType type,
    required int amount,
    required DateTime date,
    int? categoryId,
    String? note,
  }) => FinancialTransaction(
    id: id,
    type: type,
    accountId: 1,
    categoryId: categoryId,
    amount: amount,
    transactionDate: date,
    note: note,
    createdAt: date,
    updatedAt: date,
  );

  final List<Account> accounts = <Account>[account(1, 'Dompet')];
  final List<Category> categories = <Category>[
    category(10, 'Gaji', CategoryKind.income),
    category(11, 'Belanja', CategoryKind.expense),
  ];

  List<Override> overridesFor(List<FinancialTransaction> rows) => <Override>[
    accountsProvider.overrideWithValue(AsyncData<List<Account>>(accounts)),
    categoriesProvider.overrideWithValue(AsyncData<List<Category>>(categories)),
    filteredTransactionsProvider(null).overrideWithValue(
      AsyncData<List<FinancialTransaction>>(rows),
    ),
    for (final Category entry in categories)
      categoryByIdProvider(entry.id).overrideWithValue(AsyncData(entry)),
  ];

  Widget host(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: TransactionsPage()),
  );

  testWidgets('groups by day with Hari ini and Kemarin headers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        overridesFor(<FinancialTransaction>[
          row(
            id: 1,
            type: TransactionType.income,
            amount: 100000,
            date: today,
            categoryId: 10,
            note: 'Gajian',
          ),
          row(
            id: 2,
            type: TransactionType.expense,
            amount: 25000,
            date: today,
            categoryId: 11,
            note: 'Makan siang',
          ),
          row(
            id: 3,
            type: TransactionType.expense,
            amount: 10000,
            date: yesterday,
            categoryId: 11,
            note: 'Parkir',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // Month buckets by default: one header for this month.
    expect(find.text(Formatters.monthYear(now)), findsOneWidget);
    expect(find.text('3 transaksi'), findsOneWidget);

    await tester.tap(find.text('Per hari'));
    await tester.pumpAndSettle();

    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('2 transaksi'), findsOneWidget);
    expect(find.text('1 transaksi'), findsOneWidget);
    // Group totals: income 100k, expense 25k for today.
    expect(find.text(Formatters.currency(100000)), findsWidgets);
    expect(find.text(Formatters.currency(25000)), findsWidgets);
  });

  testWidgets('collapses a group when its header is tapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        overridesFor(<FinancialTransaction>[
          row(
            id: 1,
            type: TransactionType.expense,
            amount: 25000,
            date: today,
            categoryId: 11,
            note: 'Makan siang',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Per hari'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);

    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('search keeps a collapsed group open', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        overridesFor(<FinancialTransaction>[
          row(
            id: 1,
            type: TransactionType.expense,
            amount: 25000,
            date: today,
            categoryId: 11,
            note: 'Makan siang',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Per hari'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'makan');
    await tester.pumpAndSettle();

    // While searching, the matching row cannot hide behind a collapsed header.
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('switches to month and year grouping', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        overridesFor(<FinancialTransaction>[
          row(
            id: 1,
            type: TransactionType.expense,
            amount: 25000,
            date: today,
            categoryId: 11,
            note: 'Makan siang',
          ),
          row(
            id: 2,
            type: TransactionType.expense,
            amount: 10000,
            date: DateTime(now.year - 1, 6, 3),
            categoryId: 11,
            note: 'Parkir',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(Formatters.monthYear(now)), findsOneWidget);
    expect(
      find.text(Formatters.monthYear(DateTime(now.year - 1, 6))),
      findsOneWidget,
    );

    await tester.tap(find.text('Per tahun'));
    await tester.pumpAndSettle();
    expect(find.text(Formatters.year(now)), findsOneWidget);
    expect(find.text(Formatters.year(DateTime(now.year - 1))), findsOneWidget);
  });

  testWidgets('empty ledger shows the empty state', (WidgetTester tester) async {
    await tester.pumpWidget(host(overridesFor(const <FinancialTransaction>[])));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(find.text('Catat transaksi'), findsOneWidget);
  });
}
