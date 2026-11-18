import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/theme_mode_provider.dart';

class FinTrackApp extends ConsumerWidget {
  const FinTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'FinTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('id'),
      supportedLocales: const <Locale>[Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
