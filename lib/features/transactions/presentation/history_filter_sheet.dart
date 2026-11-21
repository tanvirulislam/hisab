import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/local_date.dart';
import '../../../l10n/l10n.dart';
import '../../accounts/presentation/account_providers.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_providers.dart';
import '../../settings/presentation/app_formats.dart';
import '../domain/history_filter.dart';
import 'transaction_providers.dart';

Future<void> showHistoryFilterSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _FilterSheet(),
);

/// Type, category, subcategory, account and date-range filters (§10.2).
/// Changes apply when the user taps Apply.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late HistoryFilter _f = ref.read(transactionFilterProvider);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final fmt = ref.watch(appFormatsProvider);
    final expenseTree = ref.watch(categoryTreeProvider(CategoryType.expense)).value ?? const [];
    final incomeTree = ref.watch(categoryTreeProvider(CategoryType.income)).value ?? const [];
    final accounts = ref.watch(accountBalanceProvider).value ?? const [];
    final tree = [...expenseTree, ...incomeTree];
    final selectedNode = tree.where((n) => n.category.id == _f.categoryId).firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.filters, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(l.fieldType, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (t, label) in [
                  (HistoryTypeFilter.expense, l.entryExpense),
                  (HistoryTypeFilter.income, l.entryIncome),
                  (HistoryTypeFilter.transfer, l.entryTransfer),
                ])
                  FilterChip(
                    label: Text(label),
                    selected: _f.types.contains(t),
                    onSelected: (on) => setState(() {
                      final types = {..._f.types};
                      on ? types.add(t) : types.remove(t);
                      _f = _f.copyWith(types: types);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: selectedNode?.category.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.fieldCategory, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: null, child: Text(l.filterAnyCategory)),
                for (final n in tree)
                  DropdownMenuItem(value: n.category.id, child: Text(n.category.displayName(lang))),
              ],
              onChanged: (v) => setState(() => _f = _f.copyWith(categoryId: v, subcategoryId: null)),
            ),
            if (selectedNode != null && selectedNode.children.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(selectedNode.category.id),
                initialValue: _f.subcategoryId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.fieldSubcategory, border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.filterAnySubcategory)),
                  for (final c in selectedNode.children)
                    DropdownMenuItem(value: c.id, child: Text(c.displayName(lang))),
                ],
                onChanged: (v) => setState(() => _f = _f.copyWith(subcategoryId: v)),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: accounts.any((a) => a.account.id == _f.accountId) ? _f.accountId : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.fieldAccount, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: null, child: Text(l.filterAnyAccount)),
                for (final a in accounts)
                  DropdownMenuItem(value: a.account.id, child: Text(a.account.name)),
              ],
              onChanged: (v) => setState(() => _f = _f.copyWith(accountId: v)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(_f.range == null
                  ? l.filterAnyDate
                  : '${fmt.date(_f.range!.start)} – ${fmt.date(_f.range!.end)}'),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(fmt.today.year + 1, 12, 31),
                  initialDateRange: _f.range == null
                      ? null
                      : DateTimeRange(start: _f.range!.start.toDateTime(), end: _f.range!.end.toDateTime()),
                );
                if (picked != null) {
                  setState(() => _f = _f.copyWith(
                        range: DateRange(LocalDate.fromDateTime(picked.start), LocalDate.fromDateTime(picked.end)),
                      ));
                }
              },
            ),
            if (_f.range != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _f = _f.copyWith(range: null)),
                  child: Text(l.filterAnyDate),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(transactionFilterProvider.notifier).clearFilters();
                      Navigator.of(context).pop();
                    },
                    child: Text(l.clearFilters),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      // Keep the search text typed in the history screen.
                      ref.read(transactionFilterProvider.notifier)
                          .set(_f.copyWith(search: ref.read(transactionFilterProvider).search));
                      Navigator.of(context).pop();
                    },
                    child: Text(l.applyFilters),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
