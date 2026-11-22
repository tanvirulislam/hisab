import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/today_provider.dart';
import '../../../core/utils/local_date.dart';
import '../../categories/domain/category.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../transactions/domain/history_filter.dart';
import '../../transactions/domain/ledger_entry.dart';
import '../../transactions/presentation/transaction_providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_report_repository.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import '../domain/report_repository.dart';

part 'report_providers.g.dart';

@Riverpod(keepAlive: true)
ReportRepository reportRepository(Ref ref) =>
    DriftReportRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
WeekStart weekStart(Ref ref) =>
    (ref.watch(appSettingsProvider).value ?? const AppSettings()).weekStart;

/// The period shown on the Reports tab.
class ReportSelection {
  const ReportSelection({required this.period, required this.anchor});

  final ReportPeriod period;

  /// Any date inside the selected period.
  final LocalDate anchor;

  @override
  bool operator ==(Object other) =>
      other is ReportSelection && other.period == period && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(period, anchor);
}

@Riverpod(keepAlive: true)
class ReportFilter extends _$ReportFilter {
  @override
  ReportSelection build() =>
      ReportSelection(period: ReportPeriod.month, anchor: ref.read(clockProvider).today());

  void setPeriod(ReportPeriod p) => state = ReportSelection(period: p, anchor: state.anchor);

  /// Moves by [steps] periods. Landing on the period that contains today
  /// anchors on today, so switching to Day afterwards shows today rather
  /// than the 1st of the month.
  void shift(int steps) {
    final anchor = ReportMath.shift(state.period, state.anchor, steps);
    final today = ref.read(clockProvider).today();
    final range = ReportMath.rangeFor(state.period, anchor, ref.read(weekStartProvider));
    state = ReportSelection(period: state.period, anchor: range.contains(today) ? today : anchor);
  }

  void goTo(LocalDate date) => state = ReportSelection(period: state.period, anchor: date);
}

@Riverpod(keepAlive: true)
DateRange reportRange(Ref ref) {
  final sel = ref.watch(reportFilterProvider);
  return ReportMath.rangeFor(sel.period, sel.anchor, ref.watch(weekStartProvider));
}

// ------------------------------------------------- scoped aggregate streams

@riverpod
Stream<PeriodTotals> periodTotals(Ref ref, DateRange range) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchTotals(ids, range);
}

@riverpod
Stream<List<DailyAmount>> dailySeries(Ref ref, DateRange range) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchDaily(ids, range);
}

/// Six months ending with the month of [lastMonth].
@riverpod
Stream<List<MonthAmount>> monthlyTrend(Ref ref, LocalDate lastMonth) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref
      .watch(reportRepositoryProvider)
      .watchMonthly(ids, lastMonth.firstOfMonth.addMonths(-5), lastMonth);
}

@riverpod
Stream<List<CategoryAmount>> categoryExpense(Ref ref, DateRange range, CategoryType type) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchCategoryBreakdown(ids, range, type);
}

@riverpod
Stream<List<CategoryAmount>> subcategoryExpense(Ref ref, DateRange range, String categoryId) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchSubcategoryBreakdown(ids, range, categoryId);
}

/// Every transaction of one day (daily report list). A day is small, so it
/// is loaded completely.
@riverpod
Stream<List<HistoryItem>> dayTransactions(Ref ref, LocalDate date) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref
      .watch(transactionRepositoryProvider)
      .watchHistory(HistoryQuery(
        workspaceIds: ids,
        filter: HistoryFilter(range: DateRange.day(date)),
        limit: 1 << 20,
      ))
      .map((p) => p.items);
}

// ---------------------------------------------------------------- dashboard

@riverpod
DateRange currentMonthRange(Ref ref) {
  final today = ref.currentDate();
  return DateRange.month(today.year, today.month);
}

/// Totals for the current calendar month in the active scope (§5.1).
@riverpod
Stream<PeriodTotals> monthlySummary(Ref ref) =>
    _periodStream(ref, ref.watch(currentMonthRangeProvider));

/// Totals for today in the active scope (§5.1 Today's Expenses).
@riverpod
Stream<PeriodTotals> dailySummary(Ref ref) => _periodStream(ref, DateRange.day(ref.currentDate()));

Stream<PeriodTotals> _periodStream(Ref ref, DateRange range) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchTotals(ids, range);
}
