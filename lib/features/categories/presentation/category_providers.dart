import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_category_repository.dart';
import '../domain/category.dart';
import '../domain/category_repository.dart';

part 'category_providers.g.dart';

@Riverpod(keepAlive: true)
CategoryRepository categoryRepository(Ref ref) =>
    DriftCategoryRepository(ref.watch(appDatabaseProvider));

/// Category tree of [type] for the active workspace scope.
@riverpod
Stream<List<CategoryNode>> categoryTree(Ref ref, CategoryType type) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(categoryRepositoryProvider).watchCategoryTree(ids, type);
}

/// Active category tree of [type] for one workspace (entry forms).
@riverpod
Stream<List<CategoryNode>> workspaceCategoryTree(
  Ref ref,
  String workspaceId,
  CategoryType type,
) => ref.watch(categoryRepositoryProvider).watchCategoryTree([workspaceId], type);

/// Tree including archived categories, for the management screen.
@riverpod
Stream<List<CategoryNode>> managedCategoryTree(Ref ref, CategoryType type) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(categoryRepositoryProvider).watchManagedTree(ids, type);
}
