import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../categories/data/drift_category_repository.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';
import '../domain/budget.dart';
import '../domain/budget_repository.dart';

class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository(this._db);

  final AppDatabase _db;

  int get _now => _db.clock.nowMillis();

  static Budget toDomain(BudgetRow r) => Budget(
    id: r.id,
    workspaceId: r.workspaceId,
    categoryId: r.categoryId,
    amount: Money(r.amountPaisa),
    year: r.year,
    month: r.month,
    warningThreshold: r.warningThreshold,
  );

  @override
  Stream<List<BudgetStatus>> watchStatuses(List<String> workspaceIds, int year, int month) =>
      _db.budgetsDao.watchWithSpent(workspaceIds, year, month).asyncMap((rows) async {
        if (rows.isEmpty) return const <BudgetStatus>[];
        final categories = {
          for (final c in await _db.categoriesDao.getAll()) c.id: DriftCategoryRepository.toDomain(c),
        };
        final types = {
          for (final w in await _db.workspacesDao.getAll()) w.id: WorkspaceType.fromDb(w.type),
        };
        final list = [
          for (final r in rows)
            BudgetStatus(
              budget: toDomain(r.budget),
              category: categories[r.budget.categoryId]!,
              workspaceType: types[r.budget.workspaceId]!,
              spent: Money(r.spentPaisa),
            ),
        ];
        // Most used first; ties keep creation order (the sort is stable).
        list.sort((a, b) => b.percent.compareTo(a.percent));
        return list;
      });

  static void _checkAmount(Money amount) {
    if (!amount.isPositive || amount.paisa > Money.maxInputPaisa) {
      throw const ValidationException(BudgetError.amountInvalid);
    }
  }

  static void _checkThreshold(int t) {
    if (t < 1 || t > 100) throw const ValidationException(BudgetError.thresholdInvalid);
  }

  @override
  Future<String> create(BudgetDraft d) => _db.transaction(() async {
    _checkAmount(d.amount);
    _checkThreshold(d.warningThreshold);
    if (d.month < 1 || d.month > 12) throw const ValidationException(BudgetError.categoryInvalid);
    final ws = await _db.workspacesDao.findById(d.workspaceId);
    final row = await _db.categoriesDao.findById(d.categoryId);
    final c = row == null ? null : DriftCategoryRepository.toDomain(row);
    // Budgets are set on top-level expense categories that the workspace can
    // use (global or its own), §12 / rule 11.
    if (ws == null ||
        ws.deletedAt != null ||
        c == null ||
        row!.deletedAt != null ||
        !c.isActive ||
        c.isSubcategory ||
        c.type != CategoryType.expense ||
        (c.workspaceId != null && c.workspaceId != d.workspaceId)) {
      throw const ValidationException(BudgetError.categoryInvalid);
    }
    if (await _db.budgetsDao.findLive(d.workspaceId, d.categoryId, d.year, d.month) != null) {
      throw const ValidationException(BudgetError.duplicate);
    }
    final id = _db.ids.newId();
    final now = _now;
    await _db.budgetsDao.insertRow(BudgetsCompanion.insert(
      id: id,
      workspaceId: d.workspaceId,
      categoryId: d.categoryId,
      amountPaisa: d.amount.paisa,
      year: d.year,
      month: d.month,
      warningThreshold: Value(d.warningThreshold),
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  });

  @override
  Future<void> update(String id, {required Money amount, required int warningThreshold}) =>
      _db.transaction(() async {
        _checkAmount(amount);
        _checkThreshold(warningThreshold);
        final row = await _db.budgetsDao.findById(id);
        if (row == null || row.deletedAt != null) throw const ValidationException(BudgetError.notFound);
        await _db.budgetsDao.updateRow(id, BudgetsCompanion(
          amountPaisa: Value(amount.paisa),
          warningThreshold: Value(warningThreshold),
          updatedAt: Value(_now),
        ));
      });

  @override
  Future<void> delete(String id) {
    final now = _now;
    return _db.budgetsDao.updateRow(id, BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  @override
  Future<int> copyFromPreviousMonth(String workspaceId, int year, int month) =>
      _db.transaction(() async {
        final prev = LocalDate(year, month, 1).addMonths(-1);
        final source = await _db.budgetsDao.forMonth(workspaceId, prev.year, prev.month);
        var copied = 0;
        final now = _now;
        for (final b in source) {
          if (await _db.budgetsDao.findLive(workspaceId, b.categoryId, year, month) != null) continue;
          // An archived category stays in last month's history but is not
          // carried into a new month.
          final cat = await _db.categoriesDao.findById(b.categoryId);
          if (cat == null || cat.deletedAt != null || !cat.isActive) continue;
          await _db.budgetsDao.insertRow(BudgetsCompanion.insert(
            id: _db.ids.newId(),
            workspaceId: workspaceId,
            categoryId: b.categoryId,
            amountPaisa: b.amountPaisa,
            year: year,
            month: month,
            warningThreshold: Value(b.warningThreshold),
            createdAt: now,
            updatedAt: now,
          ));
          copied++;
        }
        return copied;
      });

  @override
  Future<void> rolloverIfNeeded(List<String> workspaceIds, LocalDate today) async {
    for (final ws in workspaceIds) {
      await _db.transaction(() async {
        final existing = await _db.budgetsDao.forMonth(ws, today.year, today.month, includeDeleted: true);
        if (existing.isEmpty) await copyFromPreviousMonth(ws, today.year, today.month);
      });
    }
  }
}
