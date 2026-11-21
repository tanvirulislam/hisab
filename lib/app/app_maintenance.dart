import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/providers.dart';
import '../core/services/clock.dart';
import '../core/services/today_provider.dart';
import '../features/budgets/presentation/budget_providers.dart';
import '../features/recurring/presentation/recurring_providers.dart';
import '../features/workspaces/presentation/workspace_providers.dart';

part 'app_maintenance.g.dart';

/// Work that keeps stored data current: recording due recurring
/// transactions (D11) and carrying budgets into a new month.
///
/// Runs at start, when the app returns to the foreground, after local
/// midnight and after a recurring rule changes. Runs never overlap; a call
/// during a run waits for that run.
class AppMaintenance {
  AppMaintenance(this._ref);

  final Ref _ref;
  Future<void>? _running;

  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    try {
      final today = _ref.read(clockProvider).today();
      final result = await _ref.read(recurringRepositoryProvider).generateDue(today);
      if (result.pausedRuleIds.isNotEmpty) {
        debugPrint('Recurring rules paused (invalid template): ${result.pausedRuleIds}');
      }
      final workspaces = await _ref.read(workspacesProvider.future);
      await _ref.read(budgetRepositoryProvider).rolloverIfNeeded([for (final w in workspaces) w.id], today);
    } on Object catch (e, st) {
      // Never take the app down; the next run retries.
      debugPrint('Maintenance failed: $e\n$st');
    }
  }
}

@Riverpod(keepAlive: true)
AppMaintenance appMaintenance(Ref ref) {
  final m = AppMaintenance(ref);
  // A new day can make recurring occurrences due and starts a new month.
  ref.listen(todayProvider, (prev, next) {
    if (prev?.value != null && next.value != prev!.value) m.run();
  });
  return m;
}
