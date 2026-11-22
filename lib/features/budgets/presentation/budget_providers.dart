import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/providers.dart';
import '../../../core/services/today_provider.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_budget_repository.dart';
import '../domain/budget.dart';
import '../domain/budget_repository.dart';

part 'budget_providers.g.dart';

@Riverpod(keepAlive: true)
BudgetRepository budgetRepository(Ref ref) => DriftBudgetRepository(ref.watch(appDatabaseProvider));

/// The month shown on the Budgets screen: the key (first of the start
/// month) of a month cycle, D15.
@riverpod
class BudgetMonth extends _$BudgetMonth {
  @override
  LocalDate build() => ref.watch(monthCycleProvider).keyOf(ref.currentDate());

  void shift(int months) => state = state.addMonths(months);
}

/// Budgets of [month] in the active scope.
@riverpod
Stream<List<BudgetStatus>> budgetStatuses(Ref ref, LocalDate month) async* {
  final cycle = ref.watch(monthCycleProvider);
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(budgetRepositoryProvider).watchStatuses(ids, month.year, month.month, cycle: cycle);
}

/// This month's budgets in the active scope (dashboard).
@riverpod
Stream<List<BudgetStatus>> currentBudgetStatuses(Ref ref) async* {
  final cycle = ref.watch(monthCycleProvider);
  final key = cycle.keyOf(ref.currentDate());
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(budgetRepositoryProvider).watchStatuses(ids, key.year, key.month, cycle: cycle);
}

/// This month's budgets in every workspace, whatever scope is shown, so
/// alerts fire for Family spending while Personal is open (§12.1).
@Riverpod(keepAlive: true)
Stream<List<BudgetStatus>> allCurrentBudgetStatuses(Ref ref) async* {
  final cycle = ref.watch(monthCycleProvider);
  final key = cycle.keyOf(ref.currentDate());
  final workspaces = await ref.watch(workspacesProvider.future);
  yield* ref
      .watch(budgetRepositoryProvider)
      .watchStatuses([for (final w in workspaces) w.id], key.year, key.month, cycle: cycle);
}

/// Budget write commands. Validation lives in the repository.
// Kept alive: a list tile starts a command and reads its error afterwards,
// with nothing watching the controller in between.
@Riverpod(keepAlive: true)
class BudgetController extends _$BudgetController {
  @override
  FutureOr<void> build() {}

  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await action();
      if (ref.mounted) state = const AsyncData(null);
      return true;
    } on AppException catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> create(BudgetDraft draft) => _run(() async {
    await ref.read(budgetRepositoryProvider).create(draft);
    // Ask for notification permission when it starts to matter, not at launch.
    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
    if (settings.budgetAlerts) await ref.read(notificationServiceProvider).requestPermission();
  });

  Future<bool> edit(String id, Money amount, int threshold) =>
      _run(() => ref.read(budgetRepositoryProvider).update(id, amount: amount, warningThreshold: threshold));

  Future<bool> delete(String id) => _run(() => ref.read(budgetRepositoryProvider).delete(id));

  /// Returns how many budgets were copied, or null on failure.
  Future<int?> copyPrevious(String workspaceId, LocalDate month) async {
    var copied = 0;
    final ok = await _run(() async {
      copied = await ref.read(budgetRepositoryProvider).copyFromPreviousMonth(workspaceId, month.year, month.month);
    });
    return ok ? copied : null;
  }
}
