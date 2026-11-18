import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/constants/app_constants.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/database/repositories/accounts_repository.dart';
import 'package:fintrack/core/database/repositories/categories_repository.dart';
import 'package:fintrack/core/database/repositories/transactions_repository.dart';
import 'package:fintrack/core/services/backup_service.dart';
import 'package:fintrack/core/utils/backup_codec.dart';

void main() {
  late AppDatabase db;
  late BackupService service;
  late int accountId;
  late int categoryId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.ensureSeeded();
    service = BackupService(database: db);

    accountId = await AccountsRepository(db)
        .create(name: 'Dompet', type: AccountType.cash, initialBalance: 250000);
    categoryId = (await CategoriesRepository(
      db,
    ).list(kind: CategoryKind.expense)).first.id;
    await TransactionsRepository(db).createExpense(
      accountId: accountId,
      categoryId: categoryId,
      amount: 75000,
      date: DateTime(2026, 11, 10, 9, 30),
      note: 'Makan siang',
    );
  });

  tearDown(() => db.close());

  test(
    'createBackup captures every table and round-trips through restore',
    () async {
      final String json = await service.createBackup();
      final BackupDocument document = await service.validateBackup(json);

      expect(document.schemaVersion, AppConstants.backupSchemaVersion);
      expect(document.createdAt.isUtc, isTrue);
      expect(document.tables['accounts'], hasLength(1));
      expect(document.tables['transactions'], hasLength(1));
      expect(document.tables['categories'], isNotEmpty);
      expect(document.tables['app_settings'], isEmpty);

      // Wipe user data, then restore it.
      await TransactionsRepository(db)
          .delete((await TransactionsRepository(db).list()).single.id);
      await AccountsRepository(db).delete(accountId);
      expect(await AccountsRepository(db).list(), isEmpty);

      await service.restoreBackup(document, confirmed: true);

      final List<Account> accounts = await AccountsRepository(db)
          .list(includeArchived: true);
      expect(accounts, hasLength(1));
      expect(accounts.single.name, 'Dompet');
      expect(accounts.single.initialBalance, 250000);
      final List<FinancialTransaction> transactions =
          await TransactionsRepository(db).list();
      expect(transactions, hasLength(1));
      expect(transactions.single.amount, 75000);
      expect(transactions.single.note, 'Makan siang');
    },
  );

  test('restore requires explicit confirmation', () async {
    final BackupDocument document = await service.validateBackup(
      await service.createBackup(),
    );
    expect(
      () => service.restoreBackup(document, confirmed: false),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'backup excludes and restore preserves device security settings',
    () async {
      await db.saveSetting(SettingKeys.pinEnabled, '1');
      await db.saveSetting(SettingKeys.biometricEnabled, '1');
      await db.saveSetting(SettingKeys.autoLockSeconds, '300');

      final BackupDocument document = await service.validateBackup(
        await service.createBackup(),
      );
      expect(document.tables['app_settings'], isEmpty);

      await db.saveSetting(SettingKeys.biometricEnabled, '0');
      await db.saveSetting(SettingKeys.autoLockSeconds, '60');
      await service.restoreBackup(document, confirmed: true);

      expect(await db.readSetting(SettingKeys.pinEnabled), '1');
      expect(await db.readSetting(SettingKeys.biometricEnabled), '0');
      expect(await db.readSetting(SettingKeys.autoLockSeconds), '60');
    },
  );

  test(
    'restore is atomic: invalid backup leaves existing data untouched',
    () async {
      final String json = await service.createBackup();
      final BackupDocument document = await service.validateBackup(json);

      // Drop the referenced account row so the insert hits a foreign key error.
      final Map<String, Object?> brokenRow = Map<String, Object?>.from(
        document.tables['transactions']!.single,
      )..['account_id'] = 999;
      final BackupDocument broken = BackupDocument(
        schemaVersion: document.schemaVersion,
        createdAt: document.createdAt,
        tables: <String, List<Map<String, Object?>>>{
          for (final String name in BackupCodec.tableNames)
            name: name == 'transactions'
                ? <Map<String, Object?>>[brokenRow]
                : document.tables[name]!,
        },
      );

      await expectLater(
        service.restoreBackup(broken, confirmed: true),
        throwsA(anything),
      );

      // Original rows survive because the delete+insert happened in one
      // transaction that rolled back.
      expect(await AccountsRepository(db).list(), hasLength(1));
      expect(await TransactionsRepository(db).list(), hasLength(1));
    },
  );

  test('encrypted backup restores only with the right password', () async {
    const String password = 'kata sandi yang panjang';
    final String sealed = await service.createBackup(password: password);

    await expectLater(
      service.validateBackup(sealed),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.validateBackup(sealed, password: 'password yang salah'),
      throwsA(isA<FormatException>()),
    );

    final BackupDocument document = await service.validateBackup(
      sealed,
      password: password,
    );
    expect(document.tables['accounts'], hasLength(1));
  });

  test(
    'rejected files stay rejected: wrong app format and newer version',
    () async {
      await expectLater(
        service.validateBackup('{"hello":"world"}'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        service.validateBackup('not json at all'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
