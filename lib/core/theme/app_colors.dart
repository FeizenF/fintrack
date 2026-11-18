import 'package:flutter/material.dart';

/// Central palette for FinTrack.
///
/// The palette is intentionally small: a deep navy surface family, a single
/// gold accent, and two semantic colors (income / expense).
abstract final class AppColors {
  // Brand
  static const Color navy = Color(0xFF14213D);
  static const Color navyDeep = Color(0xFF0D1730);
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldSoft = Color(0xFFE8CC6E);

  // Surfaces
  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF101827);
  static const Color darkSurface = Color(0xFF182132);

  // Semantic
  static const Color income = Color(0xFF12855A);
  static const Color incomeDark = Color(0xFF3DD68C);
  static const Color expense = Color(0xFFC0392B);
  static const Color expenseDark = Color(0xFFFF7A6B);
  static const Color warning = Color(0xFFB7791F);
  static const Color warningDark = Color(0xFFF0B429);

  // Neutral
  static const Color lightBorder = Color(0xFFE4E7EC);
  static const Color darkBorder = Color(0xFF2A3448);
  static const Color lightMutedText = Color(0xFF5B6472);
  static const Color darkMutedText = Color(0xFF9AA5B8);

  static Color incomeOf(Brightness brightness) =>
      brightness == Brightness.dark ? incomeDark : income;

  static Color expenseOf(Brightness brightness) =>
      brightness == Brightness.dark ? expenseDark : expense;

  static Color warningOf(Brightness brightness) =>
      brightness == Brightness.dark ? warningDark : warning;

  static Color mutedTextOf(Brightness brightness) =>
      brightness == Brightness.dark ? darkMutedText : lightMutedText;

  static Color borderOf(Brightness brightness) =>
      brightness == Brightness.dark ? darkBorder : lightBorder;
}

/// Spacing scale used across the app so layouts stay consistent.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Shared corner radii.
abstract final class AppRadius {
  static const Radius small = Radius.circular(10);
  static const Radius medium = Radius.circular(16);
  static const Radius large = Radius.circular(24);

  static const BorderRadius smallAll = BorderRadius.all(small);
  static const BorderRadius mediumAll = BorderRadius.all(medium);
  static const BorderRadius largeAll = BorderRadius.all(large);
}
