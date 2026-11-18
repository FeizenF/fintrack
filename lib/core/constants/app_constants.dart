/// Static application metadata and limits.
abstract final class AppConstants {
  static const String appName = 'FinTrack';
  static const String appTagline = 'Personal Finance Manager';

  /// Maximum amount accepted for a single transaction (Rp 1 triliun).
  static const int maxTransactionAmount = 1000000000000;

  /// Auto-lock delay options in seconds.
  static const List<int> autoLockDelaysSeconds = <int>[0, 30, 60, 300, 900];

  /// Current backup schema version.
  static const int backupSchemaVersion = 1;
}
