import 'package:drift/drift.dart';

import '../../../core/constants/default_categories.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/clock.dart';
import '../domain/category.dart';
import '../domain/category_repository.dart';

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  static const int maxNameLength = 60;

  @override
  Stream<List<CategoryNode>> watchCategoryTree(
    List<String> workspaceIds,
    CategoryType type,
  ) => _db.categoriesDao
      .watchVisible(workspaceIds, type: type.dbValue)
      .map((rows) => CategoryNode.buildTree(rows.map(toDomain).toList()));

  @override
  Stream<List<CategoryNode>> watchManagedTree(
    List<String> workspaceIds,
    CategoryType type,
  ) => _db.categoriesDao
      .watchVisible(workspaceIds, type: type.dbValue, activeOnly: false)
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

  Future<Category> _require(String id) async {
    final row = await _db.categoriesDao.findById(id);
    if (row == null || row.deletedAt != null) {
      throw const ValidationException(CategoryError.notFound);
    }
    return toDomain(row);
  }

  String _validName(String name) {
    final n = name.trim();
    if (n.isEmpty || n.length > maxNameLength) {
      throw const ValidationException(CategoryError.nameInvalid);
    }
    return n;
  }

  /// A name may not repeat among siblings with the same type and parent
  /// that are visible in the same workspace. Translated names count too.
  Future<void> _checkUnique(
    String name, {
    required CategoryType type,
    required String? parentId,
    required String? workspaceId,
    String? excludeId,
  }) async {
    final lower = name.toLowerCase();
    final all = await _db.categoriesDao.getAll();
    for (final r in all) {
      if (r.deletedAt != null || r.id == excludeId) continue;
      if (r.type != type.dbValue || r.parentId != parentId) continue;
      final overlaps = workspaceId == null ||
          r.workspaceId == null ||
          r.workspaceId == workspaceId;
      if (!overlaps) continue;
      final seeded = r.systemKey == null ? null : defaultCategoryByKey[r.systemKey];
      final names = [r.name, ?seeded?.en, ?seeded?.bn].map((s) => s.toLowerCase());
      if (names.contains(lower)) {
        throw const ValidationException(CategoryError.nameDuplicate);
      }
    }
  }

  @override
  Future<String> createCategory(CategoryDraft d) => _db.transaction(() async {
    final name = _validName(d.name);
    var type = d.type;
    var workspaceId = d.workspaceId;
    var color = d.color;
    if (d.parentId != null) {
      final parent = await _require(d.parentId!);
      if (parent.isSubcategory) throw const ValidationException(CategoryError.parentInvalid);
      if (!parent.isActive) throw const ValidationException(CategoryError.parentArchived);
      type = parent.type;
      workspaceId = parent.workspaceId;
      color = parent.color;
    }
    if (workspaceId != null) {
      final ws = await _db.workspacesDao.findById(workspaceId);
      if (ws == null || ws.deletedAt != null) {
        throw const ValidationException(CategoryError.notFound, 'workspace');
      }
    }
    await _checkUnique(name, type: type, parentId: d.parentId, workspaceId: workspaceId);

    final id = _db.ids.newId();
    final now = _db.clock.nowMillis();
    await _db.categoriesDao.insertRow(CategoriesCompanion.insert(
      id: id,
      workspaceId: Value(workspaceId),
      parentId: Value(d.parentId),
      type: type.dbValue,
      name: name,
      icon: d.iconKey,
      color: color,
      sortOrder: const Value(1000), // after the seeded categories
      createdAt: now,
      updatedAt: now,
    ));
    return id;
  });

  @override
  Future<void> updateCategory(
    String id, {
    required String name,
    required String iconKey,
    required int color,
  }) => _db.transaction(() async {
    final current = await _require(id);
    final n = _validName(name);
    // Renaming a seeded category to its own default name is a no-op, not a
    // duplicate of itself.
    await _checkUnique(n,
        type: current.type, parentId: current.parentId,
        workspaceId: current.workspaceId, excludeId: id);
    final now = _db.clock.nowMillis();
    await _db.categoriesDao.updateRow(id, CategoriesCompanion(
      name: Value(n),
      icon: Value(iconKey),
      color: Value(color),
      updatedAt: Value(now),
    ));
    // Subcategories share their parent's color.
    if (!current.isSubcategory) {
      final children = await _db.categoriesDao.childrenOf(id);
      if (children.isNotEmpty) {
        await _db.categoriesDao.updateRows(children.map((c) => c.id).toList(),
            CategoriesCompanion(color: Value(color), updatedAt: Value(now)));
      }
    }
  });

  @override
  Future<void> setArchived(String id, {required bool archived}) => _db.transaction(() async {
    final c = await _require(id);
    if (archived && c.isProtected) throw const ValidationException(CategoryError.protected);
    if (!archived && c.isSubcategory) {
      final parent = await _require(c.parentId!);
      if (!parent.isActive) throw const ValidationException(CategoryError.parentArchived);
    }
    final ids = [id];
    if (archived && !c.isSubcategory) {
      ids.addAll((await _db.categoriesDao.childrenOf(id)).map((r) => r.id));
    }
    await _db.categoriesDao.updateRows(ids, CategoriesCompanion(
      isActive: Value(!archived),
      updatedAt: Value(_db.clock.nowMillis()),
    ));
  });

  Future<List<String>> _withChildren(String id) async =>
      [id, ...(await _db.categoriesDao.childrenOf(id)).map((r) => r.id)];

  @override
  Future<int> usageCount(String id) async {
    final ids = await _withChildren(id);
    var n = await _db.transactionsDao.countReferencingCategories(ids);
    for (final cid in ids) {
      n += await _db.categoriesDao.countOtherReferences(cid);
    }
    return n;
  }

  @override
  Future<void> deleteCategory(String id) => _db.transaction(() async {
    final c = await _require(id);
    if (c.isProtected) throw const ValidationException(CategoryError.protected);
    if (await usageCount(id) > 0) throw const ConflictException(CategoryError.inUse);
    final now = _db.clock.nowMillis();
    await _db.categoriesDao.updateRows(await _withChildren(id),
        CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  });

  @override
  Future<void> reassignAndArchive(String fromId, {String? toId}) => _db.transaction(() async {
    final from = await _require(fromId);
    if (from.isProtected) throw const ValidationException(CategoryError.protected);
    final now = _db.clock.nowMillis();

    if (from.isSubcategory) {
      await _db.transactionsDao.clearSubcategory(fromId, now);
    } else {
      if (toId == null || toId == fromId) {
        throw const ValidationException(CategoryError.reassignInvalid);
      }
      final to = await _require(toId);
      // The target must be usable everywhere the source was (rule 11).
      final compatibleScope = to.workspaceId == null || to.workspaceId == from.workspaceId;
      if (to.isSubcategory || to.type != from.type || !to.isActive || !compatibleScope) {
        throw const ValidationException(CategoryError.reassignInvalid);
      }
      for (final cid in await _withChildren(fromId)) {
        if (await _db.categoriesDao.countOtherReferences(cid) > 0) {
          // Budgets and recurring rules need explicit attention (Phase 4).
          throw const ConflictException(CategoryError.inUse, 'budgets or recurring rules');
        }
      }
      await _db.transactionsDao.reassignCategory(fromId, toId, now);
    }
    final ids = from.isSubcategory ? [fromId] : await _withChildren(fromId);
    await _db.categoriesDao.updateRows(ids,
        CategoriesCompanion(isActive: const Value(false), updatedAt: Value(now)));
  });
}
