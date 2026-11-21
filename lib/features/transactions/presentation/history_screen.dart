import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../workspaces/domain/workspace.dart';
import '../domain/history_filter.dart';
import '../../workspaces/presentation/widgets/scoped_page.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import 'history_filter_sheet.dart';
import 'transaction_providers.dart';
import 'widgets/transaction_tile.dart';

/// Date-grouped transaction history with search and filters (§10).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final _search = TextEditingController(text: ref.read(transactionFilterProvider).search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300),
        () => ref.read(transactionFilterProvider.notifier).setSearch(text));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final filter = ref.watch(transactionFilterProvider);
    final combined = ref.watch(activeWorkspaceScopeProvider) == WorkspaceScope.combined;
    return ScopedPage(
      title: l.navHistory,
      actions: [
        IconButton(
          tooltip: l.filters,
          onPressed: () => showHistoryFilterSheet(context),
          icon: Badge(
            isLabelVisible: filter.hasFilters,
            smallSize: 8,
            child: const Icon(Icons.tune),
          ),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchBar(
              controller: _search,
              hintText: l.searchHint,
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: _onSearch,
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      _onSearch('');
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: ref.watch(historyViewProvider),
              onRetry: () => ref.invalidate(transactionListProvider),
              data: (view) {
                if (view.isEmpty) {
                  return filter.isEmpty
                      ? EmptyState(
                          icon: Icons.history,
                          title: l.historyEmptyTitle,
                          message: l.historyEmptyMessage,
                        )
                      : EmptyState(
                          icon: Icons.search_off,
                          title: l.historyNoResults,
                          action: TextButton(
                            onPressed: () {
                              _search.clear();
                              ref.read(transactionFilterProvider.notifier).set(const HistoryFilter());
                            },
                            child: Text(l.clearFilters),
                          ),
                        );
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (view.hasMore && n.metrics.extentAfter < 400) {
                      ref.read(historyLimitProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      for (final section in view.sections) ...[
                        SliverToBoxAdapter(
                          child: DayHeader(
                            date: section.date,
                            expense: section.totals.expense,
                            income: section.totals.income,
                          ),
                        ),
                        SliverList.builder(
                          itemCount: section.items.length,
                          itemBuilder: (context, i) {
                            final item = section.items[i];
                            return TransactionTile(
                              item: item,
                              showWorkspace: combined,
                              onTap: () => context.push(Routes.transaction(item.entry.id)),
                            );
                          },
                        ),
                      ],
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: view.hasMore
                              ? Center(
                                  child: TextButton(
                                    onPressed: () => ref.read(historyLimitProvider.notifier).loadMore(),
                                    child: Text(l.loadMore),
                                  ),
                                )
                              : const SizedBox(height: 56),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
