import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/services/local_prefs.dart';
import '../../workspaces/domain/workspace.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_transaction_repository.dart';
import '../domain/drafts.dart';
import '../domain/history_filter.dart';
import '../domain/history_grouping.dart';
import '../domain/ledger_entry.dart';
import '../domain/transaction_repository.dart';

part 'transaction_providers.g.dart';

const int historyPageSize = 50;

@Riverpod(keepAlive: true)
TransactionRepository transactionRepository(Ref ref) =>
    DriftTransactionRepository(ref.watch(appDatabaseProvider));

// ------------------------------------------------------------------ history

@Riverpod(keepAlive: true)
class TransactionFilter extends _$TransactionFilter {
  @override
  HistoryFilter build() => const HistoryFilter();

  void set(HistoryFilter filter) => state = filter;

  void setSearch(String text) => state = state.copyWith(search: text);

  void clearFilters() => state = HistoryFilter(search: state.search);
}

/// How many rows the history shows. Resets when the scope or filter changes.
@Riverpod(keepAlive: true)
class HistoryLimit extends _$HistoryLimit {
  @override
  int build() {
    ref.watch(activeWorkspaceIdsProvider);
    ref.watch(transactionFilterProvider);
    return historyPageSize;
  }

  void loadMore() => state = state + historyPageSize;
}

@Riverpod(keepAlive: true)
Stream<HistoryPage> transactionList(Ref ref) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  final filter = ref.watch(transactionFilterProvider);
  final limit = ref.watch(historyLimitProvider);
  yield* ref
      .watch(transactionRepositoryProvider)
      .watchHistory(HistoryQuery(workspaceIds: ids, filter: filter, limit: limit));
}

class HistoryView {
  const HistoryView({required this.sections, required this.hasMore});

  final List<DaySection> sections;
  final bool hasMore;

  bool get isEmpty => sections.isEmpty;
}

/// Day-grouped history. Grouping happens here, not in a build method.
@Riverpod(keepAlive: true)
AsyncValue<HistoryView> historyView(Ref ref) => ref
    .watch(transactionListProvider)
    .whenData((page) => HistoryView(sections: groupByDay(page.items), hasMore: page.hasMore));

/// The newest few transactions in the active scope (Home).
@riverpod
Stream<List<HistoryItem>> recentTransactions(Ref ref) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref
      .watch(transactionRepositoryProvider)
      .watchHistory(HistoryQuery(workspaceIds: ids, limit: 5))
      .map((p) => p.items.take(5).toList());
}

@riverpod
Stream<HistoryItem?> transactionItem(Ref ref, String id) =>
    ref.watch(transactionRepositoryProvider).watchItem(id);

@riverpod
Stream<List<HistoryItem>> refundsOf(Ref ref, String expenseId) =>
    ref.watch(transactionRepositoryProvider).watchRefundsOf(expenseId);

@riverpod
Stream<List<RecentTemplate>> recentTemplates(Ref ref, String workspaceId) =>
    ref.watch(transactionRepositoryProvider).watchRecentTemplates([workspaceId]);

// ----------------------------------------------------------- entry defaults

/// Remembers the last workspace and, per workspace, the last account used,
/// so the entry form opens ready to save (§8.1). Device-local (D10).
class EntryDefaults {
  EntryDefaults(this._prefs);

  final LocalPrefs _prefs;

  Map<String, String> get _lastAccounts {
    final raw = _prefs.getString(LocalPrefKeys.lastAccountId);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } on Object {
      return {};
    }
  }

  String? lastAccountFor(String workspaceId) => _lastAccounts[workspaceId];

  String? get lastWorkspaceId => _prefs.getString(LocalPrefKeys.lastEntryWorkspaceId);

  /// Workspace for a new entry: the active scope when it is a single
  /// workspace, otherwise the last one used, otherwise Personal.
  String? defaultWorkspaceId(WorkspaceScope scope, List<Workspace> workspaces) {
    if (workspaces.isEmpty) return null;
    if (scope != WorkspaceScope.combined) {
      final match = workspaces.where((w) => scope.includes(w.type));
      if (match.isNotEmpty) return match.first.id;
    }
    final last = lastWorkspaceId;
    if (last != null && workspaces.any((w) => w.id == last)) return last;
    return workspaces.first.id;
  }

  Future<void> remember({required String workspaceId, required String accountId}) async {
    final map = _lastAccounts..[workspaceId] = accountId;
    await _prefs.setString(LocalPrefKeys.lastAccountId, jsonEncode(map));
    await _prefs.setString(LocalPrefKeys.lastEntryWorkspaceId, workspaceId);
  }
}

@Riverpod(keepAlive: true)
EntryDefaults entryDefaults(Ref ref) => EntryDefaults(ref.watch(localPrefsProvider));

// ----------------------------------------------------------------- commands

/// Write commands for the entry, refund and delete flows. Validation lives
/// in the repository. This guards against double submission (§21) and
/// remembers the last-used defaults.
@riverpod
class AddTransaction extends _$AddTransaction {
  @override
  FutureOr<void> build() {}

  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false; // duplicate tap while saving
    state = const AsyncLoading();
    try {
      await action();
      if (!ref.mounted) return true;
      state = const AsyncData(null);
      return true;
    } on AppException catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> saveEntry(EntryDraft draft, {String? editId}) => _run(() async {
    final repo = ref.read(transactionRepositoryProvider);
    if (editId == null) {
      await repo.createEntry(draft);
    } else {
      await repo.updateEntry(editId, draft);
    }
    await ref.read(entryDefaultsProvider).remember(
        workspaceId: draft.workspaceId, accountId: draft.accountId);
  });

  Future<bool> saveTransfer(TransferDraft draft, {String? groupId}) => _run(() async {
    final repo = ref.read(transactionRepositoryProvider);
    if (groupId == null) {
      await repo.createTransfer(draft);
    } else {
      await repo.updateTransfer(groupId, draft);
    }
  });

  Future<bool> saveRefund(RefundDraft draft, {String? editId}) => _run(() async {
    final repo = ref.read(transactionRepositoryProvider);
    if (editId == null) {
      await repo.createRefund(draft);
    } else {
      await repo.updateRefund(editId, draft);
    }
  });
}
