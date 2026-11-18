import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bordered surface used as the base container for dashboard and list blocks.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BorderRadius radius = AppRadius.mediumAll;
    final Color color = backgroundColor ?? theme.colorScheme.surface;

    return Material(
      color: color,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? theme.colorScheme.outlineVariant,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
