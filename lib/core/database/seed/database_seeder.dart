import 'package:drift/drift.dart';

import '../../constants/default_categories.dart';
import '../../services/clock.dart';
import '../app_database.dart';

/// Inserts default workspaces, accounts and categories.
///
/// Idempotent: runs on every open and only inserts what is missing.
/// - One Personal workspace, keyed by type (D14: there is no Family).
/// - Categories are keyed by `system_key`. A seeded category the user
///   archived or deleted stays that way, because its row still exists.
class DatabaseSeeder {
  DatabaseSeeder(this.db);

  final AppDatabase db;

  /// Identifies the local device user in `workspace_members`.
  static const String localOwnerRef = 'local-owner';

  Future<void> seed() => db.transaction(() async {
    await _seedWorkspaces();
    await _seedCategories();
  });

  Future<void> _seedWorkspaces() async {
    final existing = await db.select(db.workspaces).get();
    final types = existing.map((w) => w.type).toSet();
    final now = db.clock.nowMillis();

    for (final (type, name) in const [('personal', 'Personal')]) {
      if (types.contains(type)) continue;
      final workspaceId = db.ids.newId();
      await db.into(db.workspaces).insert(
        WorkspacesCompanion.insert(
          id: workspaceId,
          name: name,
          type: type,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.workspaceMembers).insert(
        WorkspaceMembersCompanion.insert(
          id: db.ids.newId(),
          workspaceId: workspaceId,
          memberRef: localOwnerRef,
          role: 'owner',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: db.ids.newId(),
          workspaceId: workspaceId,
          name: 'Cash',
          type: 'cash',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _seedCategories() async {
    final rows = await (db.select(db.categories)
          ..where((c) => c.systemKey.isNotNull()))
        .get();
    final idByKey = {for (final r in rows) r.systemKey!: r.id};
    final now = db.clock.nowMillis();

    Future<void> insert(
      DefaultCategory c, {
      required int order,
      DefaultCategory? parent,
    }) async {
      if (idByKey.containsKey(c.key)) return;
      final id = db.ids.newId();
      final isIncome = parent?.isIncome ?? c.isIncome;
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: id,
          parentId: Value(parent == null ? null : idByKey[parent.key]),
          type: isIncome ? 'income' : 'expense',
          systemKey: Value(c.key),
          name: c.en,
          icon: c.icon,
          color: c.color ?? parent?.color ?? 0xFF546E7A,
          isDefault: const Value(true),
          sortOrder: Value(order),
          createdAt: now,
          updatedAt: now,
        ),
      );
      idByKey[c.key] = id;
    }

    final tops = [...defaultExpenseCategories, ...defaultIncomeCategories];
    for (var i = 0; i < tops.length; i++) {
      final top = tops[i];
      await insert(top, order: i);
      for (var j = 0; j < top.children.length; j++) {
        await insert(top.children[j], order: j, parent: top);
      }
    }
  }
}
