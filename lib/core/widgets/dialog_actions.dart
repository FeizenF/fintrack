import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Cancel/confirm pair for [AlertDialog] actions.
///
/// The global filled-button style uses `Size.fromHeight(52)` (infinite minimum
/// width) so primary buttons stretch across forms. Inside [AlertDialog.actions]
/// that minimum made the confirm button claim the whole row, so [OverflowBar]
/// pushed the cancel button onto a line of its own and the pair stopped lining
/// up. This row pins both buttons to the same height and splits the width
/// evenly, which keeps every dialog in the app aligned.
class DialogActions extends StatelessWidget {
  const DialogActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.cancelLabel = 'Batal',
    required this.confirmLabel,
    this.destructive = false,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;

  static const ButtonStyle _sizing = ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(Size(0, 48)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: AppSpacing.md),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ButtonStyle confirmStyle = destructive
        ? _sizing.merge(
            FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
          )
        : _sizing;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: TextButton(
              style: _sizing,
              onPressed: onCancel,
              child: Text(cancelLabel),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              style: confirmStyle,
              onPressed: onConfirm,
              child: Text(confirmLabel, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
