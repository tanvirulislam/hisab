import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../workspaces/presentation/workspace_providers.dart';
import '../data/drift_account_repository.dart';
import '../domain/account.dart';
import '../domain/account_repository.dart';

part 'account_providers.g.dart';

@Riverpod(keepAlive: true)
AccountRepository accountRepository(Ref ref) =>
    DriftAccountRepository(ref.watch(appDatabaseProvider));

/// Accounts with balances for the active workspace scope.
@riverpod
Stream<List<AccountBalance>> accountBalance(Ref ref) async* {
  final ids = await ref.watch(activeWorkspaceIdsProvider.future);
  yield* ref.watch(accountRepositoryProvider).watchAccountBalances(ids);
}

/// Active accounts of one workspace (entry forms).
@riverpod
Stream<List<AccountBalance>> workspaceAccounts(Ref ref, String workspaceId) => ref
    .watch(accountRepositoryProvider)
    .watchAccountBalances([workspaceId], activeOnly: true);

/// Active accounts in every workspace (transfers can cross workspaces).
@riverpod
Stream<List<AccountBalance>> allActiveAccounts(Ref ref) async* {
  final workspaces = await ref.watch(workspacesProvider.future);
  yield* ref
      .watch(accountRepositoryProvider)
      .watchAccountBalances([for (final w in workspaces) w.id], activeOnly: true);
}
