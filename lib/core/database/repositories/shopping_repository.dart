import 'package:drift/drift.dart';

import '../../errors/app_exception.dart';
import '../app_database.dart';
import '../enums.dart';

/// One shopping note with its lines and derived totals.
class ShoppingListDetail {
  const ShoppingListDetail({
    required this.list,
    required this.items,
    required this.total,
  });

  final ShoppingList list;
  final List<ShoppingItem> items;

  /// Sum of every priced line (`quantity * unitPrice`). Lines without a price
  /// contribute nothing, so a partly filled list still shows a usable subtotal.
  final int total;

  int get itemCount => items.length;

  /// How many lines the user has ticked off.
  int get checkedCount => items.where((ShoppingItem i) => i.isChecked).length;

  bool get isBooked => list.transactionId != null;

  bool get isComplete => items.isNotEmpty && checkedCount == itemCount;

  /// How many priced lines still lack a quantity-adjusted total.
  int get pricedCount =>
      items.where((ShoppingItem i) => i.unitPrice != null).length;

  int get estimatedTotal => total;
}

/// Data access for shopping notes and their items.
///
/// The note itself is never a ledger row; only [book] creates a transaction, and
/// it stores the resulting id so the same note cannot be booked twice.
class ShoppingRepository {
  ShoppingRepository(this._db);

  final AppDatabase _db;

  /// Live newest-first notes with totals and line counts.
  Stream<List<ShoppingListDetail>> watch({bool includeBooked = true}) async* {
    final Stream<List<ShoppingList>> lists =
        (_db.select(_db.shoppingLists)
              ..orderBy(<OrderClauseGenerator<$ShoppingListsTable>>[
                (t) => OrderingTerm.desc(t.shoppingDate),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..where(
                (t) =>
                    includeBooked
                        ? const Constant(true)
                        : t.transactionId.isNull(),
              ))
            .watch();

    // Re-read the child rows whenever either table changes.
    await for (final List<ShoppingList> rows in lists) {
      final List<ShoppingListDetail> detail = <ShoppingListDetail>[];
      for (final ShoppingList list in rows) {
        detail.add(await _detailOf(list));
      }
      yield detail;
    }
  }

  Future<List<ShoppingListDetail>> list({bool includeBooked = true}) =>
      watch(includeBooked: includeBooked).first;

  Future<ShoppingListDetail?> byId(int id) async {
    final ShoppingList? list = await (_db.select(
      _db.shoppingLists,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (list == null) return null;
    return _detailOf(list);
  }

  Future<int> create({
    required String title,
    required DateTime shoppingDate,
    String? note,
  }) async {
    final String cleanTitle = _validateTitle(title);
    return _db
        .into(_db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            title: cleanTitle,
            shoppingDate: _dayOf(shoppingDate),
            note: Value(_cleanOptional(note)),
          ),
        );
  }

  Future<void> updateHeader(
    int id, {
    required String title,
    required DateTime shoppingDate,
    String? note,
  }) async {
    final String cleanTitle = _validateTitle(title);
    final int updated =
        await (_db.update(_db.shoppingLists)..where((t) => t.id.equals(id)))
            .write(
              ShoppingListsCompanion(
                title: Value(cleanTitle),
                shoppingDate: Value(_dayOf(shoppingDate)),
                note: Value(_cleanOptional(note)),
                updatedAt: Value(DateTime.now()),
              ),
            );
    if (updated == 0) {
      throw const NotFoundException('Catatan belanja tidak ditemukan.');
    }
  }

  Future<void> delete(int id) async {
    final int removed = await (_db.delete(
      _db.shoppingLists,
    )..where((t) => t.id.equals(id))).go();
    if (removed == 0) {
      throw const NotFoundException('Catatan belanja tidak ditemukan.');
    }
  }

  /// Appends a line, keeping append order stable.
  Future<int> addItem(
    int listId, {
    required String name,
    int quantity = 1,
    int? unitPrice,
  }) async {
    final String cleanName = _validateItemName(name);
    _validateQuantity(quantity);
    _validateUnitPrice(unitPrice);
    await _requireList(listId);

    final int sortOrder = await _nextSortOrder(listId);
    return _db
        .into(_db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            listId: listId,
            name: cleanName,
            quantity: Value(quantity),
            unitPrice: Value(unitPrice),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  Future<void> updateItem(
    int itemId, {
    String? name,
    int? quantity,
    int? unitPrice,
    bool? isChecked,
    bool clearUnitPrice = false,
  }) async {
    final ShoppingItem? existing = await (_db.select(
      _db.shoppingItems,
    )..where((t) => t.id.equals(itemId))).getSingleOrNull();
    if (existing == null) {
      throw const NotFoundException('Item belanja tidak ditemukan.');
    }
    if (name != null) name = _validateItemName(name);
    if (quantity != null) _validateQuantity(quantity);
    _validateUnitPrice(unitPrice);

    await (_db.update(_db.shoppingItems)..where((t) => t.id.equals(itemId)))
        .write(
          ShoppingItemsCompanion(
            name: name == null ? const Value.absent() : Value(name),
            quantity: quantity == null
                ? const Value.absent()
                : Value(quantity),
            unitPrice: clearUnitPrice
                ? const Value(null)
                : unitPrice == null
                ? const Value.absent()
                : Value(unitPrice),
            isChecked: isChecked == null
                ? const Value.absent()
                : Value(isChecked),
          ),
        );
  }

  Future<void> removeItem(int itemId) async {
    final int removed = await (_db.delete(
      _db.shoppingItems,
    )..where((t) => t.id.equals(itemId))).go();
    if (removed == 0) {
      throw const NotFoundException('Item belanja tidak ditemukan.');
    }
  }

  Future<void> setAllChecked(int listId, bool checked) async {
    await (_db.update(_db.shoppingItems)..where((t) => t.listId.equals(listId)))
        .write(ShoppingItemsCompanion(isChecked: Value(checked)));
  }

  /// Books the note's total as one expense row and remembers it on the note.
  ///
  /// Refuses when the note is already booked so a double tap cannot create two
  /// expenses, and refuses a zero total so an empty list cannot be booked.
  Future<int> book(
    int listId, {
    required int accountId,
    required int categoryId,
    int? amount,
  }) async {
    final ShoppingListDetail? detail = await byId(listId);
    if (detail == null) {
      throw const NotFoundException('Catatan belanja tidak ditemukan.');
    }
    if (detail.isBooked) {
      throw const ValidationException(
        'Catatan ini sudah masuk ke pengeluaran.',
      );
    }
    final int total = amount ?? detail.total;
    if (total <= 0) {
      throw const ValidationException(
        'Isi harga item dulu supaya total belanja bisa dicatat.',
      );
    }
    if (total > 999999999999) {
      throw const ValidationException('Total belanja terlalu besar.');
    }

    return _db.transaction(() async {
      final int transactionId = await _db
          .into(_db.transactions)
          .insert(
            TransactionsCompanion.insert(
              type: TransactionType.expense,
              accountId: accountId,
              categoryId: Value(categoryId),
              amount: total,
              transactionDate: detail.list.shoppingDate,
              note: Value(_bookingNote(detail.list)),
            ),
          );
      await (_db.update(_db.shoppingLists)..where((t) => t.id.equals(listId)))
          .write(
            ShoppingListsCompanion(
              transactionId: Value(transactionId),
              updatedAt: Value(DateTime.now()),
            ),
          );
      return transactionId;
    });
  }

  /// Removes the booking link (and the expense row) so the note can be edited
  /// and booked again. Used when the user corrects a wrongly booked list.
  Future<void> unbook(int listId) async {
    final ShoppingListDetail? detail = await byId(listId);
    if (detail == null) {
      throw const NotFoundException('Catatan belanja tidak ditemukan.');
    }
    final int? transactionId = detail.list.transactionId;
    await _db.transaction(() async {
      await (_db.update(_db.shoppingLists)..where((t) => t.id.equals(listId)))
          .write(
            ShoppingListsCompanion(
              transactionId: const Value(null),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (transactionId != null) {
        await (_db.delete(
          _db.transactions,
        )..where((t) => t.id.equals(transactionId))).go();
      }
    });
  }

  Future<ShoppingListDetail> _detailOf(ShoppingList list) async {
    final List<ShoppingItem> items = await (_db.select(_db.shoppingItems)
          ..where((t) => t.listId.equals(list.id))
          ..orderBy(<OrderClauseGenerator<$ShoppingItemsTable>>[
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    int total = 0;
    for (final ShoppingItem item in items) {
      total += item.quantity * (item.unitPrice ?? 0);
    }
    return ShoppingListDetail(list: list, items: items, total: total);
  }

  Future<void> _requireList(int listId) async {
    final bool exists =
        await (_db.select(_db.shoppingLists)
              ..where((t) => t.id.equals(listId)))
            .getSingleOrNull() !=
        null;
    if (!exists) {
      throw const NotFoundException('Catatan belanja tidak ditemukan.');
    }
  }

  Future<int> _nextSortOrder(int listId) async {
    final int? maxOrder = await _db
        .customSelect(
          'SELECT MAX(sort_order) AS m FROM shopping_items WHERE list_id = ?',
          variables: <Variable<Object>>[Variable<int>(listId)],
        )
        .map((QueryRow row) => row.readNullable<int>('m'))
        .getSingle();
    return (maxOrder ?? -1) + 1;
  }

  String _bookingNote(ShoppingList list) {
    final String? note = list.note?.trim();
    return note == null || note.isEmpty ? list.title : '${list.title} — $note';
  }

  static DateTime _dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _validateTitle(String raw) {
    final String title = raw.trim();
    if (title.isEmpty) {
      throw const ValidationException('Nama catatan belanja wajib diisi.');
    }
    if (title.length > 80) {
      throw const ValidationException(
        'Nama catatan belanja maksimal 80 karakter.',
      );
    }
    return title;
  }

  String _validateItemName(String raw) {
    final String name = raw.trim();
    if (name.isEmpty) {
      throw const ValidationException('Nama item wajib diisi.');
    }
    if (name.length > 120) {
      throw const ValidationException('Nama item maksimal 120 karakter.');
    }
    return name;
  }

  void _validateQuantity(int quantity) {
    if (quantity <= 0) {
      throw const ValidationException('Jumlah item minimal 1.');
    }
    if (quantity > 9999) {
      throw const ValidationException('Jumlah item terlalu banyak.');
    }
  }

  void _validateUnitPrice(int? unitPrice) {
    if (unitPrice == null) return;
    if (unitPrice < 0) {
      throw const ValidationException('Harga tidak boleh negatif.');
    }
    if (unitPrice > 999999999999) {
      throw const ValidationException('Harga terlalu besar.');
    }
  }

  String? _cleanOptional(String? value) {
    final String? clean = value?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
