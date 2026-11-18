import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Builds the light and dark Material 3 themes for FinTrack.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.goldSoft : AppColors.navy,
      onPrimary: isDark ? AppColors.navyDeep : Colors.white,
      primaryContainer: isDark ? const Color(0xFF243354) : const Color(0xFFE6EAF3),
      onPrimaryContainer: isDark ? AppColors.goldSoft : AppColors.navy,
      secondary: AppColors.gold,
      onSecondary: AppColors.navyDeep,
      secondaryContainer: isDark ? const Color(0xFF3A3218) : const Color(0xFFF6EDD2),
      onSecondaryContainer: isDark ? AppColors.goldSoft : const Color(0xFF6B5416),
      tertiary: isDark ? AppColors.incomeDark : AppColors.income,
      onTertiary: isDark ? AppColors.navyDeep : Colors.white,
      error: isDark ? AppColors.expenseDark : AppColors.expense,
      onError: isDark ? AppColors.navyDeep : Colors.white,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? const Color(0xFFE8ECF4) : const Color(0xFF1B2431),
      onSurfaceVariant:
          isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
      outline: isDark ? AppColors.darkBorder : AppColors.lightBorder,
      outlineVariant:
          isDark ? const Color(0xFF212B3E) : const Color(0xFFEDEFF3),
      surfaceContainerLowest:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      surfaceContainerLow: isDark ? AppColors.darkSurface : Colors.white,
      surfaceContainer: isDark ? const Color(0xFF1D2739) : const Color(0xFFF2F4F7),
      surfaceContainerHigh:
          isDark ? const Color(0xFF233046) : const Color(0xFFEDF0F5),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2A3752) : const Color(0xFFE7EAEF),
    );

    final TextTheme base = Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final TextTheme textTheme = base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.4),
      bodySmall: base.bodySmall?.copyWith(height: 1.35),
    );

    final Color surface = scheme.surface;
    final Color background = scheme.surfaceContainerLowest;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mediumAll,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: isDark ? AppColors.goldSoft : AppColors.navy,
        unselectedItemColor: scheme.onSurfaceVariant,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark
            ? AppColors.gold.withValues(alpha: 0.18)
            : AppColors.navy.withValues(alpha: 0.08),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (isDark ? AppColors.goldSoft : AppColors.navy)
                : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? (isDark ? AppColors.goldSoft : AppColors.navy)
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2537) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.smallAll,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smallAll,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.smallAll,
          borderSide: BorderSide(
            color: isDark ? AppColors.goldSoft : AppColors.navy,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smallAll,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smallAll,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: isDark ? AppColors.gold : AppColors.navy,
          foregroundColor: isDark ? AppColors.navyDeep : Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.smallAll,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: isDark ? AppColors.goldSoft : AppColors.navy,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.smallAll,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.goldSoft : AppColors.navy,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? AppColors.gold : AppColors.navy,
        foregroundColor: isDark ? AppColors.navyDeep : Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mediumAll,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: isDark
            ? AppColors.gold.withValues(alpha: 0.2)
            : AppColors.navy.withValues(alpha: 0.08),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mediumAll,
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A3752) : AppColors.navy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.smallAll,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.smallAll,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? AppColors.gold : AppColors.navy,
        linearTrackColor: scheme.surfaceContainerHigh,
        linearMinHeight: 6,
      ),
      // Keeps the pressed/selected visual consistent for cards.
      splashColor: (isDark ? AppColors.gold : AppColors.navy)
          .withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
    );
  }
}
