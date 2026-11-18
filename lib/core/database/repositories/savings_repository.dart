import 'package:drift/drift.dart';

import '../../errors/app_exception.dart';
import '../../utils/formatters.dart';
import '../app_database.dart';
import '../enums.dart';

/// One savings goal joined with the net amount already set aside for it.
class SavingsProgress {
  const SavingsProgress({required this.goal, required this.saved});

  final SavingsGoal goal;

  /// Signed sum of the goal's contributions: deposits minus withdrawals.
  final int saved;

  int get target => goal.targetAmount;

  int get remaining => target - saved;

  /// Fraction of the target already saved. Can exceed 1 once completed.
  double get ratio => target == 0 ? 0 : saved / target;

  bool get isComplete => saved >= target;
}

/// Data access for savings goals and their contribution ledger.
///
/// A contribution always references both a goal and an account, so the saved
/// total and the account balance are both derived from one row and can never
/// disagree.
class SavingsRepository {
  SavingsRepository(this._db);

  final AppDatabase _db;

  Stream<List<SavingsProgress>> watch({bool includeArchived = false}) {
    final String sql =
        '''
SELECT
  g.id AS goal_id,
  g.name AS goal_name,
  g.target_amount AS target_amount,
  g.target_date AS target_date,
  g.note AS note,
  g.is_archived AS is_archived,
  g.created_at AS created_at,
  g.updated_at AS updated_at,
  COALESCE((
    SELECT SUM(CASE WHEN s.type = ? THEN s.amount ELSE -s.amount END)
    FROM savings_contributions s
    WHERE s.goal_id = g.id
  ), 0) AS saved
FROM savings_goals g
${includeArchived ? '' : 'WHERE g.is_archived = 0'}
ORDER BY g.is_archived, g.target_date IS NULL, g.target_date, g.name
''';

    return _db
        .customSelect(
          sql,
          variables: <Variable<Object>>[
            Variable<String>(SavingsEntryType.deposit.name),
          ],
          readsFrom: <TableInfo<Table, Object?>>{
            _db.savingsGoals,
            _db.savingsContributions,
          },
        )
        .watch()
        .map(
          (List<QueryRow> rows) => rows.map(_readRow).toList(growable: false),
        );
  }

  Future<List<SavingsProgress>> progress({bool includeArchived = false}) =>
      watch(includeArchived: includeArchived).first;

  Future<SavingsGoal?> goalById(int id) {
    return (_db.select(
      _db.savingsGoals,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createGoal({
    required String name,
    required int targetAmount,
    DateTime? targetDate,
    String? note,
  }) async {
    final String cleanName = _validateName(name);
    _validatePositive(targetAmount, 'Target');
    _validateDate(targetDate);

    return _db
        .into(_db.savingsGoals)
        .insert(
          SavingsGoalsCompanion.insert(
            name: cleanName,
            targetAmount: targetAmount,
            targetDate: Value(targetDate),
            note: Value(_cleanNote(note)),
          ),
        );
  }

  Future<void> updateGoal(
    int id, {
    required String name,
    required int targetAmount,
    DateTime? targetDate,
    String? note,
  }) async {
    if (await goalById(id) == null) {
      throw const NotFoundException('Target tabungan tidak ditemukan.');
    }
    final String cleanName = _validateName(name);
    _validatePositive(targetAmount, 'Target');
    _validateDate(targetDate);

    await (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
      SavingsGoalsCompanion(
        name: Value(cleanName),
        targetAmount: Value(targetAmount),
        targetDate: Value(targetDate),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setGoalArchived(int id, bool archived) async {
    final int updated =
        await (_db.update(
          _db.savingsGoals,
        )..where((t) => t.id.equals(id))).write(
          SavingsGoalsCompanion(
            isArchived: Value(archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) {
      throw const NotFoundException('Target tabungan tidak ditemukan.');
    }
  }

  /// Deletes a goal that has no contributions. Goals with history are archived
  /// instead so past deposits stay accountable.
  Future<void> deleteGoal(int id) async {
    if (await goalById(id) == null) {
      throw const NotFoundException('Target tabungan tidak ditemukan.');
    }
    final QueryRow row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM savings_contributions WHERE goal_id = ?',
          variables: <Variable<Object>>[Variable<int>(id)],
        )
        .getSingle();
    if (row.read<int>('c') > 0) {
      throw const ValidationException(
        'Target sudah memiliki setoran. Arsipkan target agar riwayat tetap utuh.',
      );
    }
    await (_db.delete(_db.savingsGoals)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deposit({
    required int goalId,
    required int accountId,
    required int amount,
    required DateTime date,
    String? note,
  }) => _addContribution(
    goalId: goalId,
    accountId: accountId,
    amount: amount,
    date: date,
    type: SavingsEntryType.deposit,
    note: note,
  );

  Future<int> withdraw({
    required int goalId,
    required int accountId,
    required int amount,
    required DateTime date,
    String? note,
  }) => _addContribution(
    goalId: goalId,
    accountId: accountId,
    amount: amount,
    date: date,
    type: SavingsEntryType.withdrawal,
    note: note,
  );

  Future<int> _addContribution({
    required int goalId,
    required int accountId,
    required int amount,
    required DateTime date,
    required SavingsEntryType type,
    required String? note,
  }) async {
    _validatePositive(amount, 'Nominal');
    if (date.isBefore(DateTime(1900))) {
      throw const ValidationException('Tanggal setoran tidak valid.');
    }

    final SavingsGoal? goal = await goalById(goalId);
    if (goal == null) {
      throw const ValidationException('Target tabungan tidak ditemukan.');
    }
    if (goal.isArchived) {
      throw const ValidationException('Target tabungan sudah diarsipkan.');
    }

    final Account? account = await (_db.select(
      _db.accounts,
    )..where((t) => t.id.equals(accountId))).getSingleOrNull();
    if (account == null) {
      throw const ValidationException('Akun tidak ditemukan.');
    }
    if (account.isArchived) {
      throw const ValidationException(
        'Akun sudah diarsipkan. Pilih akun lain.',
      );
    }

    return _db.transaction<int>(() async {
      // The saved amount and the new row must be read/written in one
      // transaction, otherwise two concurrent withdrawals could each pass the
      // check and overdraw the goal.
      if (type == SavingsEntryType.withdrawal) {
        final int saved = await _savedAmount(goalId);
        if (amount > saved) {
          throw ValidationException(
            'Penarikan melebihi dana terkumpul (${Formatters.currency(saved)}).',
          );
        }
      }

      return _db
          .into(_db.savingsContributions)
          .insert(
            SavingsContributionsCompanion.insert(
              goalId: goalId,
              accountId: accountId,
              type: type,
              amount: amount,
              contributionDate: date,
              note: Value(_cleanNote(note)),
            ),
          );
    });
  }

  Future<int> _savedAmount(int goalId) async {
    final QueryRow row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE -amount END),'
          ' 0) AS saved FROM savings_contributions WHERE goal_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(SavingsEntryType.deposit.name),
            Variable<int>(goalId),
          ],
        )
        .getSingle();
    return row.read<int>('saved');
  }

  SavingsProgress _readRow(QueryRow row) {
    return SavingsProgress(
      goal: SavingsGoal(
        id: row.read<int>('goal_id'),
        name: row.read<String>('goal_name'),
        targetAmount: row.read<int>('target_amount'),
        targetDate: row.readNullable<DateTime>('target_date'),
        note: row.readNullable<String>('note'),
        isArchived: row.read<bool>('is_archived'),
        createdAt: row.read<DateTime>('created_at'),
        updatedAt: row.read<DateTime>('updated_at'),
      ),
      saved: row.read<int>('saved'),
    );
  }

  String _validateName(String value) {
    final String name = value.trim();
    if (name.isEmpty) {
      throw const ValidationException('Nama target wajib diisi.');
    }
    if (name.length > 80) {
      throw const ValidationException('Nama target maksimal 80 karakter.');
    }
    return name;
  }

  void _validatePositive(int amount, String field) {
    if (amount <= 0) {
      throw ValidationException('$field harus lebih dari nol.');
    }
    if (amount > 999999999999) {
      throw ValidationException('$field terlalu besar.');
    }
  }

  void _validateDate(DateTime? date) {
    if (date != null && date.isBefore(DateTime(1900))) {
      throw const ValidationException('Tanggal target tidak valid.');
    }
  }

  String? _cleanNote(String? note) {
    final String? value = note?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
