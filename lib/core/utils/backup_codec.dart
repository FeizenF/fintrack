import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../constants/app_constants.dart';

/// A validated, versioned backup document.
class BackupDocument {
  const BackupDocument({
    required this.schemaVersion,
    required this.createdAt,
    required this.tables,
  });

  final int schemaVersion;
  final DateTime createdAt;
  final Map<String, List<Map<String, Object?>>> tables;

  int get totalRows => tables.values.fold(
    0,
    (int sum, List<Map<String, Object?>> rows) => sum + rows.length,
  );
}

/// Versioned backup format plus password-based AES-256-GCM encryption.
///
/// The plain backup is JSON so it stays readable and portable. When the user
/// supplies a password, the same JSON is sealed with a key derived through
/// PBKDF2-HMAC-SHA256; the password itself is never written anywhere.
class BackupCodec {
  const BackupCodec();

  static const String formatName = 'fintrack-backup';
  static const String encryptionAlgorithm = 'AES-256-GCM';
  static const String kdfName = 'PBKDF2-HMAC-SHA256';

  /// Tables captured by a backup, in dependency order for restore.
  static const List<String> tableNames = <String>[
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'savings_goals',
    'savings_contributions',
    'app_settings',
  ];

  static const int _iterations = 210000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _maxBackupBytes = 20 * 1024 * 1024;

  static const Map<String, List<String>> requiredColumns =
      <String, List<String>>{
        'accounts': <String>[
          'id',
          'name',
          'type',
          'initial_balance',
          'note',
          'is_archived',
          'sort_order',
          'created_at',
          'updated_at',
        ],
        'categories': <String>[
          'id',
          'name',
          'kind',
          'icon_key',
          'color_value',
          'is_default',
          'is_archived',
          'sort_order',
          'created_at',
        ],
        'transactions': <String>[
          'id',
          'type',
          'account_id',
          'category_id',
          'to_account_id',
          'amount',
          'transaction_date',
          'note',
          'attachment_path',
          'created_at',
          'updated_at',
        ],
        'budgets': <String>[
          'id',
          'category_id',
          'month_start',
          'limit_amount',
          'is_archived',
          'created_at',
          'updated_at',
        ],
        'savings_goals': <String>[
          'id',
          'name',
          'target_amount',
          'target_date',
          'note',
          'is_archived',
          'created_at',
          'updated_at',
        ],
        'savings_contributions': <String>[
          'id',
          'goal_id',
          'account_id',
          'type',
          'amount',
          'contribution_date',
          'note',
          'created_at',
        ],
        'app_settings': <String>['key', 'value', 'updated_at'],
      };

  static final AesGcm _cipher = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  /// Serialises [tables] into the versioned JSON backup format.
  String encode({
    required DateTime createdAt,
    required Map<String, List<Map<String, Object?>>> tables,
  }) {
    final Map<String, List<Map<String, Object?>>> normalized = _validateTables(
      tables,
    );
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': formatName,
      'schemaVersion': AppConstants.backupSchemaVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'tables': normalized,
    });
  }

  /// Parses and validates a plain backup. Throws [FormatException] when the
  /// file is truncated, from another app, or from an unsupported schema.
  BackupDocument decode(String json) {
    _checkSize(json);
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('File backup bukan JSON yang valid.');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != formatName) {
      throw const FormatException('File ini bukan backup FinTrack.');
    }
    final Object? version = decoded['schemaVersion'];
    if (version is! int) {
      throw const FormatException('Versi skema backup tidak valid.');
    }
    if (version != AppConstants.backupSchemaVersion) {
      throw FormatException(
        'Versi backup $version tidak didukung aplikasi ini '
        '(versi ${AppConstants.backupSchemaVersion}).',
      );
    }
    final DateTime? createdAt = DateTime.tryParse(
      decoded['createdAt'] is String ? decoded['createdAt'] as String : '',
    );
    if (createdAt == null) {
      throw const FormatException('Tanggal backup tidak valid.');
    }
    final Object? rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw const FormatException('Data tabel backup tidak valid.');
    }

    final Map<String, List<Map<String, Object?>>> tables =
        <String, List<Map<String, Object?>>>{};
    for (final String name in tableNames) {
      final Object? rawRows = rawTables[name];
      if (rawRows is! List<Object?>) {
        throw FormatException('Tabel $name tidak ditemukan atau tidak valid.');
      }
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final Object? rawRow in rawRows) {
        if (rawRow is! Map<String, dynamic>) {
          throw FormatException('Baris pada tabel $name tidak valid.');
        }
        rows.add(Map<String, Object?>.from(rawRow));
      }
      tables[name] = rows;
    }

    return BackupDocument(
      schemaVersion: version,
      createdAt: createdAt.toUtc(),
      tables: _validateTables(tables),
    );
  }

  /// Seals [json] with a key derived from [password].
  ///
  /// [randomBytes] exists so tests can produce deterministic envelopes; in the
  /// app it defaults to [Random.secure].
  Future<String> encrypt({
    required String json,
    required String password,
    List<int> Function(int count)? randomBytes,
  }) async {
    _validatePassword(password);
    final List<int> salt = _random(_saltLength, randomBytes);
    final List<int> nonce = _random(_nonceLength, randomBytes);
    final SecretBox box = await _cipher.encrypt(
      utf8.encode(json),
      secretKey: await _deriveKey(password, salt),
      nonce: nonce,
    );
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': formatName,
      'schemaVersion': AppConstants.backupSchemaVersion,
      'encryption': encryptionAlgorithm,
      'kdf': kdfName,
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  /// Opens an encrypted backup and returns the inner JSON, or throws
  /// [FormatException] when the password is wrong or the file was tampered with.
  Future<String> decrypt({
    required String encrypted,
    required String password,
  }) async {
    _validatePassword(password);
    _checkSize(encrypted);
    final Object? decoded;
    try {
      decoded = jsonDecode(encrypted);
    } on FormatException {
      throw const FormatException('File backup terenkripsi rusak.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatName ||
        decoded['schemaVersion'] != AppConstants.backupSchemaVersion ||
        decoded['encryption'] != encryptionAlgorithm ||
        decoded['kdf'] != kdfName ||
        decoded['iterations'] != _iterations) {
      throw const FormatException('Format backup terenkripsi tidak didukung.');
    }
    try {
      final List<int> salt = base64Decode(decoded['salt'] as String);
      final List<int> nonce = base64Decode(decoded['nonce'] as String);
      final List<int> ciphertext = base64Decode(
        decoded['ciphertext'] as String,
      );
      final List<int> mac = base64Decode(decoded['mac'] as String);
      if (salt.length != _saltLength ||
          nonce.length != _nonceLength ||
          mac.length != _tagLength) {
        throw const FormatException('Panjang data enkripsi tidak valid.');
      }
      final List<int> clear = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: await _deriveKey(password, salt),
      );
      return utf8.decode(clear);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Password salah atau file backup rusak.');
    }
  }

  /// True when [json] looks like an encrypted envelope rather than plain JSON.
  bool isEncrypted(String json) {
    try {
      final Object? decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> &&
          decoded['encryption'] == encryptionAlgorithm;
    } on FormatException {
      return false;
    }
  }

  Map<String, List<Map<String, Object?>>> _validateTables(
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    if (tables.keys.any((String key) => !tableNames.contains(key))) {
      throw const FormatException('Backup memuat tabel yang tidak dikenal.');
    }
    for (final String table in tableNames) {
      final List<Map<String, Object?>>? rows = tables[table];
      if (rows == null) {
        throw FormatException('Tabel $table tidak ditemukan.');
      }
      for (int index = 0; index < rows.length; index++) {
        final Map<String, Object?> row = rows[index];
        if (row.keys.any((String key) => !_isSafeIdentifier(key))) {
          throw FormatException('Nama kolom pada $table tidak valid.');
        }
        final List<String> missing = requiredColumns[table]!
            .where((String column) => !row.containsKey(column))
            .toList(growable: false);
        if (missing.isNotEmpty) {
          throw FormatException(
            'Kolom ${missing.join(', ')} hilang pada $table baris ${index + 1}.',
          );
        }
      }
    }
    return <String, List<Map<String, Object?>>>{
      for (final String name in tableNames) name: tables[name]!,
    };
  }

  bool _isSafeIdentifier(String value) =>
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value);

  void _checkSize(String value) {
    if (utf8.encode(value).length > _maxBackupBytes) {
      throw const FormatException('File backup melebihi batas 20 MB.');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 12 || password.length > 256) {
      throw ArgumentError.value(
        password.length,
        'password.length',
        'Password backup harus berisi 12–256 karakter.',
      );
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  List<int> _random(int count, List<int> Function(int count)? randomBytes) =>
      randomBytes?.call(count) ?? _secureRandom(count);

  List<int> _secureRandom(int count) {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(count, (_) => random.nextInt(256)),
    );
  }
}
