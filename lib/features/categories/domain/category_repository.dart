import 'category.dart';

abstract interface class CategoryRepository {
  /// Active categories of [type] visible to [workspaceIds] (global ones plus
  /// workspace-owned ones), as a two-level tree.
  Stream<List<CategoryNode>> watchCategoryTree(
    List<String> workspaceIds,
    CategoryType type,
  );
}
