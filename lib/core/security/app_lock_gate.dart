import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../services/attachment_cleanup_service.dart';
import '../theme/app_colors.dart';
import '../widgets/dialog_actions.dart';
import '../../shared/providers/app_lock_provider.dart';
import '../../shared/providers/attachment_cleanup_providers.dart';
import '../../shared/providers/database_providers.dart';
import '../../shared/providers/security_providers.dart';
import 'pin_hasher.dart';

/// Which screen the lock layer shows once a usable PIN record exists.
enum _LockStage {
  /// Normal PIN entry.
  unlock,

  /// "Lupa PIN?" recovery options.
  recovery,

  /// Choosing a replacement PIN after the device owner was verified.
  newPin,
}

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
  _LockStage _stage = _LockStage.unlock;

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
    // An unreadable preference fails closed (lock now) instead of silently
    // extending the unlocked window; only a valid stored value can be relaxed.
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
      if (_stage != _LockStage.unlock) {
        setState(() => _stage = _LockStage.unlock);
      }
      ref.read(appLockControllerProvider.notifier).unlock();
    } else {
      throw const FormatException('PIN salah.');
    }
  }

  void _openRecovery() {
    if (_stage == _LockStage.recovery) return;
    setState(() => _stage = _LockStage.recovery);
  }

  void _backToUnlock() {
    if (_stage == _LockStage.unlock) return;
    setState(() => _stage = _LockStage.unlock);
  }

  /// Verifies the device owner with the platform screen lock (device PIN,
  /// pattern, password or enrolled biometrics).
  ///
  /// This is the "lupa PIN" escape hatch: the app PIN cannot be recovered
  /// because only its hash is stored, but whoever can unlock the phone can pick
  /// a new one without losing the ledger.
  Future<bool> _verifyDeviceOwner() async {
    final bool ok = await authenticateWithDeviceCredentials(ref);
    if (!mounted || !ok) return ok;
    setState(() => _stage = _LockStage.newPin);
    return true;
  }

  Future<void> _saveNewPin(String pin) async {
    final repository = ref.read(securityRepositoryProvider);
    await repository.setPin(pin);
    try {
      final AppDatabase database = await ref.read(appDatabaseProvider.future);
      await database.saveSetting(SettingKeys.pinEnabled, '1');
    } on Object {
      // A stored PIN record alone keeps protection enabled
      // (see pinProtectionEnabledProvider), so a failed preference write is not
      // an unlock bypass.
    }
    if (!mounted) return;
    ref.invalidate(pinRecordExistsProvider);
    ref.invalidate(pinRecordUsableProvider);
    ref.invalidate(pinProtectionEnabledProvider);
    ref.invalidate(biometricProtectionEnabledProvider);
    setState(() => _stage = _LockStage.unlock);
    ref.read(appLockControllerProvider.notifier).unlock();
  }

  Future<void> _resetMissingPin() async {
    if (_resetting) return;
    _resetting = true;
    try {
      final bool usableRecord = await ref
          .read(securityRepositoryProvider)
          .hasUsablePinRecord;
      if (usableRecord) {
        ref.invalidate(pinRecordUsableProvider);
        return;
      }
      await _wipeLocalData();
    } on Object {
      // _wipeLocalData reports its own failures.
    } finally {
      _resetting = false;
    }
  }

  Future<void> _forgotPinReset() async {
    if (_resetting) return;
    _resetting = true;
    try {
      await _wipeLocalData();
    } finally {
      _resetting = false;
    }
  }

  /// Destroys local data and unlocks.
  ///
  /// Confirmation happens inside the lock layer instead of a dialog: this widget
  /// lives above the [Navigator] (it wraps the whole routed app), so there is no
  /// overlay to host a dialog and `showDialog` would fail on a real device.
  Future<void> _wipeLocalData() async {
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
    setState(() => _stage = _LockStage.unlock);
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
        AsyncData<bool>(value: true) => _buildUnlockLayer(biometricEnabled),
        _ => const _LockSplash(),
      },
      AsyncError<bool>() => _LockUnavailable(
        onRetry: () => ref.invalidate(pinProtectionEnabledProvider),
      ),
      _ => const _LockSplash(),
    };
  }

  Widget _buildUnlockLayer(AsyncValue<bool> biometricEnabled) {
    return switch (_stage) {
      _LockStage.recovery => _ForgotPinScreen(
        showBiometric: biometricEnabled.value == true,
        onBiometric: _authenticate,
        onVerifyDevice: _verifyDeviceOwner,
        onResetData: _forgotPinReset,
        onBack: _backToUnlock,
      ),
      _LockStage.newPin => _NewPinScreen(
        onSave: _saveNewPin,
        onCancel: _backToUnlock,
      ),
      _LockStage.unlock => switch (biometricEnabled) {
        AsyncData<bool>(value: true) => _LockScreen(
          onSubmit: _verifyPin,
          onBiometric: _authenticate,
          onForgotPin: _openRecovery,
          showBiometric: true,
        ),
        AsyncData<bool>(value: false) => _LockScreen(
          onSubmit: _verifyPin,
          onBiometric: _authenticate,
          onForgotPin: _openRecovery,
          showBiometric: false,
        ),
        AsyncError<bool>() => _LockUnavailable(
          onRetry: () => ref.invalidate(biometricProtectionEnabledProvider),
        ),
        _ => const _LockSplash(),
      },
    };
  }
}

/// Recovery shown when the stored PIN record is unreadable or missing.
///
/// The confirmation lives on this screen rather than in a dialog: the lock
/// layer wraps the [Navigator], so dialogs have nowhere to render.
class _PinRecoveryScreen extends StatefulWidget {
  const _PinRecoveryScreen({required this.onReset});

  final Future<void> Function() onReset;

  @override
  State<_PinRecoveryScreen> createState() => _PinRecoveryScreenState();
}

class _PinRecoveryScreenState extends State<_PinRecoveryScreen> {
  bool _confirming = false;
  bool _busy = false;

  Future<void> _confirmReset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onReset();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return _LockScaffold(
      builder: (BuildContext context, bool compact) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LockBadge(icon: Icons.key_off_rounded, compact: compact),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'PIN tidak tersedia',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Data aplikasi tetap terkunci karena kunci PIN aktif tetapi '
            'catatan PIN tidak bisa dibaca.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_confirming) ...<Widget>[
            FilledButton.icon(
              onPressed: _busy ? null : () => setState(() => _confirming = true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Pulihkan akses dengan menghapus data lokal'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Reset menghapus seluruh data lokal. Pulihkan dari backup '
              'setelahnya.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else ...<Widget>[
            _ResetConfirmPanel(
              busy: _busy,
              onCancel: _busy ? null : () => setState(() => _confirming = false),
              onConfirm: _confirmReset,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared confirmation body for destructive lock resets.
class _ResetConfirmPanel extends StatelessWidget {
  const _ResetConfirmPanel({
    required this.busy,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool busy;
  final VoidCallback? onCancel;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.28 : 0.6,
        ),
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Atur ulang kunci aplikasi?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PIN lama tidak tersedia. Tindakan ini menghapus data aplikasi '
            'lokal secara permanen. Pulihkan data dari backup setelahnya.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DialogActions(
            onCancel: onCancel,
            onConfirm: busy ? null : onConfirm,
            confirmLabel: busy ? 'Menghapus...' : 'Hapus data dan reset',
            destructive: true,
          ),
        ],
      ),
    );
  }
}

/// Centred, scrollable canvas shared by every lock-layer screen so the PIN pad,
/// recovery options and new-PIN form line up identically.
class _LockScaffold extends StatelessWidget {
  const _LockScaffold({required this.builder});

  final Widget Function(BuildContext context, bool compact) builder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxHeight < 640;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: compact ? AppSpacing.lg : AppSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: builder(context, compact),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Circular brand mark used at the top of every lock-layer screen.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.icon, required this.compact});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double size = compact ? 56 : 68;

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primaryContainer,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        ),
        child: Icon(
          icon,
          size: compact ? 26 : 30,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
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
    required this.onForgotPin,
    required this.showBiometric,
  });

  final Future<void> Function(String pin) onSubmit;
  final Future<void> Function() onBiometric;
  final VoidCallback onForgotPin;
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
    final ColorScheme scheme = theme.colorScheme;

    return _LockScaffold(
      builder: (BuildContext context, bool compact) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LockBadge(icon: Icons.lock_rounded, compact: compact),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
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
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
          _PinDots(length: _pin.length, busy: _busy),
          const SizedBox(height: AppSpacing.md),
          _LockError(message: _error),
          const SizedBox(height: AppSpacing.sm),
          _Keypad(
            compact: compact,
            enabled: !_busy,
            showBiometric: widget.showBiometric,
            onDigit: _append,
            onBackspace: _backspace,
            onBiometric: widget.onBiometric,
          ),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: const Text('Buka'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _busy ? null : widget.onForgotPin,
            child: const Text('Lupa PIN?'),
          ),
        ],
      ),
    );
  }
}

/// Rounded message slot under the PIN dots.
///
/// The height is reserved even when there is no error so the keypad does not
/// jump after a wrong PIN.
class _LockError extends StatelessWidget {
  const _LockError({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? text = message;

    return SizedBox(
      height: 38,
      child: text == null
          ? null
          : Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
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
            AnimatedContainer(
              key: ValueKey<String>('pin-dot-$i'),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 6),
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
              height: 14,
              width: 14,
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
    this.compact = false,
  });

  final bool enabled;
  final bool showBiometric;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Future<void> Function() onBiometric;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<List<Widget>> rows = <List<Widget>>[
      <Widget>[
        _KeypadKey.digit('1', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('2', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('3', compact: compact, onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        _KeypadKey.digit('4', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('5', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('6', compact: compact, onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        _KeypadKey.digit('7', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('8', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey.digit('9', compact: compact, onTap: enabled ? onDigit : null),
      ],
      <Widget>[
        if (showBiometric)
          _KeypadKey(
            compact: compact,
            semanticLabel: 'Gunakan biometrik',
            onTap: enabled ? onBiometric : null,
            child: const Icon(Icons.fingerprint_rounded, size: 24),
          )
        else
          const SizedBox.shrink(),
        _KeypadKey.digit('0', compact: compact, onTap: enabled ? onDigit : null),
        _KeypadKey(
          compact: compact,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs / 2,
                      vertical: AppSpacing.xs / 2,
                    ),
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
  _KeypadKey.digit(
    String digit, {
    required ValueChanged<String>? onTap,
    this.compact = false,
  }) : semanticLabel = null,
       onTap = onTap == null ? null : (() => onTap(digit)),
       child = Text(
         digit,
         style: TextStyle(fontSize: compact ? 20 : 22),
       );

  const _KeypadKey({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.compact = false,
  });

  final String? semanticLabel;
  final VoidCallback? onTap;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final sized = SizedBox(
      height: compact ? 48 : 56,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
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

/// Recovery options shown from the lock screen when the user forgot the PIN.
///
/// The app never stores the PIN itself, so the only ways back in are the device
/// screen lock (pick a new PIN, keep the data) or a full local wipe.
class _ForgotPinScreen extends StatefulWidget {
  const _ForgotPinScreen({
    required this.showBiometric,
    required this.onBiometric,
    required this.onVerifyDevice,
    required this.onResetData,
    required this.onBack,
  });

  final bool showBiometric;
  final Future<void> Function() onBiometric;
  final Future<bool> Function() onVerifyDevice;
  final Future<void> Function() onResetData;
  final VoidCallback onBack;

  @override
  State<_ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<_ForgotPinScreen> {
  bool _busy = false;
  bool _confirmingReset = false;
  String? _error;

  Future<void> _verifyDevice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await widget.onVerifyDevice();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Verifikasi perangkat gagal atau dibatalkan.';
    });
  }

  Future<void> _biometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onBiometric();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = 'Biometrik tidak cocok atau dibatalkan.';
    });
  }

  Future<void> _resetData() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onResetData();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return _LockScaffold(
      builder: (BuildContext context, bool compact) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_confirmingReset) ...<Widget>[
            _LockBadge(icon: Icons.warning_amber_rounded, compact: compact),
            const SizedBox(height: AppSpacing.lg),
            _ResetConfirmPanel(
              busy: _busy,
              onCancel: _busy
                  ? null
                  : () => setState(() => _confirmingReset = false),
              onConfirm: _resetData,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _confirmingReset = false),
              child: const Text('Batal'),
            ),
          ] else ...<Widget>[
            _LockBadge(icon: Icons.lock_reset_rounded, compact: compact),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              'Lupa PIN?',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'PIN hanya tersimpan sebagai hash di perangkat ini, jadi tidak '
              'bisa ditampilkan. Verifikasi dengan kunci layar perangkat untuk '
              'membuat PIN baru tanpa menghapus data.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _LockError(message: _error),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _verifyDevice,
              icon: const Icon(Icons.phonelink_lock_rounded),
              label: const Text('Verifikasi dengan kunci perangkat'),
            ),
            if (widget.showBiometric) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : _biometric,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Coba buka dengan biometrik'),
              ),
            ],
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _confirmingReset = true;
                      _error = null;
                    }),
              child: Text(
                'Hapus semua data lokal',
                style: TextStyle(color: scheme.error),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: const Text('Kembali'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-step new PIN entry used after a successful device-owner check.
///
/// It reuses the keypad for the same reason as the lock screen: the layer sits
/// above the [Navigator], so a [TextField] would have no [Overlay] for its
/// selection handles.
class _NewPinScreen extends StatefulWidget {
  const _NewPinScreen({required this.onSave, required this.onCancel});

  final Future<void> Function(String pin) onSave;
  final VoidCallback onCancel;

  @override
  State<_NewPinScreen> createState() => _NewPinScreenState();
}

class _NewPinScreenState extends State<_NewPinScreen> {
  String _pin = '';
  String? _first;
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
            'PIN harus ${PinHasher.minPinLength}–'
            '${PinHasher.maxPinLength} digit angka.',
      );
      return;
    }
    final String? first = _first;
    if (first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
        _error = null;
      });
      return;
    }
    if (first != _pin) {
      setState(() {
        _first = null;
        _pin = '';
        _error = 'PIN tidak sama. Ulangi dari awal.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_pin);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _first = null;
          _pin = '';
          _error = 'PIN gagal disimpan. Coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool repeat = _first != null;

    return _LockScaffold(
      builder: (BuildContext context, bool compact) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LockBadge(icon: Icons.password_rounded, compact: compact),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          Text(
            'Buat PIN baru',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            repeat
                ? 'Ulangi PIN baru untuk memastikan.'
                : 'Masukkan ${PinHasher.minPinLength}–'
                      '${PinHasher.maxPinLength} digit angka.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          _PinDots(length: _pin.length, busy: _busy),
          const SizedBox(height: AppSpacing.md),
          _LockError(message: _error),
          const SizedBox(height: AppSpacing.sm),
          _Keypad(
            compact: compact,
            enabled: !_busy,
            showBiometric: false,
            onDigit: _append,
            onBackspace: _backspace,
            onBiometric: () async {},
          ),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(repeat ? 'Simpan' : 'Lanjut'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _busy ? null : widget.onCancel,
            child: const Text('Batal'),
          ),
        ],
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
