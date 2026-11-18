import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/services/backup_service.dart';

void main() {
  test('backup restore preserves active account rows', () async {
    final AppDatabase db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    final AccountsRepository repo = AccountsRepository(db);
    final int id = await repo.create(
      name: 'Dompet',
      type: AccountType.cash,
      initialBalance: 250000,
    );
    final BackupService service = BackupService(database: db);
    final document = await service.validateBackup(await service.createBackup());
    await repo.delete(id);
    expect(await repo.list(), isEmpty);

    await service.restoreBackup(document, confirmed: true);

    final List<Account> restored = await repo.list();
    expect(restored, hasLength(1));
    expect(restored.single.id, id);
    expect(restored.single.name, 'Dompet');
  });
}
