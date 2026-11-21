import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/transactions/presentation/transaction_providers.dart';
import 'package:hisab/features/workspaces/domain/workspace.dart';

void main() {
  final ws = [
    Workspace(id: 'p', name: 'Personal', type: WorkspaceType.personal, createdAt: DateTime(2026)),
    Workspace(id: 'f', name: 'Family', type: WorkspaceType.family, createdAt: DateTime(2026)),
  ];

  test('remembers the last account per workspace and the last workspace', () async {
    final d = EntryDefaults(InMemoryLocalPrefs());
    expect(d.lastAccountFor('p'), isNull);
    await d.remember(workspaceId: 'p', accountId: 'cash');
    await d.remember(workspaceId: 'f', accountId: 'bkash');
    expect(d.lastAccountFor('p'), 'cash');
    expect(d.lastAccountFor('f'), 'bkash');
    expect(d.lastWorkspaceId, 'f');
  });

  test('default workspace follows the scope, or the last one in Combined', () async {
    final d = EntryDefaults(InMemoryLocalPrefs());
    expect(d.defaultWorkspaceId(WorkspaceScope.family, ws), 'f');
    expect(d.defaultWorkspaceId(WorkspaceScope.combined, ws), 'p');
    await d.remember(workspaceId: 'f', accountId: 'x');
    expect(d.defaultWorkspaceId(WorkspaceScope.combined, ws), 'f');
    expect(d.defaultWorkspaceId(WorkspaceScope.personal, ws), 'p');
  });

  test('corrupt stored JSON is ignored', () {
    final d = EntryDefaults(InMemoryLocalPrefs({LocalPrefKeys.lastAccountId: '{not json'}));
    expect(d.lastAccountFor('p'), isNull);
  });
}
