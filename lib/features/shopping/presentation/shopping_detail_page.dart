import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/shopping_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/section_title.dart';
import '../../../shared/providers/database_providers.dart';

/// Detail page for one shopping note: check items off, fill prices, then book
/// the total as a single expense.
class ShoppingDetailPage extends ConsumerWidget {
  const ShoppingDetailPage({super.key, required this.listId});

  final int listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ShoppingListDetail?> value = ref.watch(
      shoppingListProvider(listId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catatan Belanja'),
        actions: <Widget>[
          value.value == null
              ? const SizedBox.shrink()
              : PopupMenuButton<String>(
                  tooltip: 'Aksi catatan',
                  onSelected: (String action) =>
                      _onAction(context, ref, value.value!, action),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Ubah catatan'),
                    ),
                    if (value.value!.isBooked)
                      const PopupMenuItem<String>(
                        value: 'unbook',
                        child: Text('Batalkan pencatatan'),
                      ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Hapus catatan'),
                    ),
                  ],
                ),
        ],
      ),
      body: value.when(
        loading: () => const LoadingState(message: 'Memuat catatan...'),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Catatan belanja gagal dimuat.',
          onRetry: () => ref.invalidate(shoppingListProvider(listId)),
        ),
        data: (ShoppingListDetail? note) {
          if (note == null) {
            return const ErrorStateView(
              message: 'Catatan belanja tidak ditemukan.',
            );
          }
          return Column(
            children: <Widget>[
              Expanded(
                child: _Body(
                  note: note,
                  onAddItem: note.isBooked
                      ? null
                      : () => _addItem(context, ref),
                ),
              ),
              _BookingBar(note: note),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final _ItemDraft? draft = await showDialog<_ItemDraft>(
      context: context,
      builder: (_) => const _ItemFormDialog(),
    );
    if (draft == null) return;
    try {
      final ShoppingRepository repository = await ref.read(
        shoppingRepositoryProvider.future,
      );
      await repository.addItem(
        listId,
        name: draft.name,
        quantity: draft.quantity,
        unitPrice: draft.unitPrice,
      );
      ref.invalidate(shoppingListProvider(listId));
      ref.invalidate(shoppingListsProvider);
    } on Object catch (error) {
      if (!context.mounted) return;
      _snack(context, error, 'Item gagal ditambahkan.');
    }
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    ShoppingListDetail note,
    String action,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final ShoppingRepository repository = await ref.read(
      shoppingRepositoryProvider.future,
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        final bool? saved = await showDialog<bool>(
          context: context,
          builder: (_) => _EditNoteDialog(note: note.list),
        );
        if (saved == true) {
          ref.invalidate(shoppingListProvider(listId));
          ref.invalidate(shoppingListsProvider);
        }
        return;
      case 'unbook':
        final bool confirmed = await _confirm(
          context,
          title: 'Batalkan pencatatan?',
          message:
              'Pengeluaran yang dibuat dari catatan ini akan dihapus. '
              'Catatan dan daftar itemnya tetap ada.',
          confirmLabel: 'Batalkan',
          destructive: true,
        );
        if (!confirmed) return;
        try {
          await repository.unbook(listId);
          ref.invalidate(shoppingListProvider(listId));
          ref.invalidate(shoppingListsProvider);
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(transactionsProvider);
          messenger.showSnackBar(
            const SnackBar(content: Text('Pencatatan dibatalkan.')),
          );
        } on Object catch (error) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                error is AppException ? error.message : 'Gagal membatalkan.',
              ),
            ),
          );
        }
        return;
      case 'delete':
        final bool confirmed = await _confirm(
          context,
          title: 'Hapus catatan?',
          message:
              'Catatan beserta daftar itemnya akan dihapus. '
              'Pengeluaran yang sudah tercatat tidak ikut terhapus.',
          confirmLabel: 'Hapus',
          destructive: true,
        );
        if (!confirmed) return;
        try {
          await repository.delete(listId);
          ref.invalidate(shoppingListsProvider);
          navigator.pop();
        } on Object catch (error) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                error is AppException
                    ? error.message
                    : 'Catatan gagal dihapus.',
              ),
            ),
          );
        }
        return;
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              DialogActions(
                onCancel: () => Navigator.pop(dialogContext, false),
                onConfirm: () => Navigator.pop(dialogContext, true),
                confirmLabel: confirmLabel,
                destructive: destructive,
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(BuildContext context, Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error is AppException ? error.message : fallback),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.note, this.onAddItem});

  final ShoppingListDetail note;

  /// Null once the note is booked: a booked note is read-only.
  final VoidCallback? onAddItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionTitle(note.list.title),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.event_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      Formatters.fullDate(note.list.shoppingDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (note.isBooked)
                    Text(
                      'Tercatat',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.incomeOf(theme.brightness),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (note.list.note case final String extra) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  extra,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(
                      label: 'Dicentang',
                      value: '${note.checkedCount}/${note.itemCount}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Berharga',
                      value: '${note.pricedCount}/${note.itemCount}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Total',
                      value: Formatters.currency(note.total),
                      emphasize: true,
                    ),
                  ),
                ],
              ),
              if (note.isBooked) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.incomeOf(theme.brightness),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Sudah masuk ke pengeluaran.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.incomeOf(theme.brightness),
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
        SectionHeader(
          title: 'Daftar item',
          subtitle: note.items.isEmpty
              ? null
              : '${note.itemCount} item · '
                    '${note.itemCount - note.pricedCount} tanpa harga',
          action: onAddItem == null
              ? null
              : TextButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                ),
        ),
        if (note.items.isNotEmpty && !note.isBooked)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _toggleAll(ref, !note.isComplete),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  note.isComplete ? 'Batal centang semua' : 'Centang semua',
                ),
              ),
            ),
          ),
        if (note.items.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Belum ada item.', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tambahkan barang belanjaan beserta jumlah dan harganya.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onAddItem != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onAddItem,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah item pertama'),
                  ),
                ],
              ],
            ),
          )
        else
          for (final ShoppingItem item in note.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ItemTile(note: note, item: item),
            ),
      ],
    );
  }

  Future<void> _toggleAll(WidgetRef ref, bool checked) async {
    final ShoppingRepository repository = await ref.read(
      shoppingRepositoryProvider.future,
    );
    await repository.setAllChecked(note.list.id, checked);
    ref.invalidate(shoppingListProvider(note.list.id));
    ref.invalidate(shoppingListsProvider);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: emphasize
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )
              : theme.textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.note, required this.item});

  final ShoppingListDetail note;
  final ShoppingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int? unitPrice = item.unitPrice;
    final bool locked = note.isBooked;
    final String subtitle = unitPrice == null
        ? '${item.quantity} × harga belum diisi'
        : '${item.quantity} × ${Formatters.currency(unitPrice)}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: item.isChecked,
            visualDensity: VisualDensity.compact,
            onChanged: locked
                ? null
                : (bool? value) => _toggle(ref, value ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: item.isChecked
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.isChecked
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (unitPrice != null)
                Text(
                  Formatters.currency(item.quantity * unitPrice),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              SizedBox(
                height: 28,
                child: !locked
                    ? PopupMenuButton<String>(
                        tooltip: 'Aksi item ${item.name}',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        splashRadius: 16,
                        onSelected: (String action) {
                          if (action == 'edit') {
                            _edit(context, ref);
                          } else {
                            _remove(context, ref);
                          }
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Ubah'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Hapus'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, bool checked) async {
    final ShoppingRepository repository = await ref.read(
      shoppingRepositoryProvider.future,
    );
    await repository.updateItem(item.id, isChecked: checked);
    ref.invalidate(shoppingListProvider(note.list.id));
    ref.invalidate(shoppingListsProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final _ItemDraft? draft = await showDialog<_ItemDraft>(
      context: context,
      builder: (_) => _ItemFormDialog(item: item),
    );
    if (draft == null) return;
    final ShoppingRepository repository = await ref.read(
      shoppingRepositoryProvider.future,
    );
    await repository.updateItem(
      item.id,
      name: draft.name,
      quantity: draft.quantity,
      unitPrice: draft.unitPrice,
      clearUnitPrice: draft.unitPrice == null,
    );
    ref.invalidate(shoppingListProvider(note.list.id));
    ref.invalidate(shoppingListsProvider);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ShoppingRepository repository = await ref.read(
      shoppingRepositoryProvider.future,
    );
    await repository.removeItem(item.id);
    ref.invalidate(shoppingListProvider(note.list.id));
    ref.invalidate(shoppingListsProvider);
  }
}

/// Result of the item form dialog.
class _ItemDraft {
  const _ItemDraft({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final int quantity;
  final int? unitPrice;
}

class _ItemFormDialog extends StatefulWidget {
  const _ItemFormDialog({this.item});

  final ShoppingItem? item;

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.item?.name ?? '',
  );
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.item?.quantity ?? 1}',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.item?.unitPrice == null
        ? ''
        : Formatters.number(widget.item!.unitPrice!),
  );

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Tambah item' : 'Ubah item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _name,
                autofocus: widget.item == null,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nama item',
                  hintText: 'Beras',
                ),
                validator: (String? value) =>
                    (value ?? '').trim().isEmpty ? 'Nama item wajib diisi.' : null,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Jumlah'),
                      validator: (String? value) {
                        final int? parsed = int.tryParse(value ?? '');
                        if (parsed == null || parsed <= 0) {
                          return 'Minimal 1';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Harga satuan',
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        DialogActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: _save,
          confirmLabel: 'Simpan',
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ItemDraft(
        name: _name.text.trim(),
        quantity: int.tryParse(_quantity.text) ?? 1,
        unitPrice: Formatters.parseAmount(_price.text),
      ),
    );
  }
}

/// Edits the note header from the detail page.
class _EditNoteDialog extends ConsumerStatefulWidget {
  const _EditNoteDialog({required this.note});

  final ShoppingList note;

  @override
  ConsumerState<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends ConsumerState<_EditNoteDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.note.title,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.note.note ?? '',
  );
  late DateTime _date = widget.note.shoppingDate;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah catatan'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Nama catatan'),
                validator: (String? value) =>
                    (value ?? '').trim().isEmpty ? 'Nama wajib diisi.' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _note,
                maxLength: 200,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('Tanggal: ${Formatters.fullDate(_date)}'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        DialogActions(
          onCancel: _saving ? null : () => Navigator.pop(context, false),
          onConfirm: _saving ? null : _save,
          confirmLabel: _saving ? 'Menyimpan...' : 'Simpan',
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final ShoppingRepository repository = await ref.read(
        shoppingRepositoryProvider.future,
      );
      await repository.updateHeader(
        widget.note.id,
        title: _title.text,
        shoppingDate: _date,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Catatan gagal disimpan.',
          ),
        ),
      );
    }
  }
}

/// Bottom bar that books the note total as one expense.
class _BookingBar extends ConsumerStatefulWidget {
  const _BookingBar({required this.note});

  final ShoppingListDetail note;

  @override
  ConsumerState<_BookingBar> createState() => _BookingBarState();
}

class _BookingBarState extends ConsumerState<_BookingBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = widget.note.total;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.borderOf(theme.brightness)),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Total belanja',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      Formatters.currency(total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (widget.note.isBooked)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  onPressed: _busy ? null : () => _unbook(context),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Batalkan'),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                  ),
                  onPressed: _busy || total <= 0 ? null : () => _book(context),
                  icon: const Icon(
                    Icons.playlist_add_check_rounded,
                    size: 18,
                  ),
                  label: Text(_busy ? 'Menyimpan...' : 'Catat pengeluaran'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _book(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final _BookingChoice? choice = await showDialog<_BookingChoice>(
      context: context,
      builder: (_) => _BookingDialog(note: widget.note),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final ShoppingRepository repository = await ref.read(
        shoppingRepositoryProvider.future,
      );
      await repository.book(
        widget.note.list.id,
        accountId: choice.accountId,
        categoryId: choice.categoryId,
        amount: choice.amount,
      );
      ref.invalidate(shoppingListProvider(widget.note.list.id));
      ref.invalidate(shoppingListsProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(recentTransactionsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${Formatters.currency(choice.amount)} masuk ke pengeluaran.',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Total belanja gagal dicatat.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbook(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Batalkan pencatatan?'),
            content: const Text(
              'Pengeluaran yang dibuat dari catatan ini akan dihapus. '
              'Catatan dan daftar itemnya tetap ada.',
            ),
            actions: <Widget>[
              DialogActions(
                onCancel: () => Navigator.pop(dialogContext, false),
                onConfirm: () => Navigator.pop(dialogContext, true),
                confirmLabel: 'Batalkan',
                destructive: true,
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final ShoppingRepository repository = await ref.read(
        shoppingRepositoryProvider.future,
      );
      await repository.unbook(widget.note.list.id);
      ref.invalidate(shoppingListProvider(widget.note.list.id));
      ref.invalidate(shoppingListsProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(transactionsProvider);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Pencatatan gagal dibatalkan.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// What the user picked in the booking dialog.
class _BookingChoice {
  const _BookingChoice({
    required this.accountId,
    required this.categoryId,
    required this.amount,
  });

  final int accountId;
  final int categoryId;
  final int amount;
}

/// Confirms the destination account, category and amount before booking.
class _BookingDialog extends ConsumerStatefulWidget {
  const _BookingDialog({required this.note});

  final ShoppingListDetail note;

  @override
  ConsumerState<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends ConsumerState<_BookingDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: Formatters.number(widget.note.total),
  );
  int? _accountId;
  int? _categoryId;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> accounts = (ref.watch(accountsProvider).value ??
            const <Account>[])
        .where((Account account) => !account.isArchived)
        .toList(growable: false);
    final List<Category> categories = (ref.watch(categoriesProvider).value ??
            const <Category>[])
        .where(
          (Category category) =>
              category.kind == CategoryKind.expense && !category.isArchived,
        )
        .toList(growable: false);

    final int? accountId = _accountId ??
        (accounts.isEmpty ? null : accounts.first.id);
    final int? categoryId = _categoryId ??
        _defaultCategoryId(categories);

    return AlertDialog(
      title: const Text('Catat sebagai pengeluaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              accounts.isEmpty
                  ? 'Tambahkan akun aktif dulu di Pengaturan > Akun Keuangan.'
                  : 'Total belanja akan dicatat sebagai satu pengeluaran.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (accounts.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bayar dari'),
                items: accounts
                    .map(
                      (Account account) => DropdownMenuItem<int>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (int? value) => setState(() => _accountId = value),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (categories.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: categories
                    .map(
                      (Category category) => DropdownMenuItem<int>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (int? value) => setState(() => _categoryId = value),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Total (bisa diubah)',
                prefixText: 'Rp ',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        DialogActions(
          onCancel: () => Navigator.pop(context),
          onConfirm: accounts.isEmpty || categoryId == null
              ? null
              : () {
                  final int? amount = Formatters.parseAmount(_amount.text);
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(
                    context,
                    _BookingChoice(
                      accountId: accountId!,
                      categoryId: categoryId,
                      amount: amount,
                    ),
                  );
                },
          confirmLabel: 'Catat',
        ),
      ],
    );
  }

  /// Prefers the seeded "Belanja" category, then any expense category.
  int? _defaultCategoryId(List<Category> categories) {
    if (categories.isEmpty) return null;
    for (final Category category in categories) {
      if (category.name.toLowerCase() == 'belanja') return category.id;
    }
    return categories.first.id;
  }
}
