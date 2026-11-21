import 'category.dart';

abstract final class CategoryError {
  static const nameInvalid = 'category.name_invalid';
  static const nameDuplicate = 'category.name_duplicate';
  static const notFound = 'category.not_found';
  static const parentInvalid = 'category.parent_invalid';
  static const protected = 'category.protected';
  static const inUse = 'category.in_use';
  static const parentArchived = 'category.parent_archived';
  static const reassignInvalid = 'category.reassign_invalid';
}

class CategoryDraft {
  const CategoryDraft({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.color,
    this.parentId,
    this.workspaceId,
  });

  final String name;
  final CategoryType type;
  final String iconKey;
  final int color;

  /// Set to create a subcategory. It inherits the parent's type and workspace.
  final String? parentId;

  /// NULL = shared by all workspaces.
  final String? workspaceId;
}

abstract interface class CategoryRepository {
  /// Active categories of [type] visible to [workspaceIds] (global ones plus
  /// workspace-owned ones), as a two-level tree.
  Stream<List<CategoryNode>> watchCategoryTree(
    List<String> workspaceIds,
    CategoryType type,
  );

  /// Like [watchCategoryTree] but includes archived categories, for the
  /// management screen.
  Stream<List<CategoryNode>> watchManagedTree(
    List<String> workspaceIds,
    CategoryType type,
  );

  Future<String> createCategory(CategoryDraft draft);

  Future<void> updateCategory(
    String id, {
    required String name,
    required String iconKey,
    required int color,
  });

  /// Archiving hides a category from entry forms but keeps its history.
  /// Archiving a parent also archives its subcategories.
  Future<void> setArchived(String id, {required bool archived});

  /// Deletes a category (and its subcategories) that nothing references.
  /// Throws [ConflictException] with [CategoryError.inUse] otherwise.
  Future<void> deleteCategory(String id);

  /// Transactions, budgets and recurring rules using the category or any of
  /// its subcategories.
  Future<int> usageCount(String id);

  /// Safe removal of a category that is in use (§7.2): moves its
  /// transactions to [toId], then archives it. For a subcategory, [toId] is
  /// ignored and its transactions keep only the parent category.
  Future<void> reassignAndArchive(String fromId, {String? toId});
}
