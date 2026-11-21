import '../../../core/database/app_database.dart';
import '../domain/category.dart';
import '../domain/category_repository.dart';

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<CategoryNode>> watchCategoryTree(
    List<String> workspaceIds,
    CategoryType type,
  ) => _db.categoriesDao
      .watchVisible(workspaceIds, type: type.dbValue)
      .map((rows) => CategoryNode.buildTree(rows.map(toDomain).toList()));

  static Category toDomain(CategoryRow row) => Category(
    id: row.id,
    workspaceId: row.workspaceId,
    parentId: row.parentId,
    type: CategoryType.fromDb(row.type),
    systemKey: row.systemKey,
    name: row.name,
    iconKey: row.icon,
    color: row.color,
    isDefault: row.isDefault,
    isActive: row.isActive,
    sortOrder: row.sortOrder,
  );
}
