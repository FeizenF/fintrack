import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Title used at the top of every card/section.
///
/// Card titles previously mixed `titleLarge`, `titleMedium` and `titleSmall`
/// depending on the page, so the same kind of heading rendered at different
/// heights and line positions on different screens. Everything now goes through
/// this widget: one type style, one weight, one baseline height.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  /// Line height shared by every section heading.
  ///
  /// Fixed instead of inherited so a long title that wraps to two lines still
  /// starts on the same baseline as a short one on the next card.
  static const double lineHeight = 1.3;

  /// The single style shared by all section headings.
  static TextStyle? styleOf(ThemeData theme) => theme.textTheme.titleMedium
      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1, height: lineHeight);

  /// Height of one title line, used to reserve identical leading space.
  static double heightOf(ThemeData theme) {
    final TextStyle? style = styleOf(theme);
    final double fontSize = style?.fontSize ?? 16;
    return fontSize * (style?.height ?? lineHeight);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Text title = Text(
      text,
      style: styleOf(theme),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (trailing == null) return title;

    return Row(
      children: <Widget>[
        Expanded(child: title),
        const SizedBox(width: AppSpacing.sm),
        trailing!,
      ],
    );
  }
}

/// Description line that sits directly under a [SectionTitle].
///
/// Wrapping the body copy in one helper keeps the gap between a title and its
/// supporting text identical everywhere.
class SectionDescription extends StatelessWidget {
  const SectionDescription(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    );
  }
}
