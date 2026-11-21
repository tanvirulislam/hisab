import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';

/// Home dashboard. Phase 1 shows the live total balance for the active
/// scope. Summary cards, charts and recent transactions come in Phase 3.
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
            const SizedBox(height: 48),
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.homeEmptyTitle,
              message: l10n.homeEmptyMessage,
            ),
          ],
        ),
      ),
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
