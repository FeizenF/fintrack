import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_routes.dart';
import '../theme/app_colors.dart';
import 'app_shell_destination.dart';

/// Persistent five-tab app shell with a global add-transaction entry point.
///
/// Compact widths use a bottom [NavigationBar]; widths >= 720dp use a
/// [NavigationRail] beside the content. Exactly one FAB is rendered in both
/// layouts.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 720;

    final Widget body = SafeArea(top: false, child: navigationShell);

    final Widget fab = FloatingActionButton.extended(
      heroTag: 'add-transaction',
      onPressed: () => context.push(AppRoutes.transactionNew),
      icon: const Icon(Icons.add_rounded),
      label: Text(wide ? 'Catat transaksi' : 'Catat'),
    );

    final Scaffold content = Scaffold(
      body: body,
      floatingActionButton: fab,
      bottomNavigationBar: wide
          ? null
          : _BottomNavBar(
              selectedIndex: navigationShell.currentIndex,
              onSelected: _onDestinationSelected,
            ),
    );

    if (!wide) return content;

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xl,
                bottom: AppSpacing.lg,
              ),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: AppRadius.smallAll,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.gold,
                  size: 23,
                ),
              ),
            ),
            destinations: AppShellDestination.values
                .map((AppShellDestination destination) => destination.railDestination)
                .toList(growable: false),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Bottom navigation with a hairline separator and a clamped label scale.
///
/// Accessibility font scaling is capped at 1.2 inside the bar only: navigation
/// labels are single-line by design, and letting them grow without bound is
/// what pushed the last letter of a label onto a second line.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: AppShellDestination.values
              .map((AppShellDestination destination) => destination.destination)
              .toList(growable: false),
        ),
      ),
    );
  }
}
