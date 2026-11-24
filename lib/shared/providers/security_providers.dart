import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/security/security_repository.dart';
import 'database_providers.dart';

final Provider<SecurityRepository> securityRepositoryProvider =
    Provider<SecurityRepository>((Ref ref) => SecurityRepository());

final Provider<LocalAuthentication> localAuthenticationProvider =
    Provider<LocalAuthentication>((Ref ref) => LocalAuthentication());

/// Platform screen-lock prompt, injectable so tests can emulate the OS dialog.
///
/// With `biometricOnly: false` Android and iOS also accept the device PIN,
/// pattern or password, which is what the "lupa PIN" flow relies on.
typedef DeviceAuthenticator =
    Future<bool> Function({
      required String localizedReason,
      required bool biometricOnly,
    });

final Provider<DeviceAuthenticator> deviceAuthenticatorProvider =
    Provider<DeviceAuthenticator>((Ref ref) {
      final LocalAuthentication auth = ref.watch(localAuthenticationProvider);
      return ({
        required String localizedReason,
        required bool biometricOnly,
      }) => auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );
    });

/// Whether any non-empty PIN record exists in platform secure storage.
final FutureProvider<bool> pinRecordExistsProvider = FutureProvider<bool>(
  (Ref ref) => ref.watch(securityRepositoryProvider).hasPinRecord,
);

/// Whether the stored record has a supported format and can be verified.
final FutureProvider<bool> pinRecordUsableProvider = FutureProvider<bool>(
  (Ref ref) => ref.watch(securityRepositoryProvider).hasUsablePinRecord,
);

/// Whether either persisted PIN signal requests protection.
/// Treat mismatched state as enabled so a stale SQLite preference or orphaned
/// secure-storage record cannot silently bypass the lock. Reads that fail throw
/// and leave the gate locked until settings can be loaded.
final FutureProvider<bool> pinProtectionEnabledProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final AppDatabase database = await ref.watch(appDatabaseProvider.future);
  final bool configured =
      await database.readSetting(SettingKeys.pinEnabled) == '1';
  final bool hasRecord = await ref.watch(pinRecordExistsProvider.future);
  // Treat either persisted signal as protection enabled. This fails closed
  // across interrupted writes: a stored PIN must not become an unlock bypass
  // merely because the non-secret SQLite preference was lost or reset.
  return configured || hasRecord;
});

final FutureProvider<bool> biometricProtectionEnabledProvider =
    FutureProvider<bool>((Ref ref) async {
      final AppDatabase database = await ref.watch(appDatabaseProvider.future);
      final bool configured =
          await database.readSetting(SettingKeys.biometricEnabled) == '1';
      return configured && await ref.read(pinProtectionEnabledProvider.future);
    });

final FutureProvider<int> autoLockSecondsProvider = FutureProvider<int>((
  Ref ref,
) async {
  final AppDatabase database = await ref.watch(appDatabaseProvider.future);
  final int? configured = int.tryParse(
    await database.readSetting(SettingKeys.autoLockSeconds) ?? '',
  );
  // A stored 0 (or any value no longer offered) falls back to the 10 second
  // floor instead of "lock immediately", which is what made the app demand a
  // PIN after a two-second glance at another app.
  return AppConstants.autoLockDelaysSeconds.contains(configured)
      ? configured!
      : AppConstants.autoLockDefaultSeconds;
});

/// Upper bound for a biometric capability probe.
///
/// Platform channels can stall instead of failing (for example when the plugin
/// is not registered in tests or unsupported platforms). Without a bound the
/// security settings page stayed on its loading spinner forever.
const Duration _biometricProbeTimeout = Duration(seconds: 2);

Future<bool> _probeBiometrics(LocalAuthentication auth) async {
  if (!await auth.isDeviceSupported()) return false;
  return auth.canCheckBiometrics;
}

/// Best-effort check for biometric hardware and enrollment.
///
/// Never throws and never hangs, so callers can await it while loading a page.
Future<bool> biometricsAvailable(WidgetRef ref) async {
  try {
    final LocalAuthentication auth = ref.read(localAuthenticationProvider);
    return await _probeBiometrics(auth).timeout(_biometricProbeTimeout);
  } on Object {
    return false;
  }
}

Future<bool> authenticateWithBiometrics(WidgetRef ref) async {
  if (!await ref.read(biometricProtectionEnabledProvider.future)) {
    return false;
  }
  if (!await biometricsAvailable(ref)) {
    return false;
  }
  try {
    return await ref
        .read(localAuthenticationProvider)
        .authenticate(
          localizedReason: 'Autentikasi untuk membuka FinTrack.',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
  } on Object {
    return false;
  }
}

/// Verifies the device owner with the platform screen lock.
///
/// Used by the "lupa PIN" flow. Passing `biometricOnly: false` also accepts the
/// device PIN, pattern or password, so a forgotten app PIN can be replaced
/// without deleting the ledger. Never throws and never hangs.
Future<bool> authenticateWithDeviceCredentials(WidgetRef ref) async {
  try {
    return await ref.read(deviceAuthenticatorProvider)(
      localizedReason: 'Verifikasi perangkat untuk membuat PIN baru FinTrack.',
      biometricOnly: false,
    );
  } on Object {
    return false;
  }
}
