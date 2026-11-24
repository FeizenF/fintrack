import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../shared/providers/app_lock_provider.dart';
import '../../../shared/providers/database_providers.dart';
import '../../../shared/providers/security_providers.dart';

/// PIN, biometric unlock and auto-lock preferences.
///
/// Secrets never leave the device: the PIN is stored as a salted PBKDF2 hash in
/// platform secure storage, while only non-secret toggles live in the database.
class SecurityPage extends ConsumerStatefulWidget {
  const SecurityPage({super.key});

  @override
  ConsumerState<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends ConsumerState<SecurityPage> {
  bool _loading = true;
  bool _loadError = false;
  bool _busy = false;
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  int _autoLockSeconds = AppConstants.autoLockDefaultSeconds;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final AppDatabase database = await ref.read(appDatabaseProvider.future);
      final bool hasPinRecord = await ref
          .read(securityRepositoryProvider)
          .hasPinRecord;
      final bool pinConfigured =
          await database.readSetting(SettingKeys.pinEnabled) == '1';
      if (pinConfigured && !hasPinRecord) {
        // Keep the lock fail-closed until user confirms/reset PIN state. Settings
        // page must never auto-clear an enabled preference on secure-storage
        // failure, since that would make a transient read error a lock bypass.
        _pinEnabled = true;
        _biometricEnabled = false;
      }
      final bool pinEnabled = hasPinRecord || pinConfigured;
      final bool biometricConfigured =
          await database.readSetting(SettingKeys.biometricEnabled) == '1';
      final int? configuredDelay = int.tryParse(
        await database.readSetting(SettingKeys.autoLockSeconds) ?? '',
      );
      final bool biometricAvailable = await _supportsBiometrics();
      if (!mounted) return;
      setState(() {
        _pinEnabled = pinEnabled;
        _biometricEnabled = biometricConfigured && pinEnabled;
        _biometricAvailable = biometricAvailable;
        _autoLockSeconds =
            AppConstants.autoLockDelaysSeconds.contains(configuredDelay)
            ? configuredDelay!
            : AppConstants.autoLockDefaultSeconds;
        _loadError = false;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _pinEnabled = true;
        _biometricEnabled = false;
        _loading = false;
      });
    }
  }

  Future<bool> _supportsBiometrics() => biometricsAvailable(ref);

  Future<void> _setPinEnabled(bool enabled) async {
    if (_busy) return;
    if (enabled) {
      final String? pin = await _askPin(
        title: 'Buat PIN aplikasi',
        confirm: true,
      );
      if (!mounted || pin == null) return;
      final bool saved = await _guard(() async {
        await ref.read(securityRepositoryProvider).setPin(pin);
        try {
          final AppDatabase database = await _database();
          await database.saveSetting(SettingKeys.pinEnabled, '1');
        } on Object {
          await ref.read(securityRepositoryProvider).removePin();
          rethrow;
        }
        ref.read(appLockControllerProvider.notifier).unlock();
        _refreshProviders();
      });
      if (saved) {
        _showMessage('PIN aktif. Aplikasi akan meminta PIN saat dibuka.');
      }
    } else {
      final String? pin = await _askPin(title: 'Masukkan PIN saat ini');
      if (!mounted || pin == null) return;
      final bool saved = await _guard(() async {
        final bool valid = await ref
            .read(securityRepositoryProvider)
            .verifyPin(pin);
        if (!valid) throw const FormatException('PIN salah.');
        final AppDatabase database = await _database();
        await database.saveSetting(SettingKeys.pinEnabled, '0');
        await database.saveSetting(SettingKeys.biometricEnabled, '0');
        await ref.read(securityRepositoryProvider).removePin();
        ref.read(appLockControllerProvider.notifier).unlock();
        _refreshProviders();
      });
      if (saved) _showMessage('PIN dinonaktifkan.');
    }
    await _load();
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    if (_busy) return;
    if (enabled && !_biometricAvailable) {
      _showMessage('Perangkat tidak mendukung biometrik.', error: true);
      return;
    }
    await _guard(() async {
      final AppDatabase database = await _database();
      await database.saveSetting(
        SettingKeys.biometricEnabled,
        enabled ? '1' : '0',
      );
      _refreshProviders();
    });
    await _load();
  }

  Future<void> _setAutoLock(int seconds) async {
    await _guard(() async {
      final AppDatabase database = await _database();
      await database.saveSetting(
        SettingKeys.autoLockSeconds,
        seconds.toString(),
      );
      _refreshProviders();
    });
    await _load();
  }

  void _refreshProviders() {
    ref.invalidate(pinRecordExistsProvider);
    ref.invalidate(pinRecordUsableProvider);
    ref.invalidate(pinProtectionEnabledProvider);
    ref.invalidate(biometricProtectionEnabledProvider);
    ref.invalidate(autoLockSecondsProvider);
  }

  Future<AppDatabase> _database() async {
    final AsyncValue<AppDatabase> state = ref.read(appDatabaseProvider);
    return state.when(
      data: (AppDatabase database) => database,
      loading: () => throw StateError('Database belum siap.'),
      error: (Object error, StackTrace stack) =>
          Error.throwWithStackTrace(error, stack),
    );
  }

  Future<bool> _guard(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          error is FormatException
              ? error.message
              : 'Perubahan keamanan gagal disimpan.',
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPin({required String title, bool confirm = false}) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _PinDialog(title: title, confirm: confirm),
    );
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  String _delayLabel(int seconds) {
    if (seconds < 60) return 'Setelah $seconds detik';
    if (seconds < 3600) return 'Setelah ${seconds ~/ 60} menit';
    return 'Setelah ${seconds ~/ 3600} jam';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Keamanan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Pengaturan keamanan gagal dibaca. Status proteksi dipertahankan.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      },
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Kunci aplikasi', style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'PIN disimpan sebagai hash di penyimpanan aman perangkat '
                        'dan tidak ikut dalam file backup.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _pinEnabled,
                        onChanged: _busy ? null : _setPinEnabled,
                        title: const Text('PIN aplikasi'),
                        subtitle: Text(_pinEnabled ? 'Aktif' : 'Tidak aktif'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _biometricEnabled,
                        onChanged: _pinEnabled && _biometricAvailable && !_busy
                            ? _setBiometricEnabled
                            : null,
                        title: const Text('Buka dengan biometrik'),
                        subtitle: Text(
                          !_pinEnabled
                              ? 'Aktifkan PIN terlebih dahulu'
                              : _biometricAvailable
                              ? 'Sidik jari atau wajah terdaftar'
                              : 'Perangkat tidak mendukung biometrik',
                        ),
                      ),
                      if (_pinEnabled) ...<Widget>[
                        const Divider(height: AppSpacing.xl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.help_outline_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Lupa PIN? Di layar kunci pilih "Lupa PIN?", '
                                'lalu verifikasi kunci perangkat untuk membuat '
                                'PIN baru tanpa menghapus data.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Kunci otomatis', style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _pinEnabled
                            ? 'Aplikasi meminta PIN/biometrik setelah kembali '
                                  'dari latar belakang.'
                            : 'Aktifkan PIN untuk memakai kunci otomatis.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<int>(
                        initialValue: _autoLockSeconds,
                        // The dropdown shares a row with the field padding; without
                        // this the longest delay label overflowed the card.
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Jeda sebelum terkunci',
                        ),
                        items: AppConstants.autoLockDelaysSeconds
                            .map(
                              (int seconds) => DropdownMenuItem<int>(
                                value: seconds,
                                child: Text(_delayLabel(seconds)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: !_pinEnabled || _busy
                            ? null
                            : (int? value) {
                                if (value != null) _setAutoLock(value);
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Database SQLite di perangkat ini tidak dienkripsi. '
                          'Gunakan backup berpassword bila file backup disimpan '
                          'di tempat yang kurang aman.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
    );
  }
}

/// Self-contained PIN entry dialog.
///
/// The controllers live in this widget so they are only disposed once the
/// route is really gone. Disposing them right after `showDialog` returned used
/// to crash while the dialog was still animating out.
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.confirm});

  final String title;
  final bool confirm;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final String pin = _first.text;
    if (!PinHasher.isValidPin(pin)) {
      setState(
        () => _error =
            'PIN harus ${PinHasher.minPinLength}–'
            '${PinHasher.maxPinLength} digit angka.',
      );
      return;
    }
    if (widget.confirm && pin != _second.text) {
      setState(() => _error = 'Konfirmasi PIN tidak sama.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _first,
            autofocus: true,
            obscureText: true,
            maxLength: PinHasher.maxPinLength,
            keyboardType: TextInputType.number,
            onSubmitted: (_) {
              if (!widget.confirm) _submit();
            },
            decoration: InputDecoration(
              labelText: 'PIN',
              counterText: '',
              errorText: _error,
            ),
          ),
          if (widget.confirm) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _second,
              obscureText: true,
              maxLength: PinHasher.maxPinLength,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Ulangi PIN',
                counterText: '',
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        DialogActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: _submit,
          confirmLabel: 'Simpan',
        ),
      ],
    );
  }
}
