import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/repositories/accounts_repository.dart';
import '../../../core/database/repositories/categories_repository.dart';
import '../../../core/database/repositories/transactions_repository.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/backup_codec.dart';
import '../../../core/utils/csv_exporter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../shared/providers/backup_providers.dart';
import '../../../shared/providers/database_providers.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<BackupService> _service() => ref.read(backupServiceProvider.future);

  Future<void> _createBackup() async {
    final String? password = await _passwordDialog(
      title: 'Enkripsi backup (opsional)',
      confirm: true,
    );
    // Null means canceled; empty string is explicit choice to skip encryption.
    if (password == null || !mounted) return;
    final BackupService service = await _service();
    final String contents = await service.createBackup(
      password: password.isEmpty ? null : password,
    );
    final DateTime now = DateTime.now();
    final Uint8List bytes = Uint8List.fromList(utf8.encode(contents));
    final Uri? saved = await FilePicker.saveFile(
      fileName: 'fintrack-backup-${_stamp(now)}.json',
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Simpan backup FinTrack',
    );
    if (saved == null || !mounted) return;
    await _saveLastBackup(now);
    _showMessage('Backup berhasil disimpan.');
  }

  Future<String?> _passwordDialog({
    required String title,
    required bool confirm,
    String? helper,
  }) async {
    final TextEditingController first = TextEditingController();
    final TextEditingController second = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    String? error;
    final String? result = await showDialog<String?>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: Text(title),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (helper != null) ...<Widget>[
                      Text(helper),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    TextFormField(
                      controller: first,
                      obscureText: true,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Password backup',
                      ),
                      validator: (String? value) {
                        if (value == null || value.isEmpty) return null;
                        if (value.length < 12 || value.length > 256) {
                          return 'Gunakan 12–256 karakter.';
                        }
                        if (confirm && value != second.text) {
                          return 'Konfirmasi password tidak sama.';
                        }
                        return null;
                      },
                    ),
                    if (confirm) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: second,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Ulangi password',
                        ),
                        validator: (String? value) =>
                            first.text.isNotEmpty && value != first.text
                            ? 'Konfirmasi password tidak sama.'
                            : null,
                      ),
                    ],
                    if (error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                if (confirm)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, ''),
                    child: const Text('Tanpa enkripsi'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    if (first.text.isEmpty) {
                      setDialogState(
                        () => error = confirm
                            ? 'Pilih enkripsi atau backup tanpa enkripsi.'
                            : 'Password wajib diisi.',
                      );
                      return;
                    }
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(dialogContext, first.text);
                    }
                  },
                  child: const Text('Lanjut'),
                ),
              ],
            ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _restoreBackup() async {
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      dialogTitle: 'Pilih backup FinTrack',
    );
    if (file == null) return;
    final int? fileLength = await file.length();
    if (fileLength != null && fileLength > 20 * 1024 * 1024) {
      throw const FormatException('File backup melebihi batas 20 MB.');
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('File backup melebihi batas 20 MB.');
    }
    final String contents = utf8.decode(bytes);
    final BackupService service = await _service();

    String? password;
    if (const BackupCodec().isEncrypted(contents)) {
      password = await _passwordDialog(
        title: 'Backup terenkripsi',
        confirm: false,
        helper: 'Masukkan password backup. Password tidak disimpan.',
      );
      if (password == null) return;
    }
    final BackupDocument document = await service.validateBackup(
      contents,
      password: password,
    );
    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Timpa seluruh data?'),
        content: Text(
          'Backup ${_formatDate(document.createdAt)} · skema ${document.schemaVersion} · '
          '${document.totalRows} baris. Semua data aplikasi saat ini akan diganti.',
        ),
        actions: <Widget>[
          DialogActions(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
            confirmLabel: 'Pulihkan',
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await service.restoreBackup(document, confirmed: true);
    ref.invalidate(appDatabaseProvider);
    if (!mounted) return;
    _showMessage('Data berhasil dipulihkan.');
  }

  Future<void> _exportCsv() async {
    final TransactionsRepository transactions = TransactionsRepository(
      await _database(),
    );
    final List<FinancialTransaction> rows = await transactions.list();
    final List<Account> accounts = await AccountsRepository(await _database())
        .list(includeArchived: true);
    final List<Category> categories = await CategoriesRepository(
      await _database(),
    ).list(includeArchived: true);
    final Map<int, Account> accountsById = <int, Account>{
      for (final Account account in accounts) account.id: account,
    };
    final Map<int, Category> categoriesById = <int, Category>{
      for (final Category category in categories) category.id: category,
    };
    final List<ExportTransaction> exportRows = rows
        .map((FinancialTransaction row) {
          return ExportTransaction(
            transaction: row,
            sourceAccount: accountsById[row.accountId]?.name ?? 'Akun dihapus',
            destinationAccount: row.toAccountId == null
                ? null
                : accountsById[row.toAccountId]?.name ?? 'Akun dihapus',
            category: row.categoryId == null
                ? null
                : categoriesById[row.categoryId]?.name ?? 'Kategori dihapus',
          );
        })
        .toList(growable: false);
    final Uri? saved = await FilePicker.saveFile(
      fileName: 'fintrack-transaksi-${_stamp(DateTime.now())}.csv',
      bytes: Uint8List.fromList(CsvExporter.encode(exportRows)),
      mimeType: 'text/csv',
      dialogTitle: 'Ekspor transaksi CSV',
    );
    if (saved != null && mounted) _showMessage('CSV berhasil diekspor.');
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

  Future<void> _saveLastBackup(DateTime date) async {
    final AppDatabase database = await _database();
    await database.saveSetting(
      SettingKeys.lastBackupAt,
      date.toUtc().toIso8601String(),
    );
  }

  String _stamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _errorMessage(Object error) => error is FormatException
      ? error.message
      : error is ArgumentError
      ? error.message?.toString() ?? 'Data tidak valid.'
      : 'Operasi gagal. Periksa file dan coba lagi.';

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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<BackupService> service = ref.watch(backupServiceProvider);
    final DateTime? lastBackup = ref.watch(lastBackupAtProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.backup_outlined,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Salinan data lokal', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Backup mencakup akun, kategori, transaksi, anggaran, target tabungan, kontribusi, dan preferensi non-keamanan. PIN, biometrik, serta jeda kunci perangkat tetap lokal dan tidak ikut diekspor.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Icon(
                      lastBackup == null
                          ? Icons.info_outline_rounded
                          : Icons.history_rounded,
                      size: 18,
                      color: AppColors.mutedTextOf(theme.brightness),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        lastBackup == null
                            ? 'Belum pernah membuat backup di perangkat ini.'
                            : 'Backup terakhir: '
                                  '${Formatters.shortDateTime(lastBackup)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedTextOf(theme.brightness),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _busy || !service.hasValue
                      ? null
                      : () => _run(_createBackup),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Buat backup'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _busy || !service.hasValue
                      ? null
                      : () => _run(_restoreBackup),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Pulihkan dari file'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.table_view_outlined,
                  color: theme.colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Ekspor transaksi', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'CSV UTF-8 untuk spreadsheet. Nilai Rupiah tetap bilangan bulat.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_exportCsv),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Ekspor CSV'),
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
