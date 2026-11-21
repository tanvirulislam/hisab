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
