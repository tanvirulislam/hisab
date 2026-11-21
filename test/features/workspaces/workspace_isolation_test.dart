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

  test('defaults to Personal and persists the selected scope', () async {
    expect(container.read(activeWorkspaceScopeProvider), WorkspaceScope.personal);
    await container.read(activeWorkspaceScopeProvider.notifier).select(WorkspaceScope.family);
    expect(prefs.getString(LocalPrefKeys.workspaceScope), 'family');

    final restarted = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localPrefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(restarted.dispose);
    expect(restarted.read(activeWorkspaceScopeProvider), WorkspaceScope.family);
  });

  test('account list follows the scope and never mixes workspaces', () async {
    final personal = await workspaceOfType(db, 'personal');
    final family = await workspaceOfType(db, 'family');

    final sub = container.listen(accountBalanceProvider, (_, _) {});
    addTearDown(sub.close);

    var accounts = await container.read(accountBalanceProvider.future);
    expect(accounts.map((a) => a.account.workspaceId).toSet(), {personal.id});

    await container.read(activeWorkspaceScopeProvider.notifier).select(WorkspaceScope.family);
    accounts = await container.read(accountBalanceProvider.future);
    expect(accounts.map((a) => a.account.workspaceId).toSet(), {family.id});

    await container.read(activeWorkspaceScopeProvider.notifier).select(WorkspaceScope.combined);
    accounts = await container.read(accountBalanceProvider.future);
    expect(accounts.map((a) => a.account.workspaceId).toSet(), {personal.id, family.id});
  });

  test('workspace-owned categories are visible only in their own workspace', () async {
    final personal = await workspaceOfType(db, 'personal');
    final now = testNow.millisecondsSinceEpoch;
    await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'mine', workspaceId: Value(personal.id), type: 'expense',
        name: 'Gym', icon: 'label', color: 0xFF000000, createdAt: now, updatedAt: now));

    Future<Set<String>> visibleNames() async {
      final sub = container.listen(categoryTreeProvider(CategoryType.expense), (_, _) {});
      addTearDown(sub.close);
      final tree = await container.read(categoryTreeProvider(CategoryType.expense).future);
      return tree.map((n) => n.category.name).toSet();
    }

    expect(await visibleNames(), contains('Gym'));
    await container.read(activeWorkspaceScopeProvider.notifier).select(WorkspaceScope.family);
    expect(await visibleNames(), isNot(contains('Gym')));
  });
}
