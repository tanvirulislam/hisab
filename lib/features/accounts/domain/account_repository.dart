import 'account.dart';

abstract interface class AccountRepository {
  /// Accounts in [workspaceIds] with live balances.
  Stream<List<AccountBalance>> watchAccountBalances(
    List<String> workspaceIds, {
    bool activeOnly = false,
  });
}
