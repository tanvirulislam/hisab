import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/accounts/presentation/account_providers.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/categories/presentation/category_providers.dart';
import 'package:hisab/features/workspaces/domain/workspace.dart';
import 'package:hisab/features/workspaces/presentation/workspace_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late InMemoryLocalPrefs prefs;

  setUp(() async {
    db = await openTestDb();
    prefs = InMemoryLocalPrefs();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPrefsProvider.overrideWithValue(prefs),
      ],
      retry: (_, _) => null,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('WorkspaceScope', () {
    final ws = [
      Workspace(id: 'p', name: 'Personal', type: WorkspaceType.personal, createdAt: DateTime(2026)),
      Workspace(id: 'f', name: 'Family', type: WorkspaceType.family, createdAt: DateTime(2026)),
    ];

    test('resolves to the right workspace IDs', () {
      expect(WorkspaceScope.personal.resolveIds(ws), ['p']);
      expect(WorkspaceScope.family.resolveIds(ws), ['f']);
      expect(WorkspaceScope.combined.resolveIds(ws), ['p', 'f']);
    });

    test('parse falls back to personal for unknown values', () {
      expect(WorkspaceScope.parse('family'), WorkspaceScope.family);
      expect(WorkspaceScope.parse(null), WorkspaceScope.personal);
      expect(WorkspaceScope.parse('garbage'), WorkspaceScope.personal);
    });
  });

  test('only the Personal workspace is visible and the scope is fixed (D14)', () async {
    expect(container.read(activeWorkspaceScopeProvider), WorkspaceScope.personal);
    final sub = container.listen(workspacesProvider, (_, _) {});
    addTearDown(sub.close);
    final visible = await container.read(workspacesProvider.future);
    expect(visible.map((w) => w.type), [WorkspaceType.personal]);
    // The Family workspace still exists in the database.
    expect(await workspaceOfType(db, 'family'), isNotNull);
    // A scope remembered by an older version is ignored.
    await prefs.setString(LocalPrefKeys.workspaceScope, 'family');
    final restarted = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localPrefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(restarted.dispose);
    expect(restarted.read(activeWorkspaceScopeProvider), WorkspaceScope.personal);
  });

  test('account lists never include the hidden Family workspace', () async {
    final personal = await workspaceOfType(db, 'personal');

    final sub = container.listen(accountBalanceProvider, (_, _) {});
    addTearDown(sub.close);
    final accounts = await container.read(accountBalanceProvider.future);
    expect(accounts.map((a) => a.account.workspaceId).toSet(), {personal.id});

    final all = container.listen(allActiveAccountsProvider, (_, _) {});
    addTearDown(all.close);
    final transferable = await container.read(allActiveAccountsProvider.future);
    expect(transferable.map((a) => a.account.workspaceId).toSet(), {personal.id},
        reason: 'transfer pickers must not offer Family accounts');
  });

  test('categories owned by the hidden workspace are not shown', () async {
    final personal = await workspaceOfType(db, 'personal');
    final family = await workspaceOfType(db, 'family');
    final now = testNow.millisecondsSinceEpoch;
    for (final (id, ws, name) in [('mine', personal.id, 'Gym'), ('theirs', family.id, 'Tuition')]) {
      await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: id, workspaceId: Value(ws), type: 'expense',
          name: name, icon: 'label', color: 0xFF000000, createdAt: now, updatedAt: now));
    }

    final sub = container.listen(categoryTreeProvider(CategoryType.expense), (_, _) {});
    addTearDown(sub.close);
    final tree = await container.read(categoryTreeProvider(CategoryType.expense).future);
    final names = tree.map((n) => n.category.name).toSet();
    expect(names, contains('Gym'));
    expect(names, isNot(contains('Tuition')));
  });
}
