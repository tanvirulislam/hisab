import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/transactions/presentation/transaction_providers.dart';
import 'package:hisab/features/workspaces/domain/workspace.dart';

void main() {
  test('remembers the last account per workspace', () async {
    final d = EntryDefaults(InMemoryLocalPrefs());
    expect(d.lastAccountFor('p'), isNull);
    await d.remember(workspaceId: 'p', accountId: 'cash');
    expect(d.lastAccountFor('p'), 'cash');
    await d.remember(workspaceId: 'p', accountId: 'bkash');
    expect(d.lastAccountFor('p'), 'bkash');
  });

  test('default workspace is the single Personal workspace', () {
    final d = EntryDefaults(InMemoryLocalPrefs());
    expect(d.defaultWorkspaceId(const []), isNull);
    expect(
      d.defaultWorkspaceId([Workspace(id: 'p', name: 'Personal', type: WorkspaceType.personal, createdAt: DateTime(2026))]),
      'p',
    );
  });

  test('corrupt stored JSON is ignored', () {
    final d = EntryDefaults(InMemoryLocalPrefs({LocalPrefKeys.lastAccountId: '{not json'}));
    expect(d.lastAccountFor('p'), isNull);
  });
}
