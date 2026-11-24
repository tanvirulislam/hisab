import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../../app/theme/app_colors.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/savings.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/presentation/budget_providers.dart';
import '../../budgets/presentation/widgets/budget_widgets.dart';
import '../../categories/domain/category.dart';
import '../../reports/presentation/report_providers.dart';
import '../../reports/presentation/widgets/report_charts.dart';
import '../../reports/presentation/widgets/report_sections.dart';
import '../../loans/presentation/loan_providers.dart';
import '../../loans/presentation/loans_screen.dart';
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
          // The cards above load their own data and change height while they
          // load. A lazy ListView drops them once scrolled far away and
          // rebuilds them in the loading state on the way back, so the content
          // above the viewport resizes and the scroll position jumps. Home is
          // short, so keep every child built.
          scrollCacheExtent: const ScrollCacheExtent.pixels(20000),
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(
              total: Money.sum(accounts.map((a) => a.balance)),
              savings: accounts.any((a) => a.account.type == AccountType.savings)
                  ? Savings.total(accounts)
                  : null,
            ),
            const _LoanCard(),
            const SizedBox(height: 12),
            const _MonthSummary(),
            const SizedBox(height: 12),
            _SavingsCard(accounts: accounts),
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
  const _BalanceCard({required this.total, this.savings});

  final Money total;

  /// Part of [total] sitting in savings accounts; null when there are none.
  final Money? savings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fmt = ref.watch(moneyFormatterProvider);
    final scheme = theme.colorScheme;
    // Outlined, not filled: the same surface as the other cards with a faint
    // green edge, so the balance stands out without shouting.
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.accountsTotalBalance,
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            fmt.format(total),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (savings != null) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.savingsIncludedInTotal(fmt.format(savings!)),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Savings (D17): what was moved this month, and one tap to send what is left
/// of the month to a savings account. Moving money is an ordinary transfer, so
/// it is neither income nor expense. Without a savings account it only
/// suggests creating one.
class _SavingsCard extends ConsumerWidget {
  const _SavingsCard({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final theme = Theme.of(context);
    final target = Savings.target(accounts);
    final month = ref.watch(monthlySummaryProvider).value;
    final moved = ref.watch(savingsMovedThisMonthProvider).value;

    Widget card({required List<Widget> children}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.savings_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l.savingsCardTitle,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );

    if (target == null) {
      // Nothing to offer until the first month figures are known.
      if (month == null || month.isEmpty) return const SizedBox.shrink();
      return card(children: [
        Text(l.savingsSetupHint, style: theme.textTheme.bodyMedium),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => context.push(Routes.accounts),
            child: Text(l.savingsSetupAction),
          ),
        ),
      ]);
    }
    if (month == null || moved == null) return const SizedBox(height: 12);
    final remaining = Savings.remaining(
      net: month.net,
      moved: moved,
      spendable: Savings.spendable(accounts),
    );
    final from = Savings.source(accounts);
    return card(children: [
      Row(
        children: [
          Expanded(child: Text(l.savingsMovedThisMonth, style: theme.textTheme.bodyMedium)),
          Text(f.money.format(moved),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
      if (remaining.isPositive)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => context.push(Routes.addTransfer(
                to: target.id,
                from: from?.id,
                amountPaisa: remaining.paisa,
              )),
              icon: const Icon(Icons.savings_outlined),
              label: Text(l.savingsSendRemaining(f.money.format(remaining))),
            ),
          ),
        ),
    ]);
  }
}

/// What is still owed to you / by you. Shown only while something is open;
/// loans are not income or expense, so they stay out of the month figures.
class _LoanCard extends ConsumerWidget {
  const _LoanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(loanTotalsProvider);
    if (!totals.owedToMe.isPositive && !totals.iOwe.isPositive) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LoanTotalsRow(onTap: () => context.push(Routes.loans)),
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
    final moved = ref.watch(savingsMovedThisMonthProvider).value;
    if (month == null || today == null || moved == null) {
      return const SizedBox(height: 140, child: LoadingState());
    }
    // Income − expense, less what was already moved to savings (D17), so this
    // matches the amount the savings card offers to send.
    final left = Savings.leftThisMonth(net: month.net, moved: moved);
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
                value: f.money.format(left),
                color: left.isNegative ? colors.expense : Theme.of(context).colorScheme.primary,
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

/// Top spending categories this month. The daily chart lives only in
/// Reports (owner request 2026-11-22: no duplicate on Home).
class _MonthOverview extends ConsumerWidget {
  const _MonthOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final range = ref.watch(currentMonthRangeProvider);
    final month = ref.watch(monthlySummaryProvider).value;
    if (month == null || month.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: l.topCategories,
      trailing: TextButton(onPressed: () => context.go(Routes.reports), child: Text(l.openReports)),
      // Not budget use (that is the budget card above): share of the month's spending.
      subtitle: l.topCategoriesHint,
      child: CategoryBreakdown(range: range, type: CategoryType.expense, limit: 5),
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
