import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/providers.dart';
import '../core/services/clock.dart';
import '../core/services/today_provider.dart';
import '../features/budgets/presentation/budget_providers.dart';
import '../features/settings/presentation/settings_providers.dart';
import '../features/workspaces/presentation/workspace_providers.dart';

part 'app_maintenance.g.dart';

/// Work that keeps stored data current: carrying budgets into a new month.
///
/// Runs at start, when the app returns to the foreground and after local
/// midnight. Runs never overlap; a call during a run waits for that run.
class AppMaintenance {
  AppMaintenance(this._ref);

  final Ref _ref;
  Future<void>? _running;

  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    try {
      final today = _ref.read(clockProvider).today();
      final workspaces = await _ref.read(workspacesProvider.future);
      // Wait for stored settings so the rollover uses the chosen month start.
      final settings = await _ref.read(appSettingsProvider.future);
      await _ref
          .read(budgetRepositoryProvider)
          .rolloverIfNeeded([for (final w in workspaces) w.id], today, cycle: settings.monthCycle);
    } on Object catch (e, st) {
      // Never take the app down; the next run retries.
      debugPrint('Maintenance failed: $e\n$st');
    }
  }
}

@Riverpod(keepAlive: true)
AppMaintenance appMaintenance(Ref ref) {
  final m = AppMaintenance(ref);
  // A new day can start a new month.
  ref.listen(todayProvider, (prev, next) {
    if (prev?.value != null && next.value != prev!.value) m.run();
  });
  return m;
}
