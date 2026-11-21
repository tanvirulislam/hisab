import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/constants/default_categories.dart';

part 'category.freezed.dart';

enum CategoryType {
  expense('expense'),
  income('income');

  const CategoryType(this.dbValue);

  final String dbValue;

  static CategoryType fromDb(String value) =>
      values.firstWhere((t) => t.dbValue == value,
          orElse: () => throw ArgumentError('Unknown category type: $value'));
}

@freezed
abstract class Category with _$Category {
  const Category._();

  const factory Category({
    required String id,

    /// NULL = shared by all workspaces.
    String? workspaceId,
    String? parentId,
    required CategoryType type,
    String? systemKey,
    required String name,
    required String iconKey,
    required int color,
    required bool isDefault,
    required bool isActive,
    required int sortOrder,
  }) = _Category;

  bool get isSubcategory => parentId != null;

  /// Fallback categories that can never be deleted or archived.
  bool get isProtected =>
      systemKey != null && SystemCategoryKeys.protectedKeys.contains(systemKey);

  /// Display name in [languageCode]. Seeded categories are translated while
  /// they keep their default name; user-created or renamed ones show their
  /// stored name (D8).
  String displayName(String languageCode) {
    final seeded = systemKey == null ? null : defaultCategoryByKey[systemKey];
    if (seeded == null || name != seeded.en) return name;
    return languageCode == 'bn' ? seeded.bn : seeded.en;
  }
}

/// A top-level category with its subcategories.
@freezed
abstract class CategoryNode with _$CategoryNode {
  const factory CategoryNode({
    required Category category,
    required List<Category> children,
  }) = _CategoryNode;

  /// Builds the two-level tree, keeping the input order. Subcategories
  /// whose parent is missing (e.g. archived) are dropped.
  static List<CategoryNode> buildTree(List<Category> flat) {
    final childrenByParent = <String, List<Category>>{};
    for (final c in flat) {
      if (c.parentId != null) {
        (childrenByParent[c.parentId!] ??= []).add(c);
      }
    }
    return [
      for (final c in flat)
        if (c.parentId == null)
          CategoryNode(category: c, children: childrenByParent[c.id] ?? const []),
    ];
  }
}
