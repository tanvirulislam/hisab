import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
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
}
