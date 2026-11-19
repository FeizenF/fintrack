import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/repositories/categories_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/dialog_actions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state_view.dart';
import '../../../core/widgets/loading_state.dart';
import '../../../shared/providers/database_providers.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Category>> value = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Pengeluaran'),
            Tab(text: 'Pemasukan'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, _kindForTab),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah kategori'),
      ),
      body: value.when(
        loading: () => const LoadingState(message: 'Memuat kategori...'),
        error: (Object error, StackTrace stack) =>
            const ErrorStateView(message: 'Kategori gagal dimuat.'),
        data: (List<Category> rows) => TabBarView(
          controller: _tabs,
          children: <Widget>[
            _CategoryList(
              rows: rows.where((c) => c.kind == CategoryKind.expense).toList(),
              onAction: _handleAction,
              onAdd: () => _showForm(context, CategoryKind.expense),
            ),
            _CategoryList(
              rows: rows.where((c) => c.kind == CategoryKind.income).toList(),
              onAction: _handleAction,
              onAdd: () => _showForm(context, CategoryKind.income),
            ),
          ],
        ),
      ),
    );
  }

  CategoryKind get _kindForTab =>
      _tabs.index == 0 ? CategoryKind.expense : CategoryKind.income;

  Future<void> _showForm(
    BuildContext context,
    CategoryKind kind, {
    Category? category,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          _CategoryFormDialog(kind: kind, category: category),
    );
    if (saved == true) ref.invalidate(categoriesProvider);
  }

  Future<void> _handleAction(Category category, String action) async {
    if (action == 'edit') {
      await _showForm(context, category.kind, category: category);
      return;
    }
    final CategoriesRepository repository = await ref.read(
      categoriesRepositoryProvider.future,
    );
    if (!mounted) return;
    try {
      if (action == 'archive') {
        await repository.setArchived(category.id, !category.isArchived);
      } else if (action == 'delete') {
        final bool confirmed =
            await showDialog<bool>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('Hapus kategori?'),
                content: Text('Kategori "${category.name}" akan dihapus.'),
                actions: <Widget>[
                  DialogActions(
                    onCancel: () => Navigator.pop(context, false),
                    onConfirm: () => Navigator.pop(context, true),
                    confirmLabel: 'Hapus',
                    destructive: true,
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return;
        await repository.delete(category.id);
      }
      ref.invalidate(categoriesProvider);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is AppException
                  ? error.message
                  : 'Kategori gagal diubah. Silakan coba lagi.',
            ),
          ),
        );
      }
    }
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.rows,
    required this.onAction,
    required this.onAdd,
  });

  final List<Category> rows;
  final Future<void> Function(Category category, String action) onAction;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        title: 'Belum ada kategori',
        message: 'Tambahkan kategori untuk merapikan transaksi.',
        action: OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tambah kategori'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl * 3,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final Category category = rows[index];
        final String origin = category.isDefault ? 'Default' : 'Buatan sendiri';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                category.kind == CategoryKind.income
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
              ),
            ),
            title: Text(category.name),
            subtitle: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: origin),
                  if (category.isArchived)
                    TextSpan(
                      text: ' · Diarsipkan',
                      style: TextStyle(
                        color: AppColors.warningOf(
                          Theme.of(context).brightness,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Aksi kategori ${category.name}',
              onSelected: (String value) {
                onAction(category, value);
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'edit', child: Text('Ubah')),
                PopupMenuItem<String>(
                  value: 'archive',
                  child: Text(category.isArchived ? 'Pulihkan' : 'Arsipkan'),
                ),
                if (!category.isDefault)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Hapus'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({required this.kind, this.category});

  final CategoryKind kind;
  final Category? category;

  @override
  ConsumerState<_CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category == null ? 'Tambah kategori' : 'Ubah kategori'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'Nama kategori'),
    ),
    actions: <Widget>[
      DialogActions(
        onCancel: _saving ? null : () => Navigator.pop(context, false),
        onConfirm: _saving ? null : _save,
        confirmLabel: _saving ? 'Menyimpan...' : 'Simpan',
      ),
    ],
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final CategoriesRepository repository = await ref.read(
        categoriesRepositoryProvider.future,
      );
      if (widget.category == null) {
        await repository.create(name: _name.text, kind: widget.kind);
      } else {
        await repository.update(widget.category!.id, name: _name.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is AppException
                  ? error.message
                  : 'Kategori gagal disimpan. Silakan coba lagi.',
            ),
          ),
        );
      }
    }
  }
}
