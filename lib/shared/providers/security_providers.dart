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
  return AppConstants.autoLockDelaysSeconds.contains(configured)
      ? configured!
      : 0;
});

Future<bool> authenticateWithBiometrics(WidgetRef ref) async {
  if (!await ref.read(biometricProtectionEnabledProvider.future)) {
    return false;
  }
  final LocalAuthentication auth = ref.read(localAuthenticationProvider);
  if (!await auth.isDeviceSupported() || !await auth.canCheckBiometrics) {
    return false;
  }
  return auth.authenticate(
    localizedReason: 'Autentikasi untuk membuka FinTrack.',
    biometricOnly: true,
    persistAcrossBackgrounding: true,
  );
}
