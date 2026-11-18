import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'enums.dart';
import 'seed/default_data.dart';
import 'tables/accounts_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/savings_contributions_table.dart';
import 'tables/savings_goals_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

/// SQLite schema version. Bump together with a [MigrationStrategy] step.
///
/// * 1 — initial schema (seven tables, indexes, constraints).
/// * 2 — triggers enforcing that a transaction's category kind matches its type.
/// * 3 — index for incoming-transfer lookups during account-balance calculation.
const int appDatabaseSchemaVersion = 3;

/// Triggers that keep cross-table invariants SQLite `CHECK` constraints cannot
/// express. They are created for new databases and added by the upgrade path,
/// so a direct SQL write cannot bypass the rule.
const List<String> _integrityTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS trg_transactions_category_kind_insert
BEFORE INSERT ON transactions
FOR EACH ROW WHEN NEW.category_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Kategori tidak sesuai jenis transaksi')
  WHERE (SELECT kind FROM categories WHERE id = NEW.category_id) IS NOT NEW.type;
END
''',
  '''
CREATE TRIGGER IF NOT EXISTS trg_transactions_category_kind_update
BEFORE UPDATE OF category_id, type ON transactions
FOR EACH ROW WHEN NEW.category_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Kategori tidak sesuai jenis transaksi')
  WHERE (SELECT kind FROM categories WHERE id = NEW.category_id) IS NOT NEW.type;
END
''',
];

/// Setting keys used by the app.
abstract final class SettingKeys {
  static const String themeMode = 'theme_mode';
  static const String hideBalances = 'hide_balances';
  static const String pinEnabled = 'pin_enabled';
  static const String biometricEnabled = 'biometric_enabled';
  static const String autoLockSeconds = 'auto_lock_seconds';
  static const String lastBackupAt = 'last_backup_at';
  static const String onboardingDone = 'onboarding_done';
}

@DriftDatabase(
  tables: <Type>[
    Accounts,
    Categories,
    Transactions,
    Budgets,
    SavingsGoals,
    SavingsContributions,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database used by tests. Foreign key enforcement matches the
  /// production executor so constraint tests are meaningful.
  factory AppDatabase.forTesting() {
    return AppDatabase(NativeDatabase.memory(setup: _applyPragmas));
  }

  /// File-backed database at [file]. Used by the app and by backup tests.
  factory AppDatabase.atFile(File file) {
    return AppDatabase(NativeDatabase(file, setup: _applyPragmas));
  }

  static void _applyPragmas(Database database) {
    // SQLite disables foreign keys per connection by default. Drift only emits
    // the pragma for `beforeOpen` on non-memory executors, so apply it here.
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA journal_mode = WAL');
  }

  @override
  int get schemaVersion => appDatabaseSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIntegrityTriggers();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _createIntegrityTriggers();
      }
      if (from < 3) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_to_account_date '
          'ON transactions (to_account_id, transaction_date)',
        );
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) {
        await ensureSeeded();
      }
    },
  );

  Future<void> _createIntegrityTriggers() async {
    for (final String sql in _integrityTriggers) {
      await customStatement(sql);
    }
  }

  /// Inserts the default category set exactly once. Safe to call repeatedly.
  Future<void> ensureSeeded() async {
    final int existing = await categories.count().getSingle();
    if (existing > 0) return;

    final List<DefaultCategorySeed> seeds = defaultCategorySeeds();
    await batch((Batch batch) {
      batch.insertAll(
        categories,
        seeds.map(
          (DefaultCategorySeed seed) => CategoriesCompanion.insert(
            name: seed.name,
            kind: seed.kind,
            iconKey: Value(seed.iconKey),
            colorValue: Value(seed.colorValue),
            isDefault: const Value(true),
            sortOrder: Value(seed.sortOrder),
          ),
        ),
      );
    });
  }

  /// Reads a preference value, or `null` when unset.
  Future<String?> readSetting(String key) async {
    final AppSetting? row = await (select(
      appSettings,
    )..where((AppSettings t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Inserts or replaces a preference value.
  Future<void> saveSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Removes a preference value.
  Future<void> deleteSetting(String key) async {
    await (delete(
      appSettings,
    )..where((AppSettings t) => t.key.equals(key))).go();
  }

  /// Convenience accessor used by seeding code and settings.
  Future<int> countRows(TableInfo<Table, dynamic> table) async {
    final QueryRow row = await customSelect(
      'SELECT COUNT(*) AS c FROM ${table.actualTableName}',
    ).getSingle();
    return row.read<int>('c');
  }

  /// Location of the app database inside the platform application-support
  /// directory. Kept here so backup/restore resolves the same path.
  static Future<File> defaultDatabaseFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'fintrack.sqlite'));
  }
}
