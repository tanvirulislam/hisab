import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/local_date.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../l10n/l10n.dart';
import '../../../categories/domain/category.dart';
import '../../../settings/presentation/app_formats.dart';
import '../../../transactions/domain/history_filter.dart';
import '../../../transactions/presentation/transaction_providers.dart';
import '../../../workspaces/presentation/widgets/workspace_selector.dart';
import '../../domain/report_math.dart';
import '../../domain/report_models.dart';
import '../report_providers.dart';
import 'report_charts.dart';

/// Income / Expense / Net tiles (§5.1, §11).
class SummaryTiles extends ConsumerWidget {
  const SummaryTiles({super.key, required this.totals, this.netLabel});

  final PeriodTotals totals;
  final String? netLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    return Row(
      children: [
        Expanded(child: StatTile(label: l.summaryIncome, value: f.money.format(totals.income), color: colors.income)),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: l.summaryExpense, value: f.money.format(totals.expense), color: colors.expense)),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            label: netLabel ?? l.summaryNet,
            value: f.money.format(totals.net),
            color: totals.net.isNegative ? colors.expense : Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color, this.icon});

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 4)],
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "12% more than last month" (§11.3 previous month comparison).
class ComparisonText extends ConsumerWidget {
  const ComparisonText({super.key, required this.previous, required this.current});

  final Money previous;
  final Money current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final change = ReportMath.percentChange(previous, current);
    final (text, color, icon) = switch (change) {
      null => (l.vsLastMonthNone, null, Icons.remove),
      0 => (l.vsLastMonthSame, null, Icons.trending_flat),
      > 0 => (l.vsLastMonthMore(f.integer(change)), colors.expense, Icons.trending_up),
      _ => (l.vsLastMonthLess(f.integer(-change)), colors.income, Icons.trending_down),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}

/// Category breakdown: donut + rows with share bars. Tapping an expense
/// category opens its subcategory breakdown (§11.4).
class CategoryBreakdown extends ConsumerWidget {
  const CategoryBreakdown({super.key, required this.range, required this.type, this.limit});

  final DateRange range;
  final CategoryType type;

  /// Show only the largest N rows (dashboard).
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final rowsAsync = ref.watch(categoryExpenseProvider(range, type));
    return rowsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 120, child: LoadingState()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(categoryExpenseProvider(range, type))),
      data: (rows) {
        final positive = rows.where((r) => r.amount.isPositive).toList();
        if (positive.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.periodEmpty, textAlign: TextAlign.center),
          );
        }
        final shown = limit == null ? positive : positive.take(limit!).toList();
        return Column(
          children: [
            if (limit == null) ...[
              CategoryDonut(slices: positive, total: Money.sum(positive.map((r) => r.amount))),
              const SizedBox(height: 12),
            ],
            for (final r in shown)
              CategoryAmountRow(
                row: r,
                onTap: type == CategoryType.expense && r.category != null
                    ? () => showCategoryDrillDown(context, range: range, category: r.category!)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class CategoryAmountRow extends ConsumerWidget {
  const CategoryAmountRow({super.key, required this.row, this.onTap});

  final CategoryAmount row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final f = ref.watch(appFormatsProvider);
    final c = row.category;
    final color = Color(c?.color ?? 0xFF9E9E9E);
    final name = row.withoutSubcategory
        ? l.withoutSubcategory
        : c?.displayName(lang) ?? l.deletedCategory;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CategoryAvatar(iconKey: c?.iconKey ?? 'label', color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(f.money.format(row.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: row.percent / 100,
                            minHeight: 6,
                            color: color,
                            backgroundColor: color.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text('${f.integer(row.percent)}%',
                            textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall),
                      ),
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

/// Subcategory breakdown of one category, with a shortcut to the matching
/// transactions in History.
Future<void> showCategoryDrillDown(
  BuildContext context, {
  required DateRange range,
  required Category category,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _DrillDown(range: range, category: category),
);

class _DrillDown extends ConsumerWidget {
  const _DrillDown({required this.range, required this.category});

  final DateRange range;
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final rows = ref.watch(subcategoryExpenseProvider(range, category.id)).value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(category.displayName(lang), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (rows == null)
              const SizedBox(height: 80, child: LoadingState())
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final r in rows.where((r) => r.amount.isPositive)) CategoryAmountRow(row: r)],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.receipt_long),
              label: Text(l.viewTransactions),
              onPressed: () {
                ref.read(transactionFilterProvider.notifier)
                    .set(HistoryFilter(categoryId: category.id, range: range));
                Navigator.of(context).pop();
                context.go(Routes.history);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Personal vs Family income and expense (Combined overview, §3.3).
class WorkspaceSplitCard extends ConsumerWidget {
  const WorkspaceSplitCard({super.key, required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final split = ref.watch(workspaceSplitProvider(range)).value;
    if (split == null) return const SizedBox.shrink();
    return SectionCard(
      title: l.workspaceSplitTitle,
      child: Column(
        children: [
          for (final s in split)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(workspaceTypeLabel(l, s.type))),
                  Text(f.money.format(s.income, signed: true), style: TextStyle(color: colors.income)),
                  const SizedBox(width: 16),
                  Text(f.money.format(-s.expense), style: TextStyle(color: colors.expense)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
