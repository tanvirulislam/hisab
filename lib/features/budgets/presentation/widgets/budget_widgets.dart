import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/app_formats.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../domain/budget.dart';

/// Color of a budget's progress for its level (§12.1).
Color budgetLevelColor(BuildContext context, BudgetLevel level) {
  final c = context.financeColors;
  return switch (level) {
    BudgetLevel.normal => Theme.of(context).colorScheme.primary,
    BudgetLevel.warning => c.warning,
    BudgetLevel.reached || BudgetLevel.over => c.danger,
  };
}

/// "৳540 left" or "৳250 over".
String remainingLabel(AppLocalizations l, AppFormats f, BudgetStatus s) => s.remaining.isNegative
    ? l.budgetOver(f.money.format(-s.remaining))
    : l.budgetLeft(f.money.format(s.remaining));

/// Fills up from empty when it first appears, after [delay], and runs to the
/// new value when it changes (D20).
class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({
    super.key,
    required this.percent,
    required this.color,
    this.height = 8,
    this.delay = Duration.zero,
  });

  final int percent;
  final Color color;
  final double height;
  final Duration delay;

  static const fill = Duration(milliseconds: 800);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: Motion.of(context, delay + fill),
      curve: Motion.delayed(delay, fill),
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: height,
        color: color,
        backgroundColor: color.withValues(alpha: 0.14),
      ),
    ),
  );
}

/// One budget: category, spent of allocated, progress, remaining (§12.2).
class BudgetTile extends ConsumerWidget {
  const BudgetTile({super.key, required this.status, this.index = 0, this.onTap});

  final BudgetStatus status;

  /// Position in its list: each bar starts filling a little after the one above.
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final color = budgetLevelColor(context, status.level);
    final name = status.category.displayName(lang);
    final delay = Duration(milliseconds: 150 + 110 * index);
    final percentText = Text('${f.integer(status.percent)}%',
        style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CategoryAvatar(iconKey: status.category.iconKey, color: Color(status.category.color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      // Reached or over: one shake once the bar is full.
                      if (status.level == BudgetLevel.reached || status.level == BudgetLevel.over)
                        ShakeOnce(delay: delay + BudgetProgressBar.fill, child: percentText)
                      else
                        percentText,
                    ],
                  ),
                  const SizedBox(height: 6),
                  BudgetProgressBar(percent: status.percent, color: color, delay: delay),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.budgetSpentOf(f.money.format(status.spent), f.money.format(status.budget.amount)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(remainingLabel(l, f, status),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status.remaining.isNegative ? color : null,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Allocated, spent and remaining over several budgets.
class BudgetTotalsCard extends ConsumerWidget {
  const BudgetTotalsCard({super.key, required this.totals, this.title, this.trailing});

  final BudgetTotals totals;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final over = totals.remaining.isNegative;
    // Overall colour uses the default warning threshold from Settings.
    final threshold = (ref.watch(appSettingsProvider).value ?? const AppSettings()).budgetWarningDefault;
    final level = totals.allocated.isPositive
        ? BudgetLevel.of(spent: totals.spent, amount: totals.allocated, warningThreshold: threshold)
        : BudgetLevel.normal;
    final color = budgetLevelColor(context, level);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title ?? l.budgetRemaining,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUpMoney(
                value: over ? -totals.remaining : totals.remaining,
                format: over ? (m) => l.budgetOver(f.money.format(m)) : null,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: over ? color : null),
              ),
            ),
            const SizedBox(height: 10),
            BudgetProgressBar(percent: totals.percent, color: color, height: 10),
            const SizedBox(height: 8),
            Text(
              l.budgetSpentOfPercent(
                  f.money.format(totals.spent), f.money.format(totals.allocated), f.integer(totals.percent)),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
