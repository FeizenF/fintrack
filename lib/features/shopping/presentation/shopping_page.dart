import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/shopping_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/section_title.dart';
import '../../../shared/providers/database_providers.dart';

/// Shopping notes list ("catatan belanja").
///
/// A note is a checklist with prices, not a ledger row. Booking its total from
/// the detail page creates exactly one expense, so the wallet only moves when
/// the user explicitly says the shopping is done.
class ShoppingPage extends ConsumerWidget {
  const ShoppingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ShoppingListDetail>> value = ref.watch(
      shoppingListsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Catatan Belanja')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Catatan belanja baru',
        onPressed: () => _openForm(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: value.when(
        loading: () => const LoadingState(message: 'Memuat catatan belanja...'),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Catatan belanja gagal dimuat.',
          onRetry: () => ref.invalidate(shoppingListsProvider),
        ),
        data: (List<ShoppingListDetail> notes) {
          if (notes.isEmpty) {
            return EmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'Belum ada catatan belanja',
              message:
                  'Tulis daftar belanjaan, isi harganya, lalu catat totalnya '
                  'sebagai pengeluaran.',
              action: FilledButton.icon(
                onPressed: () => _openForm(context, ref),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Buat catatan'),
              ),
            );
          }

          final List<ShoppingListDetail> open = notes
              .where((ShoppingListDetail note) => !note.isBooked)
              .toList(growable: false);
          final List<ShoppingListDetail> booked = notes
              .where((ShoppingListDetail note) => note.isBooked)
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl * 4,
            ),
            children: <Widget>[
              if (open.isNotEmpty) ...<Widget>[
                const SectionHeader(title: 'Belum dicatat'),
                for (final ShoppingListDetail note in open)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _NoteCard(note: note),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (booked.isNotEmpty) ...<Widget>[
                const SectionHeader(title: 'Sudah masuk pengeluaran'),
                for (final ShoppingListDetail note in booked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _NoteCard(note: note),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, [
    ShoppingList? note,
  ]) async {
    final int? savedId = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => _NoteFormDialog(note: note),
    );
    if (savedId == null || !context.mounted) return;
    ref.invalidate(shoppingListsProvider);
    if (note == null) {
      // Jump straight into the new note so items can be added right away.
      context.push(AppRoutes.shoppingDetail(savedId));
    }
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final ShoppingListDetail note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final bool hasTotal = note.total > 0;
    final bool done = note.isBooked;
    final Color accent = done
        ? AppColors.incomeOf(brightness)
        : theme.colorScheme.primary;
    final int unpriced = note.itemCount - note.pricedCount;

    return AppCard(
      onTap: () => context.push(AppRoutes.shoppingDetail(note.list.id)),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: AppRadius.smallAll,
                ),
                child: Icon(
                  done
                      ? Icons.check_rounded
                      : Icons.shopping_basket_outlined,
                  size: 19,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionTitle(note.list.title),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.fullDate(note.list.shoppingDate)} · '
                      '${note.itemCount} item',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusChip(
                icon: done
                    ? Icons.check_circle_rounded
                    : note.isComplete
                    ? Icons.shopping_cart_checkout_rounded
                    : Icons.pending_outlined,
                label: done
                    ? 'Tercatat'
                    : note.isComplete
                    ? 'Siap dicatat'
                    : '${note.checkedCount}/${note.itemCount}',
                color: done || note.isComplete
                    ? accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  hasTotal ? Formatters.currency(note.total) : 'Belum ada harga',
                  style: hasTotal
                      ? theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                ),
              ),
              if (unpriced > 0)
                Text(
                  '$unpriced tanpa harga',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warningOf(brightness),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          if (note.list.note case final String extra) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              extra,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smallAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Create/rename a shopping note.
class _NoteFormDialog extends ConsumerStatefulWidget {
  const _NoteFormDialog({this.note});

  final ShoppingList? note;

  @override
  ConsumerState<_NoteFormDialog> createState() => _NoteFormDialogState();
}

class _NoteFormDialogState extends ConsumerState<_NoteFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.note?.note ?? '',
  );
  late DateTime _date = widget.note?.shoppingDate ?? DateTime.now();
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
      title: Text(
        widget.note == null ? 'Catatan belanja baru' : 'Ubah catatan',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _title,
                autofocus: widget.note == null,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nama catatan',
                  hintText: 'Belanja mingguan',
                ),
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
                  hintText: 'Bahan masakan seminggu',
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
          // `showDialog<int>` returns the saved id, so cancel must pop nothing
          // rather than `false` — that mismatch is what made Batal dead.
          onCancel: _saving ? null : () => Navigator.pop(context),
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
      final int savedId;
      if (widget.note == null) {
        savedId = await repository.create(
          title: _title.text,
          shoppingDate: _date,
          note: _note.text,
        );
      } else {
        await repository.updateHeader(
          widget.note!.id,
          title: _title.text,
          shoppingDate: _date,
          note: _note.text,
        );
        savedId = widget.note!.id;
      }
      if (mounted) Navigator.pop(context, savedId);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Catatan gagal disimpan. Silakan coba lagi.',
          ),
        ),
      );
    }
  }
}
