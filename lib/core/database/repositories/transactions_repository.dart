import 'package:drift/drift.dart';

import '../../errors/app_exception.dart';
import '../../utils/date_range.dart';
import '../app_database.dart';
import '../enums.dart';

/// Data access for the transaction ledger.
///
/// A transfer is stored as a single row carrying both accounts, so it can never
/// be counted twice. Income/expense rows carry exactly one account and one
/// category whose kind must match the transaction type.
class TransactionsRepository {
  TransactionsRepository(this._db);

  final AppDatabase _db;

  /// Transactions newest first, optionally filtered.
  Future<List<FinancialTransaction>> list({
    DateRange? range,
    TransactionType? type,
    int? accountId,
    int? categoryId,
    String? search,
    int? limit,
  }) {
    return _query(
      range: range,
      type: type,
      accountId: accountId,
      categoryId: categoryId,
      search: search,
      limit: limit,
    ).get();
  }

  /// Live list for the transaction page.
  Stream<List<FinancialTransaction>> watch({
    DateRange? range,
    TransactionType? type,
    int? accountId,
    int? categoryId,
    String? search,
    int? limit,
  }) {
    return _query(
      range: range,
      type: type,
      accountId: accountId,
      categoryId: categoryId,
      search: search,
      limit: limit,
    ).watch();
  }

  Future<FinancialTransaction?> byId(int id) async {
    return (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createIncome({
    required int accountId,
    required int categoryId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    await _validateEntry(
      accountId: accountId,
      categoryId: categoryId,
      expectedKind: CategoryKind.income,
      amount: amount,
      date: date,
    );

    return _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            type: TransactionType.income,
            accountId: accountId,
            categoryId: Value(categoryId),
            amount: amount,
            transactionDate: date,
            note: Value(_cleanNote(note)),
          ),
        );
  }

  Future<int> createExpense({
    required int accountId,
    required int categoryId,
    required int amount,
    required DateTime date,
    String? note,
    String? attachmentPath,
  }) async {
    await _validateEntry(
      accountId: accountId,
      categoryId: categoryId,
      expectedKind: CategoryKind.expense,
      amount: amount,
      date: date,
    );

    return _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            type: TransactionType.expense,
            accountId: accountId,
            categoryId: Value(categoryId),
            amount: amount,
            transactionDate: date,
            note: Value(_cleanNote(note)),
            attachmentPath: Value(_cleanNote(attachmentPath)),
          ),
        );
  }

  /// Moves [amount] from [fromAccountId] to [toAccountId] in one row, so the
  /// total wallet balance is unchanged.
  Future<int> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    _validateAmount(amount);
    if (fromAccountId == toAccountId) {
      throw const ValidationException(
        'Akun asal dan tujuan transfer harus berbeda.',
      );
    }
    await _requireActiveAccount(fromAccountId);
    await _requireActiveAccount(toAccountId);

    return _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            type: TransactionType.transfer,
            accountId: fromAccountId,
            toAccountId: Value(toAccountId),
            amount: amount,
            transactionDate: date,
            note: Value(_cleanNote(note)),
          ),
        );
  }

  Future<void> updateIncome(
    int id, {
    required int accountId,
    required int categoryId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    await _requireExisting(id, TransactionType.income);
    await _validateEntry(
      accountId: accountId,
      categoryId: categoryId,
      expectedKind: CategoryKind.income,
      amount: amount,
      date: date,
    );

    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        toAccountId: const Value.absent(),
        amount: Value(amount),
        transactionDate: Value(date),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateExpense(
    int id, {
    required int accountId,
    required int categoryId,
    required int amount,
    required DateTime date,
    String? note,
    String? attachmentPath,
  }) async {
    await _requireExisting(id, TransactionType.expense);
    await _validateEntry(
      accountId: accountId,
      categoryId: categoryId,
      expectedKind: CategoryKind.expense,
      amount: amount,
      date: date,
    );

    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        toAccountId: const Value.absent(),
        amount: Value(amount),
        transactionDate: Value(date),
        note: Value(_cleanNote(note)),
        attachmentPath: Value(_cleanNote(attachmentPath)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateTransfer(
    int id, {
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    await _requireExisting(id, TransactionType.transfer);
    _validateAmount(amount);
    if (fromAccountId == toAccountId) {
      throw const ValidationException(
        'Akun asal dan tujuan transfer harus berbeda.',
      );
    }
    await _requireActiveAccount(fromAccountId);
    await _requireActiveAccount(toAccountId);

    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(fromAccountId),
        toAccountId: Value(toAccountId),
        categoryId: const Value.absent(),
        amount: Value(amount),
        transactionDate: Value(date),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) async {
    final int removed = await (_db.delete(
      _db.transactions,
    )..where((t) => t.id.equals(id))).go();
    if (removed == 0) {
      throw const NotFoundException('Transaksi tidak ditemukan.');
    }
  }

  /// Resolves the category row for display alongside a transaction.
  Future<Category?> categoryOf(FinancialTransaction transaction) async {
    final int? categoryId = transaction.categoryId;
    if (categoryId == null) return null;
    return (_db.select(
      _db.categories,
    )..where((t) => t.id.equals(categoryId))).getSingleOrNull();
  }

  SimpleSelectStatement<$TransactionsTable, FinancialTransaction> _query({
    DateRange? range,
    TransactionType? type,
    int? accountId,
    int? categoryId,
    String? search,
    int? limit,
  }) {
    final SimpleSelectStatement<$TransactionsTable, FinancialTransaction>
    query = _db.select(_db.transactions)
      ..orderBy(<OrderClauseGenerator<$TransactionsTable>>[
        (t) => OrderingTerm.desc(t.transactionDate),
        (t) => OrderingTerm.desc(t.id),
      ]);

    if (range != null) {
      query.where(
        (t) =>
            t.transactionDate.isBiggerOrEqualValue(range.start) &
            t.transactionDate.isSmallerThanValue(range.end),
      );
    }
    if (type != null) {
      query.where((t) => t.type.equalsValue(type));
    }
    if (accountId != null) {
      // A transfer touches both accounts, so match either side of the row.
      query.where(
        (t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId),
      );
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    final String? needle = search?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      // Search covers the note plus the category name so users can type
      // "makan" without knowing exactly which category they used.
      final String escaped = needle.replaceAll("'", "''");
      query.where(
        (t) =>
            t.note.lower().contains(escaped) |
            t.categoryId.isInQuery(
              _db.selectOnly(_db.categories)
                ..addColumns(<Expression<Object>>[_db.categories.id])
                ..where(_db.categories.name.lower().contains(escaped)),
            ),
      );
    }
    if (limit != null) {
      query.limit(limit);
    }

    return query;
  }

  Future<void> _requireExisting(int id, TransactionType expected) async {
    final FinancialTransaction? existing = await byId(id);
    if (existing == null) {
      throw const NotFoundException('Transaksi tidak ditemukan.');
    }
    if (existing.type != expected) {
      throw const ValidationException(
        'Jenis transaksi tidak dapat diubah. Hapus lalu buat transaksi baru.',
      );
    }
  }

  Future<void> _validateEntry({
    required int accountId,
    required int categoryId,
    required CategoryKind expectedKind,
    required int amount,
    required DateTime date,
  }) async {
    _validateAmount(amount);
    if (date.isBefore(DateTime(1900))) {
      throw const ValidationException('Tanggal transaksi tidak valid.');
    }
    await _requireActiveAccount(accountId);

    final Category? category = await (_db.select(
      _db.categories,
    )..where((t) => t.id.equals(categoryId))).getSingleOrNull();

    if (category == null) {
      throw const ValidationException('Kategori tidak ditemukan.');
    }
    if (category.isArchived) {
      throw const ValidationException(
        'Kategori sudah diarsipkan. Pilih kategori lain.',
      );
    }
    if (category.kind != expectedKind) {
      throw ValidationException(
        'Kategori "${category.name}" bukan kategori ${expectedKind.label.toLowerCase()}.',
      );
    }
  }

  Future<void> _requireActiveAccount(int id) async {
    final Account? account = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    if (account == null) {
      throw const ValidationException('Akun tidak ditemukan.');
    }
    if (account.isArchived) {
      throw ValidationException(
        'Akun "${account.name}" sudah diarsipkan. Pilih akun lain.',
      );
    }
  }

  void _validateAmount(int amount) {
    if (amount <= 0) {
      throw const ValidationException('Nominal harus lebih dari nol.');
    }
    // Guard against absurd input such as a paste of many digits; the column is
    // a 64-bit integer, this keeps reports and sums readable.
    if (amount > 999999999999) {
      throw const ValidationException('Nominal terlalu besar.');
    }
  }

  String? _cleanNote(String? note) {
    final String? clean = note?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
