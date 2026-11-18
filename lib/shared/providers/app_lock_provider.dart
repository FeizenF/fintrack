import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'security_providers.dart';

/// Whether the app content is currently unlocked for this session.
///
/// The lock is opt-in: when no PIN is configured the gate never blocks. State
/// is intentionally in memory only, so killing the process re-locks the app.
class AppLockController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;

  void reset() {
    state = false;
    ref.invalidate(pinRecordExistsProvider);
    ref.invalidate(pinRecordUsableProvider);
    ref.invalidate(pinProtectionEnabledProvider);
    ref.invalidate(biometricProtectionEnabledProvider);
    ref.invalidate(autoLockSecondsProvider);
  }
}

final NotifierProvider<AppLockController, bool> appLockControllerProvider =
    NotifierProvider<AppLockController, bool>(AppLockController.new);
