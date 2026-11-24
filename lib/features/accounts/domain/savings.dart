import '../../../core/utils/money.dart';
import 'account.dart';

/// Savings rules (D17). Pure functions: the numbers come from the ledger.
abstract final class Savings {
  /// Total in savings accounts.
  static Money total(Iterable<AccountBalance> accounts) =>
      Money.sum(accounts.where((a) => a.account.type == AccountType.savings).map((a) => a.balance));

  /// What is left to spend: everything outside savings accounts.
  static Money spendable(Iterable<AccountBalance> accounts) =>
      Money.sum(accounts.where((a) => a.account.type != AccountType.savings).map((a) => a.balance));

  /// The savings account to offer first: the first active one.
  static Account? target(Iterable<AccountBalance> accounts) => accounts
      .map((a) => a.account)
      .where((a) => a.type == AccountType.savings && a.isActive)
      .firstOrNull;

  /// The account to take the money from: the active non-savings account
  /// holding the most.
  static Account? source(Iterable<AccountBalance> accounts) {
    AccountBalance? best;
    for (final a in accounts) {
      if (a.account.type == AccountType.savings || !a.account.isActive) continue;
      if (best == null || a.balance > best.balance) best = a;
    }
    return best?.account;
  }

  /// What is still unsaved this month: [net] (income − expense) minus what was
  /// already moved, capped at what can actually be taken out of the spendable
  /// accounts. Zero when nothing is left.
  static Money remaining({required Money net, required Money moved, required Money spendable}) {
    var r = net - moved;
    if (r > spendable) r = spendable;
    return r.isPositive ? r : Money.zero;
  }

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
