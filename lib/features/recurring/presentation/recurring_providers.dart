import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_maintenance.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/providers.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_recurring_repository.dart';
import '../domain/recurring_repository.dart';
import '../domain/recurring_rule.dart';

part 'recurring_providers.g.dart';

@Riverpod(keepAlive: true)
RecurringRepository recurringRepository(Ref ref) =>
    DriftRecurringRepository(ref.watch(appDatabaseProvider), ref.watch(transactionRepositoryProvider));

/// Rules in the active scope.
@riverpod
Stream<List<RecurringRuleItem>> recurringRules(Ref ref) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(recurringRepositoryProvider).watchRules(ids);
}

/// Rules in every workspace (upcoming-payment notifications).
@Riverpod(keepAlive: true)
Stream<List<RecurringRuleItem>> allRecurringRules(Ref ref) async* {
  final workspaces = await ref.watch(workspacesProvider.future);
  yield* ref.watch(recurringRepositoryProvider).watchRules([for (final w in workspaces) w.id]);
}

@riverpod
Stream<RecurringRule?> recurringRule(Ref ref, String id) =>
    ref.watch(recurringRepositoryProvider).watchRule(id);

/// Rule write commands. After a change the generator runs, so a rule due
/// today records its transaction straight away.
// Kept alive: a list tile starts a command and reads its error afterwards,
// with nothing watching the controller in between.
@Riverpod(keepAlive: true)
class RecurringController extends _$RecurringController {
  @override
  FutureOr<void> build() {}

  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    try {
      await action();
      await ref.read(appMaintenanceProvider).run();
      if (ref.mounted) state = const AsyncData(null);
      return true;
    } on AppException catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> save(RecurringDraft draft, {String? id}) => _run(() async {
    final repo = ref.read(recurringRepositoryProvider);
    if (id == null) {
      await repo.create(draft);
      await ref.read(notificationServiceProvider).requestPermission();
    } else {
      await repo.update(id, draft);
    }
  });

  Future<bool> setPaused(String id, bool paused) =>
      _run(() => ref.read(recurringRepositoryProvider).setPaused(id, paused));

  Future<bool> delete(String id) => _run(() => ref.read(recurringRepositoryProvider).delete(id));
}
