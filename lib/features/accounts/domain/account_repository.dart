import '../../../core/utils/money.dart';
import 'account.dart';

abstract final class AccountError {
  static const nameInvalid = 'account.name_invalid';
  static const nameDuplicate = 'account.name_duplicate';
  static const notFound = 'account.not_found';
  static const balanceInvalid = 'account.balance_invalid';
  static const inUse = 'account.in_use';
}

class AccountDraft {
  const AccountDraft({
    required this.workspaceId,
    required this.name,
    required this.type,
    this.openingBalance = Money.zero,
  });

  final String workspaceId;
  final String name;
  final AccountType type;
  final Money openingBalance;
}

abstract interface class AccountRepository {
  /// Accounts in [workspaceIds] with live balances.
  Stream<List<AccountBalance>> watchAccountBalances(
    List<String> workspaceIds, {
    bool activeOnly = false,
  });

  Future<String> createAccount(AccountDraft draft);

  /// The workspace of an account cannot change: its transactions belong to
  /// that workspace (rule 11).
  Future<void> updateAccount(
    String id, {
    required String name,
    required AccountType type,
    required Money openingBalance,
  });

  /// Inactive accounts keep their history and balance but are hidden from
  /// entry forms.
  Future<void> setActive(String id, {required bool active});

  /// Deletes an account that no transaction or recurring rule references.
  /// Throws [ConflictException] with [AccountError.inUse] otherwise.
  Future<void> deleteAccount(String id);

  Future<int> usageCount(String id);
}
