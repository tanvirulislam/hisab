import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/money.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';

part 'budget.freezed.dart';

/// How far a budget is used up (§12.1). Ordered: a higher index is worse.
enum BudgetLevel {
  /// Below the warning threshold.
  normal,

  /// At or above the warning threshold (default 80%).
  warning,

  /// Exactly at the limit (100%).
  reached,

  /// Above the limit.
  over;

  /// Integer comparisons only, no rounding: spent × 100 ≥ amount × threshold.
  static BudgetLevel of({required Money spent, required Money amount, required int warningThreshold}) {
    if (spent > amount) return over;
    if (spent == amount) return reached;
    if (spent.paisa * 100 >= amount.paisa * warningThreshold) return warning;
    return normal;
  }
}

/// A monthly spending limit for one category in one workspace (§12).
@freezed
abstract class Budget with _$Budget {
  const factory Budget({
    required String id,
    required String workspaceId,
    required String categoryId,
    required Money amount,
    required int year,
    required int month,

    /// Percent of [amount] that triggers the warning.
    required int warningThreshold,
  }) = _Budget;
}

/// A budget with what was spent against it (§12.2).
@freezed
abstract class BudgetStatus with _$BudgetStatus {
  const BudgetStatus._();

  const factory BudgetStatus({
    required Budget budget,
    required Category category,
    required WorkspaceType workspaceType,

    /// Net expense (expense − refunds) in the category and month. A month
    /// with more refunds than spending can make this negative.
    required Money spent,
  }) = _BudgetStatus;

  Money get remaining => budget.amount - spent;

  /// Utilization rounded down, so 99.9% shows as 99% and never claims the
  /// limit was reached early. Never negative.
  int get percent => spent.isNegative ? 0 : spent.percentOf(budget.amount);

  BudgetLevel get level =>
      BudgetLevel.of(spent: spent, amount: budget.amount, warningThreshold: budget.warningThreshold);
}

/// Totals over several budgets (dashboard card, budget screen header).
class BudgetTotals {
  BudgetTotals(Iterable<BudgetStatus> statuses)
    : allocated = Money.sum(statuses.map((s) => s.budget.amount)),
      spent = Money.sum(statuses.map((s) => s.spent)),
      count = statuses.length;

  final Money allocated;
  final Money spent;
  final int count;

  Money get remaining => allocated - spent;
  int get percent => spent.isNegative ? 0 : spent.percentOf(allocated);
  bool get isEmpty => count == 0;
}

abstract final class BudgetError {
  static const amountInvalid = 'budget.amount_invalid';
  static const thresholdInvalid = 'budget.threshold_invalid';
  static const categoryInvalid = 'budget.category_invalid';
  static const duplicate = 'budget.duplicate';
  static const notFound = 'budget.not_found';
}
