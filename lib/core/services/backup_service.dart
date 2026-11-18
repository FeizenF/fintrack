import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import '../utils/backup_codec.dart';

const Set<String> _deviceSecuritySettingKeys = <String>{
  SettingKeys.pinEnabled,
  SettingKeys.biometricEnabled,
  SettingKeys.autoLockSeconds,
};

/// Database export and atomic restore coordinator.
class BackupService {
  BackupService({required AppDatabase database, BackupCodec codec = const BackupCodec()})
    : _database = database,
      _codec = codec;

  final AppDatabase _database;
  final BackupCodec _codec;

  /// Read every backup table in FK-independent order under one read transaction.
  ///
  /// Device security preferences (`pin_enabled`, `biometric_enabled`,
  /// `auto_lock_seconds`) are intentionally excluded: they describe this
  /// installation, and importing them from a file could silently weaken the
  /// lock the user configured on this device.
  Future<String> createBackup({String? password}) async {
    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    await _database.transaction(() async {
      for (final String name in BackupCodec.tableNames) {
        final String orderColumn = name == 'app_settings' ? 'key' : 'id';
        final List<QueryRow> rows = await _database
            .customSelect('SELECT * FROM $name ORDER BY $orderColumn')
            .get();
        tables[name] = rows
            .map((QueryRow row) => Map<String, Object?>.from(row.data))
            .where((Map<String, Object?> row) => !_isDeviceSecurityRow(name, row))
            .toList();
      }
    });
    final String json = _codec.encode(createdAt: DateTime.now(), tables: tables);
    return password == null
        ? json
        : _codec.encrypt(json: json, password: password);
  }

  static bool _isDeviceSecurityRow(String table, Map<String, Object?> row) =>
      table == 'app_settings' &&
      _deviceSecuritySettingKeys.contains(row['key']);

  /// Validate contents before returning metadata; does not modify database.
  Future<BackupDocument> validateBackup(
    String fileContents, {
    String? password,
  }) async {
    final String plain = _codec.isEncrypted(fileContents)
        ? await _codec.decrypt(
            encrypted: fileContents,
            password: password ?? (throw const FormatException('Backup memerlukan password.')),
          )
        : fileContents;
    return _codec.decode(plain);
  }

  /// Replaces current data after explicit confirmation. All table deletes and
  /// inserts share one SQLite transaction, so failed FK/constraint validation
  /// restores prior database contents.
  Future<void> restoreBackup(
    BackupDocument document, {
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('Pemulihan belum dikonfirmasi.');
    // Re-encode/decode to make sure caller cannot construct a forged document.
    if (document.schemaVersion != AppConstants.backupSchemaVersion) {
      throw FormatException(
        'Versi backup ${document.schemaVersion} tidak didukung aplikasi ini.',
      );
    }
    final BackupDocument validated = _codec.decode(
      _codec.encode(createdAt: document.createdAt, tables: document.tables),
    );
    await _database.transaction(() async {
      final List<QueryRow> localSecurityRows = await _database.customSelect(
        'SELECT * FROM app_settings WHERE key IN (?, ?, ?)',
        variables: <Variable<Object>>[
          Variable<String>(SettingKeys.pinEnabled),
          Variable<String>(SettingKeys.biometricEnabled),
          Variable<String>(SettingKeys.autoLockSeconds),
        ],
      ).get();
      for (final String name in BackupCodec.tableNames.reversed) {
        await _database.customUpdate(
          'DELETE FROM $name',
          updates: <TableInfo<Table, Object?>>{_table(name)},
        );
      }
      for (final String name in BackupCodec.tableNames) {
        for (final Map<String, Object?> sourceRow in validated.tables[name]!) {
          if (_isDeviceSecurityRow(name, sourceRow)) continue;
          final Map<String, Object?> row = sourceRow;
          final List<String> columns = row.keys.toList(growable: false);
          final String quotedColumns = columns.map(_quoteIdentifier).join(', ');
          final String placeholders = List<String>.filled(
            columns.length,
            '?',
          ).join(', ');
          final List<Object?> values = columns
              .map((String column) => row[column])
              .toList(growable: false);
          await _database.customInsert(
            'INSERT INTO $name ($quotedColumns) VALUES ($placeholders)',
            variables: <Variable<Object>>[
              for (final Object? value in values) Variable<Object>(value),
            ],
            updates: <TableInfo<Table, Object?>>{_table(name)},
          );
        }
      }
      for (final QueryRow localRow in localSecurityRows) {
        await _database.customInsert(
          'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)',
          variables: <Variable<Object>>[
            Variable<String>(localRow.read<String>('key')),
            Variable<String>(localRow.read<String>('value')),
            Variable<int>(localRow.read<int>('updated_at')),
          ],
          updates: <TableInfo<Table, Object?>>{_database.appSettings},
        );
      }
    });
  }

  TableInfo<Table, Object?> _table(String name) => switch (name) {
    'accounts' => _database.accounts,
    'categories' => _database.categories,
    'transactions' => _database.transactions,
    'budgets' => _database.budgets,
    'savings_goals' => _database.savingsGoals,
    'savings_contributions' => _database.savingsContributions,
    'app_settings' => _database.appSettings,
    _ => throw StateError('Unexpected backup table: $name'),
  };

  static String _quoteIdentifier(String value) => '"$value"';

  /// Writes backup bytes through a caller-selected URI. Supports local files;
  /// platform save dialogs may instead save bytes directly via file_picker.
  Future<void> writeLocalFile(File file, String contents) =>
      file.writeAsBytes(utf8.encode(contents), flush: true);
}
