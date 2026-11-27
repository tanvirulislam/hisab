import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../l10n/l10n.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = <_MoreItem>[
      _MoreItem(Icons.savings_outlined, l10n.moreBudgets, Routes.budgets),
      _MoreItem(Icons.category_outlined, l10n.moreCategories, Routes.categories),
      _MoreItem(Icons.account_balance_wallet_outlined, l10n.moreAccounts, Routes.accounts),
      _MoreItem(Icons.handshake_outlined, l10n.moreLoans, Routes.loans),
      _MoreItem(Icons.settings_outlined, l10n.moreSettings, Routes.settings),
      _MoreItem(Icons.backup_outlined, l10n.moreBackup, Routes.backup),
      _MoreItem(Icons.info_outline, l10n.moreAbout, Routes.about),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMore)),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final item = items[i];
          final enabled = item.route != null;
          return ListTile(
            enabled: enabled,
            leading: Icon(item.icon),
            title: Text(item.label),
            subtitle: enabled ? null : Text(l10n.comingSoon),
            trailing: enabled ? const Icon(Icons.chevron_right) : null,
            onTap: enabled ? () => context.push(item.route!) : null,
          );
        },
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.icon, this.label, this.route);

  final IconData icon;
  final String label;

  /// NULL while the feature is not built yet.
  final String? route;
}
