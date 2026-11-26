import '../../../core/utils/money.dart';
import 'account.dart';

/// Savings rules (D17). Pure functions: the numbers come from the ledger.
abstract final class Savings {
  /// The savings account that exists first: the first active one.
  static Account? target(Iterable<AccountBalance> accounts) => accounts
      .map((a) => a.account)
      .where((a) => a.type == AccountType.savings && a.isActive)
      .firstOrNull;

  /// The "left this month" figure: what is left of the month's income after
  /// expenses and after what was already moved to savings. An overspent month
  /// (net ≤ 0) shows its deficit as it is: saving is not spending, so moving
  /// money never makes it worse. Never goes below zero because of savings.
  static Money leftThisMonth({required Money net, required Money moved}) {
    if (!net.isPositive) return net;
    final left = net - moved;
    return left.isPositive ? left : Money.zero;
  }
}
