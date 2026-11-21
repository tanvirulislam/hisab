import '../../../core/database/app_database.dart';
import '../../../core/database/daos/reports_dao.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../categories/data/drift_category_repository.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';
import '../domain/report_math.dart';
import '../domain/report_models.dart';
import '../domain/report_repository.dart';

class DriftReportRepository implements ReportRepository {
  DriftReportRepository(this._db);

  final AppDatabase _db;

  ReportsDao get _dao => _db.reportsDao;

  @override
  Stream<PeriodTotals> watchTotals(List<String> ids, DateRange range) => _dao
      .watchTotals(ids, range.start.toInt(), range.end.toInt())
      .map((r) => PeriodTotals(
            income: Money(r.income),
            grossExpense: Money(r.expense),
            refunds: Money(r.refund),
            transferIn: Money(r.transferIn),
            transferOut: Money(r.transferOut),
            count: r.count,
          ))
      .distinct();

  @override
  Stream<List<DailyAmount>> watchDaily(List<String> ids, DateRange range) => _dao
      .watchDaily(ids, range.start.toInt(), range.end.toInt())
      .map((rows) => ReportMath.fillDays(range, [
            for (final r in rows)
              DailyAmount(
                date: LocalDate.fromInt(r.localDate),
                income: Money(r.income),
                expense: Money(r.netExpense),
              ),
          ]));

  @override
  Stream<List<MonthAmount>> watchMonthly(List<String> ids, LocalDate first, LocalDate last) {
    final from = first.firstOfMonth;
    final to = last.lastOfMonth;
    return _dao.watchMonthly(ids, from.toInt(), to.toInt()).map((rows) => ReportMath.fillMonths(
          from,
          to,
          [
            for (final r in rows)
              MonthAmount(
                year: r.yearMonth ~/ 100,
                month: r.yearMonth % 100,
                income: Money(r.income),
                expense: Money(r.netExpense),
              ),
          ],
        ));
  }

  Future<Map<String, Category>> _categories() async => {
    for (final r in await _db.categoriesDao.getAll()) r.id: DriftCategoryRepository.toDomain(r),
  };

  List<CategoryAmount> _withShares(
    List<KeyAmountRow> rows,
    Map<String, Category> cats, {
    Category? parent,
  }) {
    // Drop empty rows (e.g. an expense fully refunded within the period).
    final kept = rows.where((r) => r.amount != 0).toList();
    final shares = ReportMath.sharePercents([for (final r in kept) Money(r.amount)]);
    return [
      for (var i = 0; i < kept.length; i++)
        CategoryAmount(
          category: kept[i].key == null ? parent : cats[kept[i].key],
          amount: Money(kept[i].amount),
          percent: shares[i],
          withoutSubcategory: parent != null && kept[i].key == null,
        ),
    ];
  }

  @override
  Stream<List<CategoryAmount>> watchCategoryBreakdown(
    List<String> ids,
    DateRange range,
    CategoryType type,
  ) => _dao
      .watchByCategory(ids, range.start.toInt(), range.end.toInt(), income: type == CategoryType.income)
      .asyncMap((rows) async => _withShares(rows, await _categories()));

  @override
  Stream<List<CategoryAmount>> watchSubcategoryBreakdown(
    List<String> ids,
    DateRange range,
    String categoryId,
  ) => _dao
      .watchBySubcategory(ids, range.start.toInt(), range.end.toInt(), categoryId)
      .asyncMap((rows) async {
        final cats = await _categories();
        return _withShares(rows, cats, parent: cats[categoryId]);
      });

  @override
  Stream<List<WorkspaceSplit>> watchWorkspaceSplit(List<String> ids, DateRange range) => _dao
      .watchByWorkspace(ids, range.start.toInt(), range.end.toInt())
      .asyncMap((rows) async {
        final types = {
          for (final w in await _db.workspacesDao.getAll()) w.id: WorkspaceType.fromDb(w.type),
        };
        final byId = {for (final r in rows) r.workspaceId: r};
        // Every requested workspace appears, even with no activity.
        return [
          for (final id in ids)
            if (types[id] != null)
              WorkspaceSplit(
                type: types[id]!,
                income: Money(byId[id]?.income ?? 0),
                expense: Money(byId[id]?.netExpense ?? 0),
              ),
        ];
      });
}
