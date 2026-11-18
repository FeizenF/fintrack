import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/services/backup_service.dart';

void main() {
  test('diag', () async {
    final AppDatabase db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    final AccountsRepository repo = AccountsRepository(db);
    final int id = await repo.create(
      name: 'Dompet',
      type: AccountType.cash,
      initialBalance: 250000,
    );
    final BackupService service = BackupService(database: db);
    final doc = await service.validateBackup(await service.createBackup());
    await repo.delete(id);
    await service.restoreBackup(doc, confirmed: true);

    final List<QueryRow> filtered =
        await db.customSelect('SELECT id FROM accounts WHERE is_archived = 0').get();
    print('sql filtered: ${filtered.length}');

    final List<Account> typed = await db.select(db.accounts).get();
    print('typed all: ${typed.map((a) => '${a.id}:${a.isArchived}').toList()}');

    final List<Account> typedFiltered = await (db.select(db.accounts)
          ..where((t) => t.isArchived.equals(false)))
        .get();
    print('typed filtered: ${typedFiltered.length}');

    await db.close();
  });
}
