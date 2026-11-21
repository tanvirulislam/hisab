import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/app_formats.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../../workspaces/presentation/widgets/workspace_selector.dart';
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

class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({super.key, required this.percent, required this.color, this.height = 8});

  final int percent;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: (percent.clamp(0, 100)) / 100,
      minHeight: height,
      color: color,
      backgroundColor: color.withValues(alpha: 0.14),
    ),
  );
}

/// One budget: category, spent of allocated, progress, remaining (§12.2).
class BudgetTile extends ConsumerWidget {
  const BudgetTile({super.key, required this.status, this.showWorkspace = false, this.onTap});

  final BudgetStatus status;
  final bool showWorkspace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final color = budgetLevelColor(context, status.level);
    final name = status.category.displayName(lang);
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
                          showWorkspace ? '$name · ${workspaceTypeLabel(l, status.workspaceType)}' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text('${f.integer(status.percent)}%',
                          style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  BudgetProgressBar(percent: status.percent, color: color),
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
              child: Text(
                over ? l.budgetOver(f.money.format(-totals.remaining)) : f.money.format(totals.remaining),
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
