import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/security/app_lock_gate.dart';
import 'package:fintrack/core/security/security_repository.dart';
import 'package:fintrack/shared/providers/app_lock_provider.dart';
import 'package:fintrack/shared/providers/database_providers.dart';
import 'package:fintrack/shared/providers/security_providers.dart';

class _FakeSecurityRepository extends SecurityRepository {
  _FakeSecurityRepository({this.initialPin});

  final String? initialPin;
  String? _pin;
  bool _mutated = false;

  String? get _currentPin => _mutated ? _pin : initialPin;

  @override
  Future<bool> get hasPinRecord async => _currentPin != null;

  @override
  Future<bool> get hasUsablePinRecord async =>
      _currentPin != null &&
      _currentPin != 'MALFORMED' &&
      _currentPin != 'CORRUPT';

  @override
  Future<void> setPin(String pin) async {
    _mutated = true;
    _pin = pin;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final String? current = _currentPin;
    return current != null && pin == current;
  }

  @override
  Future<void> removePin() async {
    _mutated = true;
    _pin = null;
  }
}

Widget _buildGateApp({
  required SecurityRepository repository,
  required bool pinEnabled,
  required bool biometricEnabled,
  bool autoLockFails = false,
  Widget? child,
}) {
  return ProviderScope(
    overrides: [
      securityRepositoryProvider.overrideWithValue(repository),
      pinProtectionEnabledProvider.overrideWith((_) async => pinEnabled),
      biometricProtectionEnabledProvider.overrideWith(
        (_) async => biometricEnabled,
      ),
      autoLockSecondsProvider.overrideWith((_) async {
        if (autoLockFails) throw StateError('settings unavailable');
        return 0;
      }),
    ],
    child: MaterialApp(
      home: AppLockGate(child: child ?? const Text('UNLOCKED_CONTENT')),
    ),
  );
}

void main() {
  testWidgets('AppLockGate shows child directly when PIN is disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildGateApp(
        repository: _FakeSecurityRepository(),
        pinEnabled: false,
        biometricEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
    expect(find.text('FinTrack terkunci'), findsNothing);
  });

  testWidgets('AppLockGate blocks with lock screen and unlocks on valid PIN', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildGateApp(
        repository: _FakeSecurityRepository(initialPin: '1234'),
        pinEnabled: true,
        biometricEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FinTrack terkunci'), findsOneWidget);
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);
    expect(find.text('Gunakan biometrik'), findsNothing);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
    expect(find.text('FinTrack terkunci'), findsNothing);
  });

  testWidgets('AppLockGate rejects invalid PIN and stays locked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildGateApp(
        repository: _FakeSecurityRepository(initialPin: '1234'),
        pinEnabled: true,
        biometricEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('PIN salah.'), findsOneWidget);
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);
  });

  testWidgets('AppLockGate fails closed when PIN setting cannot load', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pinProtectionEnabledProvider.overrideWith(
            (_) async => throw StateError('storage unavailable'),
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('UNLOCKED_CONTENT')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pengaturan keamanan tidak dapat dibaca.'),
      findsOneWidget,
    );
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);
  });

  testWidgets('reset invalidates cached auto-lock preference', (
    WidgetTester tester,
  ) async {
    int autoLockReads = 0;
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(),
          ),
          pinProtectionEnabledProvider.overrideWith((_) async => false),
          biometricProtectionEnabledProvider.overrideWith((_) async => false),
          autoLockSecondsProvider.overrideWith((Ref ref) {
            autoLockReads++;
            return Future<int>.value(300);
          }),
        ],
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: SizedBox.shrink());
          },
        ),
      ),
    );
    await container.read(autoLockSecondsProvider.future);
    expect(autoLockReads, 1);

    container.read(appLockControllerProvider.notifier).reset();
    await tester.pump();
    await container.read(autoLockSecondsProvider.future);
    expect(autoLockReads, 2);
  });

  testWidgets('AppLockGate locks immediately if auto-lock preference fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildGateApp(
        repository: _FakeSecurityRepository(initialPin: '1234'),
        pinEnabled: true,
        biometricEnabled: false,
        autoLockFails: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('FinTrack terkunci'), findsOneWidget);
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);
  });

  testWidgets('malformed PIN record requires confirmed local data reset', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = AppDatabase.forTesting();
    addTearDown(database.close);
    await database.customSelect('SELECT 1').get();
    await database.ensureSeeded();
    await database.saveSetting(SettingKeys.pinEnabled, '1');
    final _FakeSecurityRepository repository = _FakeSecurityRepository(
      initialPin: 'CORRUPT',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => database),
          securityRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('UNLOCKED_CONTENT')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('PIN tidak tersedia'), findsOneWidget);
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);

    await tester.tap(find.text('Pulihkan akses dengan menghapus data lokal'));
    await tester.pumpAndSettle();
    expect(find.text('Atur ulang kunci aplikasi?'), findsOneWidget);
    expect(find.text('UNLOCKED_CONTENT'), findsNothing);

    await tester.tap(find.text('Hapus data dan reset'));
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
    expect(await database.readSetting(SettingKeys.pinEnabled), isNull);
    expect(await database.countRows(database.accounts), 0);
    expect(await database.countRows(database.categories), greaterThan(0));
  });
}
