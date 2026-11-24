/// Static application metadata and limits.
abstract final class AppConstants {
  static const String appName = 'FinTrack';
  static const String appTagline = 'Personal Finance Manager';
  static const String appVersion = '1.0.0';

  /// Maximum amount accepted for a single transaction (Rp 1 triliun).
  static const int maxTransactionAmount = 1000000000000;

  /// Auto-lock delay options in seconds.
  ///
  /// The floor is intentionally 10 seconds: a shorter (or zero) delay re-locked
  /// the app on every brief switch to another app, which felt like the PIN was
  /// demanded at random.
  static const List<int> autoLockDelaysSeconds = <int>[
    10,
    30,
    60,
    300,
    900,
  ];

  /// Delay used when the stored preference is missing or no longer offered.
  static const int autoLockDefaultSeconds = 10;

  /// Current backup schema version.
  static const int backupSchemaVersion = 1;
}
