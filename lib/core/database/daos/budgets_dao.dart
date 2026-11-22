import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'budgets_dao.g.dart';

/// A budget row plus the net expense of its category in its month.
typedef BudgetSpentRow = ({BudgetRow budget, int spentPaisa});

@DriftAccessor(tables: [Budgets, Transactions])
class BudgetsDao extends DatabaseAccessor<AppDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.attachedDatabase);

  /// Budgets of [year]/[month] in [workspaceIds] with what was spent between
  /// the `yyyymmdd` dates [from] and [to] (the month cycle, D15).
  ///
  /// Spent follows the reporting rules (§12.2, §23 rule 10): expense − refunds
  /// of the budget's category (including its subcategories, which share
  /// `category_id`), in the budget's own workspace and month period.
  /// Transfers never count. An empty workspace list returns nothing (D9).
  Stream<List<BudgetSpentRow>> watchWithSpent(
    List<String> workspaceIds,
    int year,
    int month, {
    required int from,
    required int to,
  }) {
    if (workspaceIds.isEmpty) return Stream.value(const []);
    final ph = List.filled(workspaceIds.length, '?').join(', ');
    final query = customSelect(
      'SELECT b.*, COALESCE((SELECT SUM(CASE WHEN t.type = \'expense\' THEN t.amount_paisa '
      'ELSE -t.amount_paisa END) FROM transactions t '
      'WHERE t.deleted_at IS NULL AND t.workspace_id = b.workspace_id '
      "AND t.category_id = b.category_id AND t.type IN ('expense', 'refund') "
      'AND t.local_date BETWEEN ? AND ?), 0) AS spent '
      'FROM budgets b '
      'WHERE b.deleted_at IS NULL AND b.year = ? AND b.month = ? AND b.workspace_id IN ($ph) '
      'ORDER BY b.created_at',
      variables: [
        Variable.withInt(from),
        Variable.withInt(to),
        Variable.withInt(year),
        Variable.withInt(month),
        ...workspaceIds.map(Variable.withString),
      ],
      readsFrom: {budgets, transactions},
    );
    return query.watch().asyncMap((rows) => Future.wait(rows.map((r) async => (
          budget: await budgets.mapFromRow(r),
          spentPaisa: r.read<int>('spent'),
        ))));
  }

  Future<BudgetRow?> findById(String id) =>
      (select(budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// The live budget for a category and month, if one exists.
  Future<BudgetRow?> findLive(String workspaceId, String categoryId, int year, int month) =>
      (select(budgets)
            ..where((b) =>
                b.workspaceId.equals(workspaceId) &
                b.categoryId.equals(categoryId) &
                b.year.equals(year) &
                b.month.equals(month) &
                b.deletedAt.isNull()))
          .getSingleOrNull();

  /// Budgets of a month, live only unless [includeDeleted].
  Future<List<BudgetRow>> forMonth(String workspaceId, int year, int month,
          {bool includeDeleted = false}) =>
      (select(budgets)
            ..where((b) {
              final match = b.workspaceId.equals(workspaceId) & b.year.equals(year) & b.month.equals(month);
              return includeDeleted ? match : match & b.deletedAt.isNull();
            }))
          .get();

  Future<void> insertRow(BudgetsCompanion row) => into(budgets).insert(row);

  Future<void> updateRow(String id, BudgetsCompanion row) =>
      (update(budgets)..where((b) => b.id.equals(id))).write(row);
}
