import 'package:drift/drift.dart';

import '../app_database.dart';
import '../enums.dart';
import '../../errors/app_exception.dart';

/// Data access for transaction categories.
///
/// Default categories are seeded by [AppDatabase] and are protected from
/// renaming or deletion so historical reports keep their meaning. They can be
/// archived, which hides them from new-entry pickers only.
class CategoriesRepository {
  CategoriesRepository(this._db);

  final AppDatabase _db;

  Future<List<Category>> list({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    return watch(kind: kind, includeArchived: includeArchived).first;
  }

  Stream<List<Category>> watch({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    final SimpleSelectStatement<$CategoriesTable, Category> query =
        _db.select(_db.categories)
          ..orderBy(<OrderClauseGenerator<$CategoriesTable>>[
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]);

    if (kind != null) {
      query.where((t) => t.kind.equalsValue(kind));
    }
    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }

    return query.watch();
  }

  Future<Category?> byId(int id) async {
    return (_db.select(
      _db.categories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> create({
    required String name,
    required CategoryKind kind,
    String? iconKey,
    int? colorValue,
  }) async {
    final String cleanName = _validateName(name);
    await _ensureNameAvailable(cleanName, kind);

    final int sortOrder = await _nextSortOrder(kind);

    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: cleanName,
            kind: kind,
            iconKey: Value(_cleanOptional(iconKey)),
            colorValue: Value(colorValue),
            sortOrder: Value(sortOrder),
          ),
        );
  }

  /// Renames a custom category. Default categories keep their identity because
  /// reports and budgets reference them by name in the UI.
  Future<void> update(
    int id, {
    String? name,
    String? iconKey,
    int? colorValue,
  }) async {
    final Category? existing = await byId(id);
    if (existing == null) {
      throw const NotFoundException('Kategori tidak ditemukan.');
    }
    if (existing.isDefault && name != null && name.trim() != existing.name) {
      throw const ValidationException(
        'Kategori default tidak dapat diubah namanya.',
      );
    }

    String? cleanName;
    if (name != null) {
      cleanName = _validateName(name);
      if (cleanName.toLowerCase() != existing.name.toLowerCase()) {
        await _ensureNameAvailable(cleanName, existing.kind, ignoreId: id);
      }
    }

    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: cleanName == null ? const Value.absent() : Value(cleanName),
        iconKey: iconKey == null
            ? const Value.absent()
            : Value(_cleanOptional(iconKey)),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
      ),
    );
  }

  /// Hides a category from new entries without breaking historical rows.
  Future<void> setArchived(int id, bool archived) async {
    final int updated =
        await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(isArchived: Value(archived)),
        );
    if (updated == 0) {
      throw const NotFoundException('Kategori tidak ditemukan.');
    }
  }

  Future<void> delete(int id) async {
    final Category? existing = await byId(id);
    if (existing == null) {
      throw const NotFoundException('Kategori tidak ditemukan.');
    }
    if (existing.isDefault) {
      throw const ValidationException(
        'Kategori default tidak dapat dihapus. Arsipkan bila tidak dipakai.',
      );
    }

    final int used = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM transactions WHERE category_id = ?',
          variables: <Variable<Object>>[Variable<int>(id)],
        )
        .map((row) => row.read<int>('c'))
        .getSingle();

    if (used > 0) {
      throw const ValidationException(
        'Kategori masih dipakai transaksi. Arsipkan kategori ini sebagai gantinya.',
      );
    }

    final int budgeted = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM budgets WHERE category_id = ?',
          variables: <Variable<Object>>[Variable<int>(id)],
        )
        .map((row) => row.read<int>('c'))
        .getSingle();

    if (budgeted > 0) {
      throw const ValidationException(
        'Kategori masih dipakai anggaran. Arsipkan kategori ini sebagai gantinya.',
      );
    }

    await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _ensureNameAvailable(
    String name,
    CategoryKind kind, {
    int? ignoreId,
  }) async {
    final Category? clash =
        await (_db.select(_db.categories)..where(
              (t) =>
                  t.name.lower().equals(name.toLowerCase()) &
                  t.kind.equalsValue(kind),
            ))
            .getSingleOrNull();

    if (clash != null && clash.id != ignoreId) {
      throw ValidationException('Kategori "$name" sudah ada untuk jenis ini.');
    }
  }

  Future<int> _nextSortOrder(CategoryKind kind) async {
    final int? maxOrder = await _db
        .customSelect(
          'SELECT MAX(sort_order) AS m FROM categories WHERE kind = ?',
          variables: <Variable<Object>>[Variable<String>(kind.name)],
        )
        .map((row) => row.readNullable<int>('m'))
        .getSingle();
    return (maxOrder ?? -1) + 1;
  }

  String _validateName(String raw) {
    final String name = raw.trim();
    if (name.isEmpty) {
      throw const ValidationException('Nama kategori wajib diisi.');
    }
    if (name.length > 60) {
      throw const ValidationException('Nama kategori maksimal 60 karakter.');
    }
    return name;
  }

  String? _cleanOptional(String? value) {
    final String? clean = value?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
