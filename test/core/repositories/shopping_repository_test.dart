import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/shopping_repository.dart';
import 'package:fintrack/core/errors/app_exception.dart';

void main() {
  late AppDatabase db;
  late ShoppingRepository repository;
  late int accountId;
  late int categoryId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    repository = ShoppingRepository(db);
    accountId = await AccountsRepository(db)
        .create(name: 'Dompet', type: AccountType.cash);
    categoryId = (await CategoriesRepository(
      db,
    ).list(kind: CategoryKind.expense)).first.id;
  });

  tearDown(() => db.close());

  test('total is the sum of quantity times unit price', () async {
    final int listId = await repository.create(
      title: 'Belanja mingguan',
      shoppingDate: DateTime(2026, 5, 20, 10),
    );
    await repository.addItem(listId, name: 'Beras', quantity: 2, unitPrice: 15000);
    await repository.addItem(listId, name: 'Telur', quantity: 1, unitPrice: 27000);
    await repository.addItem(listId, name: 'Sabun');

    final ShoppingListDetail detail = (await repository.byId(listId))!;

    expect(detail.itemCount, 3);
    expect(detail.pricedCount, 2);
    expect(detail.total, 57000);
    // An unpriced line must not make the note unbootable.
    expect(detail.isBooked, isFalse);
  });

  test('booking creates one expense and cannot be repeated', () async {
    final int listId = await repository.create(
      title: 'Belanja pasar',
      shoppingDate: DateTime(2026, 5, 20, 10),
      note: 'Bahan masakan',
    );
    await repository.addItem(listId, name: 'Beras', quantity: 2, unitPrice: 15000);

    final int transactionId = await repository.book(
      listId,
      accountId: accountId,
      categoryId: categoryId,
    );

    final FinancialTransaction row = (await db.select(db.transactions).get()).single;
    expect(row.id, transactionId);
    expect(row.type, TransactionType.expense);
    expect(row.amount, 30000);
    expect(row.transactionDate, DateTime(2026, 5, 20));
    expect(row.note, 'Belanja pasar — Bahan masakan');

    expect((await repository.byId(listId))!.isBooked, isTrue);
    await expectLater(
      repository.book(listId, accountId: accountId, categoryId: categoryId),
      throwsA(isA<ValidationException>()),
    );
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('an unpriced note refuses to book', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await repository.addItem(listId, name: 'Gula');

    await expectLater(
      repository.book(listId, accountId: accountId, categoryId: categoryId),
      throwsA(isA<ValidationException>()),
    );
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('explicit amount overrides the computed total', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await repository.addItem(listId, name: 'Sayur', quantity: 1, unitPrice: 10000);

    await repository.book(
      listId,
      accountId: accountId,
      categoryId: categoryId,
      amount: 9500,
    );

    expect((await db.select(db.transactions).get()).single.amount, 9500);
  });

  test('unbook deletes the expense and frees the note', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await repository.addItem(listId, name: 'Beras', quantity: 1, unitPrice: 15000);
    await repository.book(
      listId,
      accountId: accountId,
      categoryId: categoryId,
    );

    await repository.unbook(listId);

    expect(await db.select(db.transactions).get(), isEmpty);
    expect((await repository.byId(listId))!.isBooked, isFalse);
  });

  test('deleting a note cascades to its items', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await repository.addItem(listId, name: 'Beras');
    await repository.delete(listId);

    expect(await db.select(db.shoppingItems).get(), isEmpty);
    expect(await repository.byId(listId), isNull);
  });

  test('deleting the booked transaction keeps the note editable', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await repository.addItem(listId, name: 'Beras', quantity: 1, unitPrice: 15000);
    final int transactionId = await repository.book(
      listId,
      accountId: accountId,
      categoryId: categoryId,
    );

    // Mirrors deleting the expense from the ledger page.
    await (db.delete(db.transactions)..where((t) => t.id.equals(transactionId)))
        .go();

    final ShoppingListDetail detail = (await repository.byId(listId))!;
    expect(detail.list.transactionId, isNull, reason: 'FK uses SET NULL');
    expect(detail.isBooked, isFalse);
  });

  test('items keep insertion order and can be checked off', () async {
    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    final int first = await repository.addItem(listId, name: 'Beras');
    await repository.addItem(listId, name: 'Minyak');

    await repository.updateItem(first, isChecked: true);

    final ShoppingListDetail detail = (await repository.byId(listId))!;
    expect(detail.items.map((i) => i.name), <String>['Beras', 'Minyak']);
    expect(detail.checkedCount, 1);
    expect(detail.isComplete, isFalse);

    await repository.setAllChecked(listId, true);
    expect((await repository.byId(listId))!.isComplete, isTrue);
  });

  test('rejects empty titles, zero quantity and negative prices', () async {
    await expectLater(
      repository.create(title: '   ', shoppingDate: DateTime(2026, 5, 20)),
      throwsA(isA<ValidationException>()),
    );

    final int listId = await repository.create(
      title: 'Belanja',
      shoppingDate: DateTime(2026, 5, 20),
    );
    await expectLater(
      repository.addItem(listId, name: 'Beras', quantity: 0),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repository.addItem(listId, name: 'Beras', unitPrice: -1),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repository.addItem(listId, name: '  '),
      throwsA(isA<ValidationException>()),
    );
  });

  test('missing list is reported, not silently created', () async {
    await expectLater(
      repository.addItem(999, name: 'Beras'),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      repository.delete(999),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      repository.updateItem(999, name: 'Beras'),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('lists are newest shopping date first and filter booked ones', () async {
    await repository.create(title: 'Lama', shoppingDate: DateTime(2026, 4, 1));
    final int newest = await repository.create(
      title: 'Baru',
      shoppingDate: DateTime(2026, 5, 1),
    );

    final List<ShoppingListDetail> all = await repository.list();
    expect(all.first.list.title, 'Baru');
    expect(all.last.list.title, 'Lama');

    await repository.addItem(newest, name: 'Beras', quantity: 1, unitPrice: 1000);
    await repository.book(
      newest,
      accountId: accountId,
      categoryId: categoryId,
    );

    final List<ShoppingListDetail> open = await repository.list(
      includeBooked: false,
    );
    expect(open.map((d) => d.list.title), <String>['Lama']);
  });
}
