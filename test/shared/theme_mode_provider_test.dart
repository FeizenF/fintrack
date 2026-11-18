import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fintrack/shared/providers/theme_mode_provider.dart';

void main() {
  test('theme storage round-trips every mode', () {
    for (final ThemeMode mode in ThemeMode.values) {
      expect(themeModeFromStorage(themeModeToStorage(mode)), mode);
    }
  });

  test('unknown or missing storage falls back to the system theme', () {
    expect(themeModeFromStorage(null), ThemeMode.system);
    expect(themeModeFromStorage('sepia'), ThemeMode.system);
  });

  test('stored values are stable strings, not enum indexes', () {
    expect(themeModeToStorage(ThemeMode.light), 'light');
    expect(themeModeToStorage(ThemeMode.dark), 'dark');
    expect(themeModeToStorage(ThemeMode.system), 'system');
  });
}
