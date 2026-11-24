import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/tab_page_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const TabPageHeader(
            title: 'Pengaturan',
            subtitle: 'Data, keamanan dan preferensi aplikasi',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xxl * 4,
              ),
              children: <Widget>[
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: <Widget>[
                      _SettingsTile(
                        icon: Icons.account_balance_outlined,
                        title: 'Akun Keuangan',
                        subtitle: 'Cash, bank, e-wallet, dana usaha',
                        onTap: () => context.push(AppRoutes.accounts),
                      ),
                      const Divider(height: 1, indent: AppSpacing.lg + 32),
                      _SettingsTile(
                        icon: Icons.category_outlined,
                        title: 'Kategori',
                        subtitle: 'Kategori pemasukan dan pengeluaran',
                        onTap: () => context.push(AppRoutes.categories),
                      ),
                      const Divider(height: 1, indent: AppSpacing.lg + 32),
                      _SettingsTile(
                        icon: Icons.savings_outlined,
                        title: 'Target Tabungan',
                        subtitle: 'Dana darurat, laptop baru, modal usaha',
                        onTap: () => context.push(AppRoutes.savings),
                      ),
                      const Divider(height: 1, indent: AppSpacing.lg + 32),
                      _SettingsTile(
                        icon: Icons.shopping_basket_outlined,
                        title: 'Catatan Belanja',
                        subtitle: 'Daftar belanjaan yang bisa langsung dicatat',
                        onTap: () => context.push(AppRoutes.shopping),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: <Widget>[
                      _SettingsTile(
                        icon: Icons.backup_outlined,
                        title: 'Backup & Restore',
                        subtitle: 'Amankan dan pulihkan seluruh data',
                        onTap: () => context.push(AppRoutes.backup),
                      ),
                      const Divider(height: 1, indent: AppSpacing.lg + 32),
                      _SettingsTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Keamanan',
                        subtitle: 'PIN, biometrik dan auto-lock',
                        onTap: () => context.push(AppRoutes.security),
                      ),
                      const Divider(height: 1, indent: AppSpacing.lg + 32),
                      _SettingsTile(
                        icon: Icons.tune_rounded,
                        title: 'Preferensi Aplikasi',
                        subtitle: 'Tema dan preferensi tampilan',
                        onTap: () => context.push(AppRoutes.preferences),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: Text(
                    '${AppConstants.appName} ${AppConstants.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.smallAll,
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
      ),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}
