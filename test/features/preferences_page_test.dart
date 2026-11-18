import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fintrack/core/constants/app_constants.dart';
import 'package:fintrack/core/theme/app_theme.dart';
import 'package:fintrack/features/settings/presentation/preferences_page.dart';
import 'package:fintrack/shared/providers/database_providers.dart';

void main() {
  testWidgets('preferences page lists themes, privacy toggle and app info', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hideBalancesProvider.overrideWithValue(const AsyncData<bool>(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PreferencesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terang'), findsOneWidget);
    expect(find.text('Gelap'), findsOneWidget);
    expect(find.text('Ikuti sistem'), findsOneWidget);
    expect(find.text('Sembunyikan saldo'), findsOneWidget);
    expect(find.text(AppConstants.appVersion), findsOneWidget);
  });

  testWidgets('back falls back to settings when there is no route to pop', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/preferences',
      routes: <RouteBase>[
        GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('SETTINGS_HOME')),
        ),
        GoRoute(
          path: '/preferences',
          builder: (BuildContext context, GoRouterState state) =>
              const PreferencesPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hideBalancesProvider.overrideWithValue(const AsyncData<bool>(false)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SETTINGS_HOME'), findsOneWidget);
  });
}
