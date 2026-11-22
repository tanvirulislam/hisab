import '../../../core/utils/local_date.dart';
import '../../../core/utils/month_cycle.dart';
import '../../categories/domain/category.dart';
import 'report_models.dart';

/// Live, scope-aware aggregates for the dashboard and reports. Every method
/// takes the workspace IDs of the active scope (D9).
abstract interface class ReportRepository {
  Stream<PeriodTotals> watchTotals(List<String> workspaceIds, DateRange range);

  /// One entry per day of [range], zero-filled.
  Stream<List<DailyAmount>> watchDaily(List<String> workspaceIds, DateRange range);

  /// One entry per month cycle from the one containing [first] to the one
  /// containing [last], zero-filled. Each entry's year/month is the cycle key.
  Stream<List<MonthAmount>> watchMonthly(
    List<String> workspaceIds,
    LocalDate first,
    LocalDate last, {
    MonthCycle cycle = const MonthCycle(),
  });

  /// Top-level categories, largest first, with shares that add up to 100.
  Stream<List<CategoryAmount>> watchCategoryBreakdown(
    List<String> workspaceIds,
    DateRange range,
    CategoryType type,
  );

  /// Subcategories of an expense category, including spending without one.
  Stream<List<CategoryAmount>> watchSubcategoryBreakdown(
    List<String> workspaceIds,
    DateRange range,
    String categoryId,
  );
}
