import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../services/attachment_cleanup_service.dart';
import '../theme/app_colors.dart';
import '../../shared/providers/app_lock_provider.dart';
import '../../shared/providers/attachment_cleanup_providers.dart';
import '../../shared/providers/database_providers.dart';
import '../../shared/providers/security_providers.dart';
import 'pin_hasher.dart';

/// Blocks the app content behind the optional PIN/biometric lock.
///
/// When no PIN is provisioned the child is shown immediately, so the app stays
/// usable offline with zero setup. Auto-lock re-locks the session after the
/// configured delay following a background/foreground transition.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _biometricRunning = false;
  bool _unlockScheduled = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockIfNoPin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        _maybeAutoLock();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _unlockIfNoPin() async {
    if (!mounted || _unlockScheduled) return;
    _unlockScheduled = true;
    try {
      final bool enabled = await ref.read(pinProtectionEnabledProvider.future);
      if (!mounted) return;
      if (!enabled) {
        ref.read(appLockControllerProvider.notifier).unlock();
      } else if (await _biometricEnabled() && mounted) {
        await _authenticate();
      }
    } on Object {
      // Keep session locked when security state cannot be read. User can retry
      // from the fail-closed screen after storage or database recovers.
    }
  }

  Future<bool> _biometricEnabled() async {
    try {
      return await ref.read(biometricProtectionEnabledProvider.future);
    } on Object {
      return false;
    }
  }

  Future<void> _maybeAutoLock() async {
    final DateTime? backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || !mounted) return;
    final bool unlocked = ref.read(appLockControllerProvider);
    if (!unlocked) return;
    int delaySeconds = 0;
    try {
      delaySeconds = await ref.read(autoLockSecondsProvider.future);
    } on Object {
      delaySeconds = 0;
    }
    if (!mounted) return;
    final Duration elapsed = DateTime.now().difference(backgroundedAt);
    if (elapsed.inSeconds >= delaySeconds) {
      ref.read(appLockControllerProvider.notifier).lock();
    }
  }

  Future<void> _authenticate() async {
    if (_biometricRunning || !mounted) return;
    setState(() => _biometricRunning = true);
    try {
      final bool ok = await authenticateWithBiometrics(ref);
      if (ok && mounted) ref.read(appLockControllerProvider.notifier).unlock();
    } on Object {
      // Cancelled or unavailable biometrics simply leave the PIN pad visible.
    } finally {
      if (mounted) setState(() => _biometricRunning = false);
    }
  }

  Future<void> _verifyPin(String pin) async {
    final bool ok = await ref.read(securityRepositoryProvider).verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      ref.read(appLockControllerProvider.notifier).unlock();
    } else {
      throw const FormatException('PIN salah.');
    }
  }

  Future<void> _resetMissingPin() async {
    if (_resetting) return;
    _resetting = true;
    try {
      await _performLocalReset();
    } finally {
      _resetting = false;
    }
  }

  Future<void> _performLocalReset() async {
    try {
      final bool usableRecord = await ref
          .read(securityRepositoryProvider)
          .hasUsablePinRecord;
      if (usableRecord) {
        ref.invalidate(pinRecordUsableProvider);
        return;
      }
    } on Object {
      return;
    }
    if (!mounted) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Atur ulang kunci aplikasi?'),
            content: const Text(
              'PIN lama tidak tersedia. Tindakan ini menghapus data aplikasi '
              'lokal secara permanen. Pulihkan data dari backup setelahnya.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Hapus data dan reset'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    String? cleanupWarning;
    try {
      final AppDatabase database = await ref.read(appDatabaseProvider.future);
      await ref.read(securityRepositoryProvider).removePin();
      await database.transaction(() async {
        await database.delete(database.savingsContributions).go();
        await database.delete(database.budgets).go();
        await database.delete(database.transactions).go();
        await database.delete(database.savingsGoals).go();
        await database.delete(database.categories).go();
        await database.delete(database.accounts).go();
        await database.delete(database.appSettings).go();
        await database.ensureSeeded();
      });
      try {
        final AttachmentCleanupResult result = await ref
            .read(attachmentCleanupServiceProvider)
            .deleteOwnedAttachments();
        if (result.hasFailures) {
          cleanupWarning =
              'Reset selesai. ${result.failedPaths.length} lampiran gagal '
              'dihapus; hapus file tersebut manual dari penyimpanan aplikasi.';
        }
      } on Object {
        cleanupWarning =
            'Reset selesai, tetapi penghapusan lampiran gagal. Hapus file '
            'lampiran secara manual dari penyimpanan aplikasi jika perlu.';
      }
    } on Object {
      if (mounted) {
        ref.invalidate(pinRecordExistsProvider);
        ref.invalidate(pinRecordUsableProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reset gagal. Data lokal tidak diubah; coba lagi.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    ref.read(appLockControllerProvider.notifier).reset();
    if (cleanupWarning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cleanupWarning)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> pinEnabled = ref.watch(pinProtectionEnabledProvider);
    final AsyncValue<bool> pinRecordExists = ref.watch(pinRecordUsableProvider);
    final AsyncValue<bool> biometricEnabled = ref.watch(
      biometricProtectionEnabledProvider,
    );
    final bool unlocked = ref.watch(appLockControllerProvider);

    if (unlocked && pinEnabled is AsyncData<bool> && !pinEnabled.value) {
      return widget.child;
    }
    if (unlocked &&
        pinEnabled is AsyncData<bool> &&
        pinEnabled.value &&
        pinRecordExists is AsyncData<bool> &&
        pinRecordExists.value) {
      return widget.child;
    }
    return switch (pinEnabled) {
      AsyncData<bool>(value: false) => widget.child,
      AsyncData<bool>(value: true) => switch (pinRecordExists) {
        AsyncData<bool>(value: false) => _PinRecoveryScreen(
          onReset: _resetMissingPin,
        ),
        AsyncError<bool>() => _LockUnavailable(
          onRetry: () => ref.invalidate(pinRecordUsableProvider),
        ),
        AsyncData<bool>(value: true) => switch (biometricEnabled) {
          AsyncData<bool>(value: true) => _LockScreen(
            onSubmit: _verifyPin,
            onBiometric: _authenticate,
            biometricBusy: _biometricRunning,
            showBiometric: true,
          ),
          AsyncData<bool>(value: false) => _LockScreen(
            onSubmit: _verifyPin,
            onBiometric: _authenticate,
            biometricBusy: _biometricRunning,
            showBiometric: false,
          ),
          AsyncError<bool>() => _LockUnavailable(
            onRetry: () => ref.invalidate(biometricProtectionEnabledProvider),
          ),
          _ => const _LockSplash(),
        },
        _ => const _LockSplash(),
      },
      AsyncError<bool>() => _LockUnavailable(
        onRetry: () => ref.invalidate(pinProtectionEnabledProvider),
      ),
      _ => const _LockSplash(),
    };
  }
}

class _PinRecoveryScreen extends StatelessWidget {
  const _PinRecoveryScreen({required this.onReset});

  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.key_off_rounded, size: 40),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'PIN tidak tersedia. Data aplikasi tetap terkunci.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Reset menghapus seluruh data lokal. Pulihkan dari backup setelahnya.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onReset,
              child: const Text('Pulihkan akses dengan menghapus data lokal'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({
    required this.onSubmit,
    required this.onBiometric,
    required this.biometricBusy,
    required this.showBiometric,
  });

  final Future<void> Function(String pin) onSubmit;
  final Future<void> Function() onBiometric;
  final bool biometricBusy;
  final bool showBiometric;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String pin = _controller.text;
    if (_busy) return;
    if (!PinHasher.isValidPin(pin)) {
      setState(() => _error = 'Masukkan PIN 4–8 digit.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(pin);
      if (mounted) _controller.clear();
    } on Object {
      if (mounted) setState(() => _error = 'PIN salah.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'FinTrack terkunci',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Masukkan PIN untuk melanjutkan.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: PinHasher.maxPinLength,
                    enabled: !_busy,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: _error,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buka'),
                  ),
                  if (widget.showBiometric) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: widget.biometricBusy
                          ? null
                          : widget.onBiometric,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Gunakan biometrik'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockUnavailable extends StatelessWidget {
  const _LockUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded, size: 40),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Pengaturan keamanan tidak dapat dibaca. Aplikasi tetap terkunci.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    ),
  );
}

class _LockSplash extends StatelessWidget {
  const _LockSplash();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        height: 28,
        width: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}
