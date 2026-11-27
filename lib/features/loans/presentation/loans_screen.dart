import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/add_action.dart';
import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/loan.dart';
import 'loan_entry_sheet.dart';
import 'loan_providers.dart';

/// Everyone you lent money to or borrowed from, with what is still open.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    // The tab bar's Add button adds a loan entry here (D21).
    return AddAction(
      path: Routes.loans,
      onAdd: () {
        final ws = workspaces.firstOrNull;
        if (ws != null) showLoanEntrySheet(context, workspaceId: ws.id);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.moreLoans)),
        body: AsyncValueView(
          value: ref.watch(loanSummariesProvider),
          onRetry: () => ref.invalidate(loanSummariesProvider),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.handshake_outlined,
                title: l.loansEmpty,
                message: l.loansEmptyHint,
              );
            }
            final open = [for (final s in list) if (!s.isSettled) s];
            final settled = [for (final s in list) if (s.isSettled) s];
            return ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: LoanTotalsRow(),
                ),
                for (final s in open) _PersonTile(summary: s),
                if (settled.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      l.loansSettledSection,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final s in settled) _PersonTile(summary: s),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "You will get" and "You owe" totals side by side.
class LoanTotalsRow extends ConsumerWidget {
  const LoanTotalsRow({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final fmt = ref.watch(appFormatsProvider).money;
    final totals = ref.watch(loanTotalsProvider);
    final colors = context.financeColors;
    Widget cell(String label, String value, Color color) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            cell(l.loansOwedToMe, fmt.format(totals.owedToMe), colors.income),
            cell(l.loansIOwe, fmt.format(totals.iOwe), colors.expense),
          ],
        ),
      ),
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.summary});

  final PersonLoanSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final colors = context.financeColors;
    final theme = Theme.of(context);
    final p = summary.person;
    final last = summary.lastDate;
    return ListTile(
      onTap: () => context.push(Routes.loanPerson(p.id)),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Text(p.name.characters.first.toUpperCase()),
      ),
      title: Text(p.name),
      subtitle: last == null ? null : Text(f.date(last)),
      trailing: summary.isSettled
          ? Text(l.loanSettled, style: theme.textTheme.labelMedium)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (summary.owedToMe.isPositive)
                  Text(
                    l.loanOwesYou(f.money.format(summary.owedToMe)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.income,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (summary.iOwe.isPositive)
                  Text(
                    l.loanYouOwe(f.money.format(summary.iOwe)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
    );
  }
}
