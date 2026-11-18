import 'package:drift/drift.dart';

import '../../errors/app_exception.dart';
import '../app_database.dart';
import '../enums.dart';

/// One budget row joined with the amount already spent in its month.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.categoryName,
    required this.categoryKind,
    required this.spent,
  });

  final Budget budget;
  final String categoryName;
  final CategoryKind categoryKind;

  /// Total expense booked in the budget month for the budget category.
  final int spent;

  int get limit => budget.limitAmount;

  int get remaining => limit - spent;

  /// Fraction of the limit already used. Can exceed 1 when overspent.
  double get ratio => limit == 0 ? 0 : spent / limit;

  bool get isExceeded => spent > limit;

  /// Usage reached the 80% warning threshold (and is not yet exceeded).
  bool get isNearLimit => !isExceeded && ratio >= 0.8;
}

/// Data access for monthly spending limits.
///
/// A budget is always scoped to one expense category and one normalised month,
/// so "spent" is a ledger sum and never a stored counter that could drift.
class BudgetsRepository {
  BudgetsRepository(this._db);

  final AppDatabase _db;

  /// Normalises any date inside a month to the first day at 00:00 local time.
  static DateTime monthStartOf(DateTime date) =>
      DateTime(date.year, date.month);

  /// Live budgets for [month] with their spent totals.
  Stream<List<BudgetProgress>> watch(DateTime month) {
    final DateTime monthStart = monthStartOf(month);
    final DateTime monthEnd = DateTime(monthStart.year, monthStart.month + 1);

    final String sql = '''
SELECT
  b.id AS budget_id,
  b.category_id AS category_id,
  b.month_start AS month_start,
  b.limit_amount AS limit_amount,
  b.is_archived AS is_archived,
  b.created_at AS created_at,
  b.updated_at AS updated_at,
  c.name AS category_name,
  c.kind AS category_kind,
  COALESCE((
    SELECT SUM(t.amount) FROM transactions t
    WHERE t.category_id = b.category_id AND t.type = ?
      AND t.transaction_date >= ? AND t.transaction_date < ?
  ), 0) AS spent
FROM budgets b
JOIN categories c ON c.id = b.category_id
WHERE b.month_start = ? AND b.is_archived = 0
ORDER BY c.sort_order, c.name
''';

    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(TransactionType.expense.name),
            Variable<DateTime>(monthStart),
            Variable<DateTime>(monthEnd),
            Variable<DateTime>(monthStart),
          ],
          readsFrom: <TableInfo<Table, Object?>>{
            _db.budgets,
            _db.transactions,
            _db.categories,
          },
        )
        .watch()
        .map((List<QueryRow> rows) => rows.map(_readRow).toList(growable: false));
  }

  Future<List<BudgetProgress>> list(DateTime month) =>
      watch(month).first;

  Future<Budget?> byId(int id) async {
    return (_db.select(
      _db.budgets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> create({
    required int categoryId,
    required DateTime monthStart,
    required int limitAmount,
  }) async {
    final DateTime month = monthStartOf(monthStart);
    _validateLimit(limitAmount);
    await _requireExpenseCategory(categoryId);
    await _ensureUnused(categoryId, month);

    return _db
        .into(_db.budgets)
        .insert(
          BudgetsCompanion.insert(
            categoryId: categoryId,
            monthStart: month,
            limitAmount: limitAmount,
          ),
        );
  }

  Future<void> updateLimit(int id, int limitAmount) async {
    _validateLimit(limitAmount);
    final int updated =
        await (_db.update(_db.budgets)..where((t) => t.id.equals(id))).write(
          BudgetsCompanion(
            limitAmount: Value(limitAmount),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) {
      throw const NotFoundException('Anggaran tidak ditemukan.');
    }
  }

  Future<void> delete(int id) async {
    final int removed =
        await (_db.delete(_db.budgets)..where((t) => t.id.equals(id))).go();
    if (removed == 0) {
      throw const NotFoundException('Anggaran tidak ditemukan.');
    }
  }

  /// Copies the previous month's budgets into [month] when they do not exist.
  ///
  /// Returns how many rows were created so the UI can report a result.
  Future<int> copyFromPreviousMonth(DateTime month) async {
    final DateTime current = monthStartOf(month);
    final DateTime previous = DateTime(current.year, current.month - 1);

    final List<Budget> source =
        await (_db.select(_db.budgets)..where(
              (t) =>
                  t.monthStart.equals(previous) & t.isArchived.equals(false),
            ))
            .get();

    int created = 0;
    for (final Budget budget in source) {
      final bool exists = await _exists(budget.categoryId, current);
      if (exists) continue;
      await _db
          .into(_db.budgets)
          .insert(
            BudgetsCompanion.insert(
              categoryId: budget.categoryId,
              monthStart: current,
              limitAmount: budget.limitAmount,
            ),
          );
      created++;
    }
    return created;
  }

  Future<bool> _exists(int categoryId, DateTime month) async {
    final Budget? row =
        await (_db.select(_db.budgets)..where(
              (t) =>
                  t.categoryId.equals(categoryId) &
                  t.monthStart.equals(month),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> _ensureUnused(int categoryId, DateTime month) async {
    if (await _exists(categoryId, month)) {
      throw const ValidationException(
        'Kategori ini sudah punya anggaran pada bulan tersebut.',
      );
    }
  }

  Future<void> _requireExpenseCategory(int categoryId) async {
    final Category? category =
        await (_db.select(_db.categories)
              ..where((t) => t.id.equals(categoryId)))
            .getSingleOrNull();

    if (category == null) {
      throw const ValidationException('Kategori tidak ditemukan.');
    }
    if (category.kind != CategoryKind.expense) {
      throw const ValidationException(
        'Anggaran hanya untuk kategori pengeluaran.',
      );
    }
    if (category.isArchived) {
      throw const ValidationException(
        'Kategori sudah diarsipkan. Pilih kategori lain.',
      );
    }
  }

  void _validateLimit(int limitAmount) {
    if (limitAmount <= 0) {
      throw const ValidationException('Batas anggaran harus lebih dari nol.');
    }
    if (limitAmount > 999999999999) {
      throw const ValidationException('Batas anggaran terlalu besar.');
    }
  }

  BudgetProgress _readRow(QueryRow row) {
    return BudgetProgress(
      budget: Budget(
        id: row.read<int>('budget_id'),
        categoryId: row.read<int>('category_id'),
        monthStart: row.read<DateTime>('month_start'),
        limitAmount: row.read<int>('limit_amount'),
        isArchived: row.read<bool>('is_archived'),
        createdAt: row.read<DateTime>('created_at'),
        updatedAt: row.read<DateTime>('updated_at'),
      ),
      categoryName: row.read<String>('category_name'),
      categoryKind: CategoryKind.values.byName(row.read<String>('category_kind')),
      spent: row.read<int>('spent'),
    );
  }
}
