import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';

/// Theme preference for the whole app.
///
/// The initial value is injected at startup (see [loadThemeModePreference])
/// so the very first frame already uses the stored theme. The selected mode is
/// written to `app_settings` when the user changes it in the preferences page.
class ThemeModeController extends Notifier<ThemeMode> {
  ThemeModeController({this.initial = ThemeMode.system});

  final ThemeMode initial;

  @override
  ThemeMode build() => initial;

  void setThemeMode(ThemeMode mode) {
    if (state != mode) state = mode;
  }
}

final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Stable storage representation; never persist enum indexes.
String themeModeToStorage(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

ThemeMode themeModeFromStorage(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Reads the persisted theme before the first frame.
///
/// The application database provider is not available yet at this point, so a
/// short-lived connection is opened and closed again. Any failure falls back to
/// the system theme instead of blocking startup.
Future<ThemeMode> loadThemeModePreference() async {
  AppDatabase? database;
  try {
    final File file = await AppDatabase.defaultDatabaseFile();
    database = AppDatabase.atFile(file);
    return themeModeFromStorage(
      await database.readSetting(SettingKeys.themeMode),
    );
  } on Object {
    return ThemeMode.system;
  } finally {
    await database?.close();
  }
}
