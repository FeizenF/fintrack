import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/backup/presentation/backup_page.dart';
import '../../features/budgets/presentation/budgets_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/savings/presentation/savings_page.dart';
import '../../features/settings/presentation/preferences_page.dart';
import '../../features/settings/presentation/security_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shopping/presentation/shopping_detail_page.dart';
import '../../features/shopping/presentation/shopping_page.dart';
import '../../features/transactions/presentation/transaction_form_page.dart';
import '../../features/transactions/presentation/transaction_page.dart';
import '../../features/transactions/presentation/transaction_detail_page.dart';
import '../constants/app_routes.dart';
import '../widgets/app_shell.dart';

/// Application router. Stateful branches retain tab state while switching.
///
/// Created per [ProviderScope] so navigating in one scope never leaks into
/// another (important for tests and for full app resets).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (BuildContext context, GoRouterState state,
              StatefulNavigationShell navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const DashboardPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.transactions,
              builder: (context, state) => const TransactionsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.budgets,
              builder: (context, state) => const BudgetsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.reports,
              builder: (context, state) => const ReportsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.transactionNew,
      builder: (context, state) => const TransactionFormPage(),
    ),
    GoRoute(
      path: AppRoutes.transactionDetailPattern,
      builder: (context, state) => TransactionDetailPage(
        transactionId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: AppRoutes.transactionEditPattern,
      builder: (context, state) => TransactionFormPage(
        transactionId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: AppRoutes.accounts,
      builder: (context, state) => const AccountsPage(),
    ),
    GoRoute(
      path: AppRoutes.categories,
      builder: (context, state) => const CategoriesPage(),
    ),
    GoRoute(
      path: AppRoutes.savings,
      builder: (context, state) => const SavingsPage(),
    ),
    GoRoute(
      path: AppRoutes.backup,
      builder: (context, state) => const BackupPage(),
    ),
    GoRoute(
      path: AppRoutes.security,
      builder: (context, state) => const SecurityPage(),
    ),
    GoRoute(
      path: AppRoutes.preferences,
      builder: (context, state) => const PreferencesPage(),
    ),
    GoRoute(
      path: AppRoutes.shopping,
      builder: (context, state) => const ShoppingPage(),
      routes: <RouteBase>[
        GoRoute(
          path: ':id',
          builder: (context, state) => ShoppingDetailPage(
            listId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    ),
  ],
);
