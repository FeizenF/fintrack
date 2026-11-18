import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/formatters.dart';
import 'shared/providers/theme_mode_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Formatters.ensureInitialized();
  final ThemeMode initialThemeMode = await loadThemeModePreference();
  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(
          () => ThemeModeController(initial: initialThemeMode),
        ),
      ],
      child: const FinTrackApp(),
    ),
  );
}
