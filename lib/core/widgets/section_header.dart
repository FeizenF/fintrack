import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'section_title.dart';

/// Section title with optional trailing action.
///
/// The title style comes from [SectionTitle] so a heading looks the same here as
/// it does inside a card.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        right: AppSpacing.xs,
        bottom: AppSpacing.md,
      ),
      child: Row(
        // Top-aligned, not centred: a header with a subtitle or a trailing
        // button is taller than one without, and centring used to push the
        // title up by half of that extra height. Starting at the top keeps
        // every section title on the same line across the page.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: SectionTitle.heightOf(theme),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: SectionTitle.styleOf(theme),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (subtitle case final String text)
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
