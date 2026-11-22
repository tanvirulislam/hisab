import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/bn_digits.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../settings/presentation/app_formats.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../domain/budget.dart';
import 'budget_edit_sheet.dart';
import 'budget_providers.dart';
import 'widgets/budget_widgets.dart';

/// Monthly budgets for the active scope (§12): allocated, spent, remaining
/// and utilization per category.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final month = ref.watch(budgetMonthProvider);
    final single = ref.watch(workspacesProvider).value?.firstOrNull;
    final statuses = ref.watch(budgetStatusesProvider(month));

    void add() {
      if (single == null) return;
      final budgeted = {for (final s in statuses.value ?? const <BudgetStatus>[]) s.category.id};
      showBudgetEditSheet(context, workspaceId: single.id, month: month, budgeted: budgeted);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.moreBudgets),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: Text(l.budgetAdd),
      ),
      body: Column(
        children: [
          _MonthNavigator(month: month),
          Expanded(
            child: AsyncValueView(
              value: statuses,
              onRetry: () => ref.invalidate(budgetStatusesProvider(month)),
              data: (list) => list.isEmpty
                  ? _Empty(month: month, workspaceId: single?.id)
                  : _BudgetList(statuses: list, month: month),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthNavigator extends ConsumerWidget {
  const _MonthNavigator({required this.month});

  final LocalDate month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final digits = f.banglaDigits ? BnDigits.toBangla : BnDigits.toLatin;
    final notifier = ref.read(budgetMonthProvider.notifier);
    // Budgets can be planned one month ahead.
    final canGoNext = month.isBefore(f.today.firstOfMonth.addMonths(1));
    return Row(
      children: [
        IconButton(tooltip: l.previousPeriod, icon: const Icon(Icons.chevron_left), onPressed: () => notifier.shift(-1)),
        Expanded(
          child: Text(
            digits(DateFormat.yMMMM(f.languageCode).format(month.toDateTime())),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: l.nextPeriod,
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoNext ? () => notifier.shift(1) : null,
        ),
      ],
    );
  }
}

class _BudgetList extends StatelessWidget {
  const _BudgetList({required this.statuses, required this.month});

  final List<BudgetStatus> statuses;
  final LocalDate month;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    children: [
      BudgetTotalsCard(totals: BudgetTotals(statuses)),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final s in statuses)
              BudgetTile(
                status: s,
                onTap: () => showBudgetEditSheet(context, workspaceId: s.budget.workspaceId, month: month, existing: s),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.month, required this.workspaceId});

  final LocalDate month;

  /// NULL until the workspace has loaded.
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final saving = ref.watch(budgetControllerProvider).isLoading;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 96),
      children: [
        EmptyState(icon: Icons.savings_outlined, title: l.budgetsEmptyTitle, message: l.budgetsEmptyMessage),
        if (workspaceId != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.content_copy),
              label: Text(l.budgetsCopyPrevious),
              onPressed: saving
                  ? null
                  : () async {
                      final n = await ref.read(budgetControllerProvider.notifier).copyPrevious(workspaceId!, month);
                      if (!context.mounted) return;
                      final f = ref.read(appFormatsProvider);
                      showSnack(context, switch (n) {
                        null => l.errorMessage,
                        0 => l.budgetsNothingToCopy,
                        _ => l.budgetsCopied(f.integer(n)),
                      });
                    },
            ),
          ),
        ],
      ],
    );
  }
}
