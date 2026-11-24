import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import 'package:fintrack/core/constants/app_constants.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/security/security_repository.dart';
import 'package:fintrack/features/settings/presentation/security_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';
import 'package:fintrack/shared/providers/security_providers.dart';

class _FakeSecurityRepository extends SecurityRepository {
  String? _pin;

  @override
  Future<bool> get hasPinRecord async => _pin != null;

  @override
  Future<bool> get hasUsablePinRecord async => _pin != null;

  @override
  Future<void> setPin(String pin) async => _pin = pin;

  @override
  Future<bool> verifyPin(String pin) async => _pin != null && pin == _pin;

  @override
  Future<void> removePin() async => _pin = null;
}

class _FakeLocalAuthentication extends LocalAuthentication {
  _FakeLocalAuthentication({this.hangs = false});

  final bool hangs;

  @override
  Future<bool> isDeviceSupported() {
    if (hangs) return Completer<bool>().future;
    return Future<bool>.value(false);
  }

  @override
  Future<bool> get canCheckBiometrics {
    if (hangs) return Completer<bool>().future;
    return Future<bool>.value(false);
  }
}

Future<AppDatabase> _testDatabase() async {
  final AppDatabase database = AppDatabase.forTesting();
  addTearDown(database.close);
  await database.customSelect('SELECT 1').get();
  await database.ensureSeeded();
  return database;
}

Widget _securityApp(AppDatabase database, LocalAuthentication auth) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((_) async => database),
      securityRepositoryProvider.overrideWithValue(_FakeSecurityRepository()),
      localAuthenticationProvider.overrideWithValue(auth),
    ],
    child: const MaterialApp(home: SecurityPage()),
  );
}

void main() {
  testWidgets('saving a PIN from the security page does not throw', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _testDatabase();

    await tester.pumpWidget(
      _securityApp(database, _FakeLocalAuthentication()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'PIN aplikasi'));
    await tester.pumpAndSettle();
    expect(find.text('Buat PIN aplikasi'), findsOneWidget);

    final Finder fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '1234');
    await tester.enterText(fields.at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    // The old implementation disposed the dialog controllers while the route
    // was still animating out, which surfaced here as an exception.
    expect(tester.takeException(), isNull);
    expect(
      find.text('PIN aktif. Aplikasi akan meminta PIN saat dibuka.'),
      findsOneWidget,
    );
  });

  testWidgets('stalled biometric plugin does not block the settings page', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _testDatabase();

    await tester.pumpWidget(
      _securityApp(database, _FakeLocalAuthentication(hangs: true)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The probe is bounded, so the page leaves its loading spinner even when
    // the platform channel never answers.
    expect(find.text('PIN aplikasi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('auto-lock never offers a delay shorter than 10 seconds', () {
    expect(AppConstants.autoLockDelaysSeconds, isNotEmpty);
    expect(AppConstants.autoLockDelaysSeconds.first, greaterThanOrEqualTo(10));
    expect(AppConstants.autoLockDelaysSeconds, isNot(contains(0)));
    expect(
      AppConstants.autoLockDelaysSeconds,
      contains(AppConstants.autoLockDefaultSeconds),
    );
    // Options must stay ascending so the dropdown reads shortest to longest.
    final List<int> sorted = <int>[...AppConstants.autoLockDelaysSeconds]
      ..sort();
    expect(AppConstants.autoLockDelaysSeconds, sorted);
  });

  testWidgets('security page labels the shortest auto-lock as 10 seconds', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _testDatabase();

    await tester.pumpWidget(_securityApp(database, _FakeLocalAuthentication()));
    await tester.pumpAndSettle();

    // Dropdown shows the selected delay; the shortest option must be seconds
    // based, not the old "Segera setelah keluar" immediate lock.
    expect(find.text('Setelah 10 detik'), findsOneWidget);
    expect(find.text('Segera setelah keluar'), findsNothing);
  });
}
