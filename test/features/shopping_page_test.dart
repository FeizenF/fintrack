import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/shopping_repository.dart';
import 'package:fintrack/features/shopping/presentation/shopping_detail_page.dart';
import 'package:fintrack/features/shopping/presentation/shopping_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  late AppDatabase database;
  late ShoppingRepository shopping;
  late int accountId;
  late int categoryId;
  late List<Account> accountRows;
  late List<Category> categoryRows;

  setUp(() async {
    database = AppDatabase.forTesting();
    await database.customSelect('SELECT 1').get();
    await database.ensureSeeded();
    shopping = ShoppingRepository(database);
    accountId = await AccountsRepository(database)
        .create(name: 'Dompet', type: AccountType.cash, initialBalance: 500000);
    accountRows = await AccountsRepository(database).list(includeArchived: true);
    categoryRows = await CategoriesRepository(
      database,
    ).list(includeArchived: true);
    categoryId = categoryRows
        .firstWhere((Category row) => row.kind == CategoryKind.expense)
        .id;
  });

  tearDown(() async => database.close());

  /// Unmounts while drift's stream-store cleanup timers run on the real clock,
  /// otherwise `testWidgets` fails on pending timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  List<Override> overridesFor() => <Override>[
    appDatabaseProvider.overrideWith((Ref ref) async => database),
    shoppingRepositoryProvider.overrideWith((Ref ref) async => shopping),
    accountsProvider.overrideWithValue(AsyncData<List<Account>>(accountRows)),
    categoriesProvider.overrideWithValue(
      AsyncData<List<Category>>(categoryRows),
    ),
  ];

  Widget host(List<Override> overrides, Widget child) {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => child),
        GoRoute(
          path: '/shopping/:id',
          builder: (_, GoRouterState state) => ShoppingDetailPage(
            listId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shopping page shows the empty state and creates a note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(overridesFor(), const ShoppingPage()));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada catatan belanja'), findsOneWidget);

    await tester.tap(find.text('Buat catatan'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama catatan'),
      'Belanja mingguan',
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    // Saving jumps straight into the new note.
    expect(find.text('Belanja mingguan'), findsOneWidget);
    expect(find.text('Belum ada item.'), findsOneWidget);

    late List<ShoppingListDetail> notes;
    await tester.runAsync(() async {
      notes = await shopping.list();
    });
    expect(notes.single.list.title, 'Belanja mingguan');

    await unmount(tester);
  });

  testWidgets('detail page shows items, total and books one expense', (
    WidgetTester tester,
  ) async {
    late int listId;
    await tester.runAsync(() async {
      listId = await shopping.create(
        title: 'Belanja pasar',
        shoppingDate: DateTime(2026, 5, 20),
      );
      await shopping.addItem(
        listId,
        name: 'Beras',
        quantity: 2,
        unitPrice: 15000,
      );
    });

    await tester.pumpWidget(
      host(overridesFor(), ShoppingDetailPage(listId: listId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Beras'), findsOneWidget);
    expect(find.text('2 × Rp 15.000'), findsOneWidget);
    expect(find.text('Rp 30.000'), findsWidgets);

    await tester.tap(
      find.textContaining('sebagai pengeluaran'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catat sebagai pengeluaran'), findsOneWidget);
    await tester.tap(find.text('Catat'));
    await tester.pumpAndSettle();

    late List<FinancialTransaction> rows;
    late ShoppingListDetail? saved;
    await tester.runAsync(() async {
      rows = await database.select(database.transactions).get();
      saved = await shopping.byId(listId);
    });
    expect(rows.single.type, TransactionType.expense);
    expect(rows.single.amount, 30000);
    expect(saved!.isBooked, isTrue);

    await unmount(tester);
  });

  testWidgets('detail page reports a missing note instead of crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(overridesFor(), const ShoppingDetailPage(listId: 999)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catatan belanja tidak ditemukan.'), findsOneWidget);

    await unmount(tester);
  });
}
