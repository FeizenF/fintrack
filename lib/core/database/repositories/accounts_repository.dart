import 'package:drift/drift.dart';

import '../app_database.dart';
import '../enums.dart';
import '../../errors/app_exception.dart';

/// Data access for financial accounts.
///
/// All validation lives here so the UI can never write an account that breaks
/// the schema or the ledger.
class AccountsRepository {
  AccountsRepository(this._db);

  final AppDatabase _db;

  /// Accounts ordered for display: manual sort order, then name.
  Future<List<Account>> list({bool includeArchived = false}) {
    return watch(includeArchived: includeArchived).first;
  }

  /// Live account list, re-emitted whenever an account changes.
  Stream<List<Account>> watch({bool includeArchived = false}) {
    final SimpleSelectStatement<$AccountsTable, Account> query =
        _db.select(_db.accounts)
          ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]);

    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }

    return query.watch();
  }

  Future<Account?> byId(int id) async {
    return (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> create({
    required String name,
    required AccountType type,
    int initialBalance = 0,
    String? note,
  }) async {
    final String cleanName = _validateName(name);
    _validateBalance(initialBalance);
    await _ensureNameAvailable(cleanName);

    final int sortOrder = await _nextSortOrder();

    return _db
        .into(_db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: cleanName,
            type: type,
            initialBalance: Value(initialBalance),
            note: Value(_cleanNote(note)),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  Future<void> update(
    int id, {
    required String name,
    required AccountType type,
    int? initialBalance,
    String? note,
  }) async {
    final Account? existing = await byId(id);
    if (existing == null) {
      throw const NotFoundException('Akun tidak ditemukan.');
    }

    final String cleanName = _validateName(name);
    if (initialBalance != null) _validateBalance(initialBalance);
    if (cleanName != existing.name) {
      await _ensureNameAvailable(cleanName);
    }

    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: Value(cleanName),
        type: Value(type),
        initialBalance: initialBalance == null
            ? const Value.absent()
            : Value(initialBalance),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Names of columns are trimmed then compared case-insensitively so "Bank"
  /// and "bank " cannot both exist.
  Future<void> _ensureNameAvailable(String name) async {
    final Account? clash =
        await (_db.select(_db.accounts)
              ..where((t) => t.name.lower().equals(name.toLowerCase())))
            .getSingleOrNull();
    if (clash != null) {
      throw ValidationException('Nama akun "$name" sudah dipakai.');
    }
  }

  /// Archived accounts stay in reports, so archiving is preferred over delete.
  Future<void> setArchived(int id, bool archived) async {
    final int updated =
        await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
          AccountsCompanion(
            isArchived: Value(archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) {
      throw const NotFoundException('Akun tidak ditemukan.');
    }
  }

  /// Deletes an account only when nothing references it.
  Future<void> delete(int id) async {
    final Account? existing = await byId(id);
    if (existing == null) {
      throw const NotFoundException('Akun tidak ditemukan.');
    }

    final int transactions = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM transactions '
          'WHERE account_id = ? OR to_account_id = ?',
          variables: <Variable<Object>>[Variable<int>(id), Variable<int>(id)],
        )
        .map((row) => row.read<int>('c'))
        .getSingle();

    if (transactions > 0) {
      throw const ValidationException(
        'Akun masih dipakai oleh transaksi. Arsipkan akun ini sebagai gantinya.',
      );
    }

    final int contributions = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM savings_contributions WHERE account_id = ?',
          variables: <Variable<Object>>[Variable<int>(id)],
        )
        .map((row) => row.read<int>('c'))
        .getSingle();

    if (contributions > 0) {
      throw const ValidationException(
        'Akun masih dipakai oleh target tabungan. Arsipkan akun ini sebagai gantinya.',
      );
    }

    await (_db.delete(_db.accounts)..where((t) => t.id.equals(id))).go();
  }

  /// Account used as the default source in the transaction form.
  Future<int?> defaultAccountId() async {
    final Account? first =
        await (_db.select(_db.accounts)
              ..where((t) => t.isArchived.equals(false))
              ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
                (t) => OrderingTerm.asc(t.sortOrder),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return first?.id;
  }

  Future<int> _nextSortOrder() async {
    final int? maxOrder = await _db
        .customSelect('SELECT MAX(sort_order) AS m FROM accounts')
        .map((row) => row.readNullable<int>('m'))
        .getSingle();
    return (maxOrder ?? -1) + 1;
  }

  String _validateName(String raw) {
    final String name = raw.trim();
    if (name.isEmpty) {
      throw const ValidationException('Nama akun wajib diisi.');
    }
    if (name.length > 60) {
      throw const ValidationException('Nama akun maksimal 60 karakter.');
    }
    return name;
  }

  void _validateBalance(int value) {
    if (value < 0) {
      throw const ValidationException('Saldo awal tidak boleh negatif.');
    }
  }

  String? _cleanNote(String? note) {
    final String? clean = note?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
