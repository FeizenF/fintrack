import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Income, expense and net result for one period.
///
/// One row per flow (label, amount and a bar scaled to the larger value) keeps
/// the comparison readable on phone widths, while the net result gets its own
/// full-width block so it cannot be mistaken for another category total. The
/// dashboard and reports use the same widget so both pages read identically.
class CashFlowSummary extends StatelessWidget {
  const CashFlowSummary({
    super.key,
    required this.income,
    required this.expense,
    this.hidden = false,
    this.showNet = true,
    this.showPercent = true,
    this.emptyHint = 'Belum ada transaksi pada periode ini.',
  });

  final int income;
  final int expense;
  final bool hidden;
  final bool showNet;
  final bool showPercent;
  final String emptyHint;

  int get _net => income - expense;

  int get _max => income > expense ? income : expense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final Color incomeColor = AppColors.incomeOf(brightness);
    final Color expenseColor = AppColors.expenseOf(brightness);
    final int max = _max;
    final bool empty = max <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FlowBar(
          label: 'Pemasukan',
          amount: Formatters.maskedCurrency(income, hidden: hidden),
          ratio: empty ? 0 : income / max,
          color: incomeColor,
        ),
        const SizedBox(height: AppSpacing.md),
        _FlowBar(
          label: 'Pengeluaran',
          amount: Formatters.maskedCurrency(expense, hidden: hidden),
          ratio: empty ? 0 : expense / max,
          color: expenseColor,
        ),
        if (empty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Icon(
                Icons.insights_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  emptyHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ] else if (showPercent && !hidden && income > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pengeluaran ${(expense / income * 100).round()}% dari pemasukan',
            style: theme.textTheme.bodySmall?.copyWith(
              color: expense > income
                  ? expenseColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (showNet) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _NetSummary(net: _net, hidden: hidden),
        ],
      ],
    );
  }
}

class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.label,
    required this.amount,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String amount;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  amount,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 8,
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// Full-width net result with an explicit surplus/deficit label.
class _NetSummary extends StatelessWidget {
  const _NetSummary({required this.net, required this.hidden});

  final int net;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final bool surplus = net >= 0;
    final Color color = surplus
        ? AppColors.incomeOf(brightness)
        : AppColors.expenseOf(brightness);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              surplus
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Selisih',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  surplus ? 'Surplus' : 'Defisit',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                Formatters.maskedCurrency(net.abs(), hidden: hidden),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
