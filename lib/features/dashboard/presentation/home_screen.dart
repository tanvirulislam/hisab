import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../transactions/presentation/entry_form_screen.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../transactions/presentation/widgets/transaction_tile.dart';
import '../../workspaces/domain/workspace.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';
import '../../workspaces/presentation/workspace_providers.dart';

/// Home dashboard. Shows the live total balance, quick actions and recent
/// transactions. Monthly summary cards and charts come in Phase 3.
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
            const SizedBox(height: 16),
            const _QuickActions(),
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
        // Voice entry arrives in Phase 4.
        action(Icons.mic_none, l.quickVoice, null),
      ],
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final combined = ref.watch(activeWorkspaceScopeProvider) == WorkspaceScope.combined;
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
                      showWorkspace: combined,
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
