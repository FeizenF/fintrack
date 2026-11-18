import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pin_hasher.dart';

/// Device-local secrets. This storage must never be included in app backups.
class SecurityRepository {
  SecurityRepository({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    PinHasher pinHasher = const PinHasher(),
  }) : _storage = storage,
       _pinHasher = pinHasher;

  static const String pinRecordKey = 'fintrack.security.pin_record.v1';

  final FlutterSecureStorage _storage;
  final PinHasher _pinHasher;

  Future<bool> get hasPinRecord async {
    final String? record = await _storage.read(key: pinRecordKey);
    return record != null && record.isNotEmpty;
  }

  Future<bool> get hasUsablePinRecord async {
    final String? record = await _storage.read(key: pinRecordKey);
    return record != null && PinHasher.isWellFormedRecord(record);
  }

  Future<void> setPin(String pin) async {
    final String record = await _pinHasher.hash(pin);
    await _storage.write(key: pinRecordKey, value: record);
  }

  Future<bool> verifyPin(String pin) async {
    final String? record = await _storage.read(key: pinRecordKey);
    if (record == null) return false;
    return _pinHasher.verify(pin, record);
  }

  Future<void> removePin() => _storage.delete(key: pinRecordKey);
}
