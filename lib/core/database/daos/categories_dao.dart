import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories, Budgets, RecurringRules])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.attachedDatabase);

  /// Categories visible to [workspaceIds]: global ones plus those owned by
  /// any of the given workspaces. Includes subcategories.
  Stream<List<CategoryRow>> watchVisible(
    List<String> workspaceIds, {
    String? type,
    bool activeOnly = true,
  }) {
    final query = select(categories)
      ..where(
        (c) =>
            c.deletedAt.isNull() &
            (c.workspaceId.isNull() | c.workspaceId.isIn(workspaceIds)),
      );
    if (type != null) query.where((c) => c.type.equals(type));
    if (activeOnly) query.where((c) => c.isActive.equals(true));
    query.orderBy([
      (c) => OrderingTerm(expression: c.sortOrder),
      (c) => OrderingTerm(expression: c.createdAt),
    ]);
    return query.watch();
  }

  Future<CategoryRow?> findById(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Every category, including archived and deleted ones (history needs
  /// them to show old transactions).
  Future<List<CategoryRow>> getAll() => select(categories).get();

  Future<List<CategoryRow>> childrenOf(String parentId) => (select(categories)
        ..where((c) => c.parentId.equals(parentId) & c.deletedAt.isNull()))
      .get();

  Future<void> insertRow(CategoriesCompanion row) => into(categories).insert(row);

  Future<void> updateRow(String id, CategoriesCompanion row) =>
      (update(categories)..where((c) => c.id.equals(id))).write(row);

  Future<void> updateRows(List<String> ids, CategoriesCompanion row) =>
      (update(categories)..where((c) => c.id.isIn(ids))).write(row);

  /// Budgets and recurring rules that reference [categoryId] (not deleted).
  Future<int> countOtherReferences(String categoryId) async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM budgets WHERE category_id = ?1 AND deleted_at IS NULL) + '
      '(SELECT COUNT(*) FROM recurring_rules WHERE (category_id = ?1 OR subcategory_id = ?1) '
      'AND deleted_at IS NULL) AS n',
      variables: [Variable.withString(categoryId)],
      readsFrom: {budgets, recurringRules},
    ).getSingle();
    return row.read<int>('n');
  }
}
