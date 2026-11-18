import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/utils/backup_codec.dart';

void main() {
  group('BackupCodec', () {
    const BackupCodec codec = BackupCodec();

    test('creates versioned backup containing all required tables', () {
      final String json = codec.encode(
        createdAt: DateTime.utc(2026, 11, 18),
        tables: <String, List<Map<String, Object?>>>{
          for (final String table in BackupCodec.tableNames)
            table: <Map<String, Object?>>[
              <String, Object?>{
                for (final String column in BackupCodec.requiredColumns[table]!)
                  column: column == 'id' ? 1 : null,
              },
            ],
        },
      );

      final BackupDocument document = codec.decode(json);
      expect(document.schemaVersion, 1);
      expect(document.createdAt, DateTime.utc(2026, 11, 18));
      expect(document.tables.keys, containsAll(BackupCodec.tableNames));
      expect(document.tables['accounts']!.single['id'], 1);
    });

    test('rejects unsupported schema version', () {
      final String json = jsonEncode(<String, Object?>{
        'format': BackupCodec.formatName,
        'schemaVersion': 999,
        'createdAt': '2026-11-18T00:00:00.000Z',
        'tables': <String, Object?>{
          for (final String table in BackupCodec.tableNames) table: <Object?>[],
        },
      });

      expect(() => codec.decode(json), throwsA(isA<FormatException>()));
    });

    test('rejects missing tables and malformed rows', () {
      final String missing = jsonEncode(<String, Object?>{
        'format': BackupCodec.formatName,
        'schemaVersion': 1,
        'createdAt': '2026-11-18T00:00:00.000Z',
        'tables': <String, Object?>{},
      });
      expect(() => codec.decode(missing), throwsA(isA<FormatException>()));

      final String malformed = codec.encode(
        createdAt: DateTime.utc(2026, 11, 18),
        tables: <String, List<Map<String, Object?>>>{
          for (final String table in BackupCodec.tableNames)
            table: <Map<String, Object?>>[],
        },
      );
      final Map<String, Object?> root =
          jsonDecode(malformed) as Map<String, Object?>;
      final Map<String, Object?> tables =
          root['tables']! as Map<String, Object?>;
      tables['accounts'] = <Object?>['not a row'];
      expect(() => codec.decode(jsonEncode(root)),
          throwsA(isA<FormatException>()));
    });

    test('encrypted backup decrypts only with correct password', () async {
      final String encrypted = await codec.encrypt(
        json: '{"private":"account data"}',
        password: 'correct horse battery staple',
        randomBytes: (int count) => List<int>.generate(count, (int i) => i + 1),
      );

      expect(encrypted, contains('AES-256-GCM'));
      expect(
        await codec.decrypt(
          encrypted: encrypted,
          password: 'correct horse battery staple',
        ),
        '{"private":"account data"}',
      );
      expect(
        () => codec.decrypt(encrypted: encrypted, password: 'wrong password'),
        throwsA(anything),
      );
    });

    test('rejects invalid encryption envelope and weak password', () async {
      await expectLater(
        codec.encrypt(json: '{}', password: 'short'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        codec.decrypt(encrypted: '{}', password: 'password'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        codec.decrypt(
          encrypted: '{}',
          password: 'password yang cukup panjang',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
