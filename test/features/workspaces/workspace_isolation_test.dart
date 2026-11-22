import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/accounts/presentation/account_providers.dart';
import 'package:hisab/features/workspaces/domain/workspace.dart';
import 'package:hisab/features/workspaces/presentation/workspace_providers.dart';

import '../../helpers/test_db.dart';

/// Since D14 there is a single Personal workspace and no scope switching.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDb();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPrefsProvider.overrideWithValue(InMemoryLocalPrefs()),
      ],
      retry: (_, _) => null,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<T> read<T>(ProviderListenable<AsyncValue<T>> p, Future<T> future) {
    final sub = container.listen(p, (_, _) {});
    addTearDown(sub.close);
    return future;
  }

  test('only the Personal workspace exists, and every query is scoped to it', () async {
    final personal = await workspaceOfType(db, 'personal');
    final ws = await read(workspacesProvider, container.read(workspacesProvider.future));
    expect(ws.map((w) => w.type), [WorkspaceType.personal]);
    expect(await container.read(activeWorkspaceIdsProvider.future), [personal.id]);
  });

  test('account lists show the Personal accounts', () async {
    final personal = await workspaceOfType(db, 'personal');
    await addAccount(db, personal.id);
    final accounts = await read(accountBalanceProvider, container.read(accountBalanceProvider.future));
    expect(accounts.map((a) => a.account.name).toSet(), {'Cash', 'bKash'});
    final all = await read(allActiveAccountsProvider, container.read(allActiveAccountsProvider.future));
    expect(all, hasLength(2));
  });
}
