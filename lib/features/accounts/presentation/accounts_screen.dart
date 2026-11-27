import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/add_action.dart';
import '../../../app/routes.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/account.dart';
import 'account_edit_sheet.dart';
import 'account_providers.dart';

/// Accounts with live balances.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = ref.watch(moneyFormatterProvider);
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    // The tab bar's Add button adds an account here (D21).
    return AddAction(
      path: Routes.accounts,
      onAdd: () {
        final ws = workspaces.firstOrNull;
        if (ws != null) showAccountEditSheet(context, workspaceId: ws.id);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.moreAccounts)),
        body: AsyncValueView(
          value: ref.watch(accountBalanceProvider),
          onRetry: () => ref.invalidate(accountBalanceProvider),
          data: (accounts) {
            if (accounts.isEmpty) {
              return EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.accountsEmpty,
              );
            }
            return ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                for (final a in accounts)
                  ListTile(
                    onTap: () =>
                        showAccountEditSheet(context, existing: a.account),
                    leading: CategoryAvatar(
                      iconKey: accountIconKey(a.account.type),
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: Text(a.account.name),
                    subtitle: Text(
                      a.account.isActive
                          ? accountTypeLabel(l10n, a.account.type)
                          : '${accountTypeLabel(l10n, a.account.type)} · ${l10n.accountInactive}',
                    ),
                    trailing: Text(
                      fmt.format(a.balance),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String accountTypeLabel(AppLocalizations l10n, AccountType type) =>
    switch (type) {
      AccountType.cash => l10n.accountTypeCash,
      AccountType.bank => l10n.accountTypeBank,
      AccountType.bkash => l10n.accountTypeBkash,
      AccountType.nagad => l10n.accountTypeNagad,
      AccountType.savings => l10n.accountTypeSavings,
      AccountType.other => l10n.accountTypeOther,
    };

String accountIconKey(AccountType type) => switch (type) {
  AccountType.cash => 'payments',
  AccountType.bank => 'account_balance',
  AccountType.bkash || AccountType.nagad => 'phone_iphone',
  AccountType.savings => 'savings',
  AccountType.other => 'account_balance_wallet',
};
