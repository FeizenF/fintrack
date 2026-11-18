import 'package:flutter/material.dart';

/// Navigation destinations shared by compact and wide app shells.
enum AppShellDestination {
  home('Beranda', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  transactions('Transaksi', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  budgets('Anggaran', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded),
  reports('Laporan', Icons.query_stats_outlined, Icons.query_stats_rounded),
  settings('Setelan', Icons.tune_outlined, Icons.tune_rounded);

  const AppShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  NavigationDestination get destination => NavigationDestination(
        icon: Icon(icon),
        selectedIcon: Icon(selectedIcon),
        label: label,
      );

  NavigationRailDestination get railDestination => NavigationRailDestination(
        icon: Icon(icon),
        selectedIcon: Icon(selectedIcon),
        label: Text(label),
      );
}
