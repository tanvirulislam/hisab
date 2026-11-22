import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../../app/theme/app_colors.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/presentation/budget_providers.dart';
import '../../budgets/presentation/widgets/budget_widgets.dart';
import '../../categories/domain/category.dart';
import '../../reports/presentation/report_providers.dart';
import '../../reports/presentation/widgets/report_charts.dart';
import '../../reports/presentation/widgets/report_sections.dart';
import '../../settings/presentation/app_formats.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../transactions/presentation/entry_form_screen.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';

/// Home dashboard (§5). Every figure is computed live from stored
/// transactions for the active scope.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final balances = ref.watch(accountBalanceProvider);
    return ScopedPage(
      title: l10n.appTitle,
      body: AsyncValueView(
        value: balances,
        onRetry: () => ref.invalidate(accountBalanceProvider),
        data: (accounts) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(total: Money.sum(accounts.map((a) => a.balance))),
            const SizedBox(height: 12),
            const _MonthSummary(),
            const SizedBox(height: 12),
            const _BudgetSummary(),
            const _QuickActions(),
            const SizedBox(height: 12),
            const _MonthOverview(),
            const SizedBox(height: 8),
            const _RecentTransactions(),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? 0.4 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(height: 6),
                    Text(label, style: Theme.of(context).textTheme.labelMedium, maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        action(Icons.north_east, l.quickExpense,
            () => context.push(Routes.addOfType(EntryMode.expense.name))),
        action(Icons.south_west, l.quickIncome,
            () => context.push(Routes.addOfType(EntryMode.income.name))),
        action(Icons.swap_horiz, l.quickTransfer,
            () => context.push(Routes.addOfType(EntryMode.transfer.name))),
        action(Icons.mic_none, l.quickVoice, () => context.push(Routes.voice)),
      ],
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final recent = ref.watch(recentTransactionsProvider);
    return recent.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 120, child: LoadingState()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(recentTransactionsProvider)),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 32),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l.homeEmptyTitle,
              message: l.homeEmptyMessage,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.recentTransactions,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: () => context.go(Routes.history), child: Text(l.seeAll)),
              ],
            ),
            Card(
              child: Column(
                children: [
                  for (final item in items)
                    TransactionTile(
                      item: item,
                      onTap: () => context.push(Routes.transaction(item.entry.id)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.total});

  final Money total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fmt = ref.watch(moneyFormatterProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.accountsTotalBalance,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            fmt.format(total),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// This month's income, expense and savings, plus today's expense (§5.1).
class _MonthSummary extends ConsumerWidget {
  const _MonthSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final month = ref.watch(monthlySummaryProvider).value;
    final today = ref.watch(dailySummaryProvider).value;
    if (month == null || today == null) return const SizedBox(height: 140, child: LoadingState());
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                  icon: Icons.south_west, label: l.monthIncome,
                  value: f.money.format(month.income), color: colors.income),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                  icon: Icons.north_east, label: l.monthExpense,
                  value: f.money.format(month.expense), color: colors.expense),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.savings_outlined,
                label: l.monthNet,
                value: f.money.format(month.net),
                color: month.net.isNegative ? colors.expense : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                  icon: Icons.today, label: l.todayExpense, value: f.money.format(today.expense)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Daily spending chart and top categories.
class _MonthOverview extends ConsumerWidget {
  const _MonthOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final range = ref.watch(currentMonthRangeProvider);
    final days = ref.watch(dailySeriesProvider(range)).value;
    final month = ref.watch(monthlySummaryProvider).value;
    if (month == null || month.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: l.dailySpending,
          child: days == null ? const SizedBox(height: 180, child: LoadingState()) : DailyBarChart(days: days),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l.topCategories,
          trailing: TextButton(onPressed: () => context.go(Routes.reports), child: Text(l.openReports)),
          child: CategoryBreakdown(range: range, type: CategoryType.expense, limit: 5),
        ),
      ],
    );
  }
}

/// Remaining budget for this month and the three most used budgets
/// (§5.1 Remaining Budget, §5.2 budget utilization summary). Until a budget
/// is set, only a one-line prompt is shown.
class _BudgetSummary extends ConsumerWidget {
  const _BudgetSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final statuses = ref.watch(currentBudgetStatusesProvider).value;
    if (statuses == null) return const SizedBox.shrink();
    if (statuses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: Text(l.budgetsSetPrompt),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.budgets),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BudgetTotalsCard(
            totals: BudgetTotals(statuses),
            title: l.budgetRemainingThisMonth,
            trailing: TextButton(onPressed: () => context.push(Routes.budgets), child: Text(l.seeAll)),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final s in statuses.take(3))
                  BudgetTile(status: s, onTap: () => context.push(Routes.budgets)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
