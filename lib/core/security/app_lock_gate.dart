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
      // Drop focus before the lock layer covers the content so the keyboard
      // does not stay open above the PIN screen.
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(appLockControllerProvider.notifier).lock();
    }
  }

  Future<void> _authenticate() async {
    if (_biometricRunning || !mounted) return;
    _biometricRunning = true;
    try {
      final bool ok = await authenticateWithBiometrics(ref);
      if (ok && mounted) ref.read(appLockControllerProvider.notifier).unlock();
    } on Object {
      // Cancelled or unavailable biometrics simply leave the PIN pad visible.
    } finally {
      _biometricRunning = false;
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
    final bool unlocked = ref.watch(appLockControllerProvider);
    final AsyncValue<bool> pinEnabled = ref.watch(pinProtectionEnabledProvider);
    // No PIN configured means there is nothing to unlock. Treat that as open
    // immediately instead of flashing a splash while the setting resolves.
    final bool noPinConfigured =
        pinEnabled is AsyncData<bool> && !pinEnabled.value;
    final bool lockVisible = !unlocked && !noPinConfigured;

    // The app content is only hidden, never unmounted: tearing down the router
    // (and any open dialog or half-filled form) on every lock/unlock was what
    // produced the `_dependents.isEmpty` framework assertion.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        TickerMode(
          enabled: !lockVisible,
          child: Offstage(offstage: lockVisible, child: widget.child),
        ),
        if (lockVisible) Positioned.fill(child: _buildLockLayer()),
      ],
    );
  }

  Widget _buildLockLayer() {
    final AsyncValue<bool> pinEnabled = ref.watch(pinProtectionEnabledProvider);
    final AsyncValue<bool> pinRecordExists = ref.watch(pinRecordUsableProvider);
    final AsyncValue<bool> biometricEnabled = ref.watch(
      biometricProtectionEnabledProvider,
    );
    return switch (pinEnabled) {
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
            showBiometric: true,
          ),
          AsyncData<bool>(value: false) => _LockScreen(
            onSubmit: _verifyPin,
            onBiometric: _authenticate,
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

/// PIN entry for the lock screen.
///
/// This layer is rendered above the [Navigator] (the whole app is hidden behind
/// it), which means there is no [Overlay] ancestor. A [TextField] would need
/// one for its selection handles and would crash with "No Overlay widget
/// found", so the lock screen uses its own numeric keypad instead. It also
/// avoids pulling up the system keyboard over the lock screen.
class _LockScreen extends StatefulWidget {
  const _LockScreen({
    required this.onSubmit,
    required this.onBiometric,
    required this.showBiometric,
  });

  final Future<void> Function(String pin) onSubmit;
  final Future<void> Function() onBiometric;
  final bool showBiometric;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  bool get _canSubmit => !_busy && PinHasher.isValidPin(_pin);

  void _append(String digit) {
    if (_busy || _pin.length >= PinHasher.maxPinLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!PinHasher.isValidPin(_pin)) {
      setState(
        () => _error =
            'Masukkan PIN ${PinHasher.minPinLength}–'
            '${PinHasher.maxPinLength} digit.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_pin);
      if (mounted) setState(() => _pin = '');
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'PIN salah.';
          _pin = '';
        });
      }
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
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'FinTrack terkunci',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Masukkan PIN untuk melanjutkan.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PinDots(length: _pin.length, busy: _busy),
                  SizedBox(
                    height: 20,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _Keypad(
                    enabled: !_busy,
                    showBiometric: widget.showBiometric,
                    onDigit: _append,
                    onBackspace: _backspace,
                    onBiometric: widget.onBiometric,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('Buka'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled dots for the digits entered so far, with empty slots up to the
/// minimum PIN length so the expected size is visible from the start.
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.busy});

  final int length;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int slots = length > PinHasher.minPinLength
        ? length
        : PinHasher.minPinLength;
    return Semantics(
      label: 'PIN terisi $length digit',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < slots; i++)
            Container(
              key: ValueKey<String>('pin-dot-$i'),
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < length
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: i < length
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
            ),
          if (busy) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.showBiometric,
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
  });

  final bool enabled;
  final bool showBiometric;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Future<void> Function() onBiometric;

  @override
  Widget build(BuildContext context) {
    final List<List<Widget>> rows = <List<Widget>>[
      <Widget>[
        _KeypadKey.digit('1', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('2', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('3', onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        _KeypadKey.digit('4', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('5', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('6', onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        _KeypadKey.digit('7', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('8', onTap: enabled ? onDigit : null),
        _KeypadKey.digit('9', onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        if (showBiometric)
          _KeypadKey(
            semanticLabel: 'Gunakan biometrik',
            onTap: enabled ? onBiometric : null,
            child: const Icon(Icons.fingerprint_rounded, size: 24),
          )
        else
          const SizedBox.shrink(),
        _KeypadKey.digit('0', onTap: enabled ? onDigit : null),
        _KeypadKey(
          semanticLabel: 'Hapus digit',
          onTap: enabled ? onBackspace : null,
          child: const Icon(Icons.backspace_outlined, size: 22),
        ),
      ],
    ];

    return Column(
      children: <Widget>[
        for (final List<Widget> row in rows)
          Row(
            children: <Widget>[
              for (final Widget key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs / 2),
                    child: key,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _KeypadKey extends StatelessWidget {
  _KeypadKey.digit(String digit, {required ValueChanged<String>? onTap})
    : semanticLabel = null,
      onTap = onTap == null ? null : (() => onTap(digit)),
      child = Text(digit, style: const TextStyle(fontSize: 22));

  const _KeypadKey({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String? semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final sized = SizedBox(
      height: 52,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      ),
    );
    if (semanticLabel == null) return sized;
    return Semantics(label: semanticLabel, button: true, child: sized);
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
