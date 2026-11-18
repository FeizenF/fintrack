import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/core/database/enums.dart';
import 'package:fintrack/core/security/app_lock_gate.dart';
import 'package:fintrack/core/security/security_repository.dart';
import 'package:fintrack/core/services/attachment_cleanup_service.dart';
import 'package:fintrack/shared/providers/app_lock_provider.dart';
import 'package:fintrack/shared/providers/attachment_cleanup_providers.dart';
import 'package:fintrack/shared/providers/database_providers.dart';
import 'package:fintrack/shared/providers/security_providers.dart';

class _RecordingAttachmentCleanupService extends AttachmentCleanupService {
  int cleanupCalls = 0;
  bool throwsOnDelete = false;
  List<String> failedPaths = const <String>[];
  Future<void> Function()? onCleanup;

  @override
  Future<AttachmentCleanupResult> deleteOwnedAttachments() async {
    cleanupCalls++;
    await onCleanup?.call();
    if (throwsOnDelete) throw FileSystemException('cleanup failed');
    return AttachmentCleanupResult(deletedCount: 0, failedPaths: failedPaths);
  }
}

class _FakeSecurityRepository extends SecurityRepository {
  _FakeSecurityRepository({this.initialPin, this.removePinFails = false});

  final String? initialPin;
  final bool removePinFails;
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
    if (removePinFails) throw StateError('secure storage unavailable');
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

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final String digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
}

Future<AppDatabase> _seededDatabase({String? attachmentPath}) async {
  final AppDatabase database = AppDatabase.forTesting();
  await database.customSelect('SELECT 1').get();
  await database.ensureSeeded();
  await database.saveSetting(SettingKeys.pinEnabled, '1');
  final int categoryId = (await (database.select(
    database.categories,
  )..where((row) => row.name.equals('Makanan'))).getSingle()).id;
  final int accountId = await database
      .into(database.accounts)
      .insert(
        AccountsCompanion.insert(name: 'Dompet', type: AccountType.cash),
      );
  await database
      .into(database.transactions)
      .insert(
        TransactionsCompanion.insert(
          type: TransactionType.expense,
          accountId: accountId,
          categoryId: Value<int>(categoryId),
          amount: 100,
          transactionDate: DateTime(2026, 1, 1),
          attachmentPath: Value<String?>(attachmentPath),
        ),
      );
  return database;
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
    expect(find.byIcon(Icons.fingerprint_rounded), findsNothing);

    await _enterPin(tester, '1234');

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

    await _enterPin(tester, '9999');

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
    await _enterPin(tester, '1234');
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
    final AppDatabase database = await _seededDatabase(
      attachmentPath: '/private/attachments/receipt.jpg',
    );
    addTearDown(database.close);
    final _RecordingAttachmentCleanupService cleanupService =
        _RecordingAttachmentCleanupService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => database),
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(initialPin: 'CORRUPT'),
          ),
          attachmentCleanupServiceProvider.overrideWithValue(cleanupService),
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
    expect(cleanupService.cleanupCalls, 1);
    expect(find.textContaining('lampiran gagal'), findsNothing);
  });

  testWidgets('attachment cleanup runs after local data wipe', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _seededDatabase(
      attachmentPath: '/private/attachments/receipt.jpg',
    );
    addTearDown(database.close);
    int? transactionsDuringCleanup;
    final _RecordingAttachmentCleanupService cleanupService =
        _RecordingAttachmentCleanupService()
          ..onCleanup = () async {
            transactionsDuringCleanup = await database.countRows(
              database.transactions,
            );
          };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => database),
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(initialPin: 'CORRUPT'),
          ),
          attachmentCleanupServiceProvider.overrideWithValue(cleanupService),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('UNLOCKED_CONTENT')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan akses dengan menghapus data lokal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus data dan reset'));
    await tester.pumpAndSettle();

    expect(transactionsDuringCleanup, 0);
  });

  testWidgets('attachment cleanup failure does not block completed reset', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _seededDatabase(
      attachmentPath: '/private/attachments/receipt.jpg',
    );
    addTearDown(database.close);
    final _RecordingAttachmentCleanupService cleanupService =
        _RecordingAttachmentCleanupService()..throwsOnDelete = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => database),
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(initialPin: 'CORRUPT'),
          ),
          attachmentCleanupServiceProvider.overrideWithValue(cleanupService),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AppLockGate(child: Text('UNLOCKED_CONTENT'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan akses dengan menghapus data lokal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus data dan reset'));
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
    expect(await database.countRows(database.accounts), 0);
    expect(cleanupService.cleanupCalls, 1);
    expect(
      find.textContaining('penghapusan lampiran gagal'),
      findsOneWidget,
    );
  });

  testWidgets('failed attachment deletion warns but completes reset', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = await _seededDatabase(
      attachmentPath: '/private/attachments/receipt.jpg',
    );
    addTearDown(database.close);
    final _RecordingAttachmentCleanupService cleanupService =
        _RecordingAttachmentCleanupService()
          ..failedPaths = const <String>['/private/attachments/receipt.jpg'];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => database),
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(initialPin: 'CORRUPT'),
          ),
          attachmentCleanupServiceProvider.overrideWithValue(cleanupService),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AppLockGate(child: Text('UNLOCKED_CONTENT'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan akses dengan menghapus data lokal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus data dan reset'));
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
    expect(await database.countRows(database.accounts), 0);
    expect(
      find.textContaining('1 lampiran gagal'),
      findsOneWidget,
    );
  });

  testWidgets(
    'PIN removal failure keeps local data intact for recovery retry',
    (WidgetTester tester) async {
      final AppDatabase database = await _seededDatabase();
      addTearDown(database.close);
      final _RecordingAttachmentCleanupService cleanupService =
          _RecordingAttachmentCleanupService();
      final _FakeSecurityRepository repository = _FakeSecurityRepository(
        initialPin: 'CORRUPT',
        removePinFails: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((_) async => database),
            securityRepositoryProvider.overrideWithValue(repository),
            attachmentCleanupServiceProvider.overrideWithValue(cleanupService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AppLockGate(child: Text('UNLOCKED_CONTENT')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pulihkan akses dengan menghapus data lokal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus data dan reset'));
      await tester.pumpAndSettle();

      expect(find.text('UNLOCKED_CONTENT'), findsNothing);
      expect(find.textContaining('PIN tidak tersedia'), findsOneWidget);
      expect(
        find.text('Reset gagal. Data lokal tidak diubah; coba lagi.'),
        findsOneWidget,
      );
      expect(await database.countRows(database.accounts), 1);
      expect(await database.readSetting(SettingKeys.pinEnabled), '1');
      expect(cleanupService.cleanupCalls, 0);
    },
  );

  testWidgets('locking hides routes and open dialogs without tearing them down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityRepositoryProvider.overrideWithValue(
            _FakeSecurityRepository(initialPin: '1234'),
          ),
          pinProtectionEnabledProvider.overrideWith((_) async => true),
          biometricProtectionEnabledProvider.overrideWith((_) async => false),
        ],
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          home: const _RouteStateProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FinTrack terkunci'), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(AppLockGate)),
    );
    container.read(appLockControllerProvider.notifier).unlock();
    await tester.pumpAndSettle();

    // Route state is populated before the lock happens.
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    expect(find.text('Nilai: 1'), findsOneWidget);

    await tester.tap(find.text('Buka dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog uji'), findsOneWidget);

    container.read(appLockControllerProvider.notifier).lock();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FinTrack terkunci'), findsOneWidget);
    // The app content is offstage, so its widgets are not discoverable.
    expect(find.text('Dialog uji'), findsNothing);

    await _enterPin(tester, '1234');

    expect(tester.takeException(), isNull);
    // Both the counter state and the still-open dialog survived the lock.
    expect(find.text('Nilai: 1'), findsOneWidget);
    expect(find.text('Dialog uji'), findsOneWidget);
  });
}

class _RouteStateProbe extends StatefulWidget {
  const _RouteStateProbe();

  @override
  State<_RouteStateProbe> createState() => _RouteStateProbeState();
}

class _RouteStateProbeState extends State<_RouteStateProbe> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Nilai: $_value'),
            FilledButton(
              onPressed: () => setState(() => _value += 1),
              child: const Text('Tambah'),
            ),
            FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (BuildContext context) => const AlertDialog(
                  title: Text('Dialog uji'),
                  content: TextField(),
                ),
              ),
              child: const Text('Buka dialog'),
            ),
          ],
        ),
      ),
    );
  }
}
