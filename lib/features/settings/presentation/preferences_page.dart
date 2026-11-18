import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/providers/database_providers.dart';
import '../../../shared/providers/theme_mode_provider.dart';

/// User-visible preferences that are persisted in `app_settings`.
class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(themeModeProvider);
    final AsyncValue<bool> hidden = ref.watch(hideBalancesProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Preferensi Aplikasi'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          const _SectionLabel('Tampilan'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              children: <Widget>[
                _ThemeOption(
                  icon: Icons.light_mode_outlined,
                  label: 'Terang',
                  description: 'Selalu gunakan tema terang',
                  selected: mode == ThemeMode.light,
                  onTap: () => _selectTheme(context, ref, ThemeMode.light),
                ),
                const Divider(height: 1, indent: AppSpacing.lg + 32),
                _ThemeOption(
                  icon: Icons.dark_mode_outlined,
                  label: 'Gelap',
                  description: 'Selalu gunakan tema gelap',
                  selected: mode == ThemeMode.dark,
                  onTap: () => _selectTheme(context, ref, ThemeMode.dark),
                ),
                const Divider(height: 1, indent: AppSpacing.lg + 32),
                _ThemeOption(
                  icon: Icons.brightness_auto_outlined,
                  label: 'Ikuti sistem',
                  description: 'Sesuaikan dengan pengaturan Android',
                  selected: mode == ThemeMode.system,
                  onTap: () => _selectTheme(context, ref, ThemeMode.system),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('Privasi'),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Sembunyikan saldo'),
              subtitle: const Text(
                'Nominal disamarkan agar aman dilihat di tempat umum',
              ),
              value: hidden.value ?? false,
              onChanged: hidden.hasValue
                  ? (bool value) => _setHidden(context, ref, value)
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionLabel('Tentang'),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: <Widget>[
                _InfoRow(label: 'Aplikasi', value: AppConstants.appName),
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(label: 'Versi', value: AppConstants.appVersion),
                const SizedBox(height: AppSpacing.sm),
                const _InfoRow(
                  label: 'Penyimpanan',
                  value: 'Lokal, tanpa server',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Seluruh data keuangan disimpan di perangkat ini dan tidak pernah '
            'dikirim ke server mana pun. Buat backup berkala agar data aman '
            'saat ganti perangkat.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    final ThemeMode previous = ref.read(themeModeProvider);
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    try {
      final AppDatabase database = await ref.read(appDatabaseProvider.future);
      await database.saveSetting(
        SettingKeys.themeMode,
        themeModeToStorage(mode),
      );
    } on Object {
      if (!context.mounted) return;
      ref.read(themeModeProvider.notifier).setThemeMode(previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferensi tema gagal disimpan.')),
      );
    }
  }

  Future<void> _setHidden(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await setHideBalances(ref, value);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferensi saldo gagal disimpan.')),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppColors.mutedTextOf(theme.brightness),
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      selected: selected,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.smallAll,
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
      ),
      title: Text(label, style: theme.textTheme.titleSmall),
      subtitle: Text(
        description,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
          : null,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
