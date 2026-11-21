import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';

/// Totals for a period under the reporting rules (§23): transfers excluded
/// from income/expense, refunds reduce expense.
class PeriodTotals {
  const PeriodTotals({
    required this.income,
    required this.grossExpense,
    required this.refunds,
    required this.transferIn,
    required this.transferOut,
    required this.count,
  });

  static const empty = PeriodTotals(
    income: Money.zero,
    grossExpense: Money.zero,
    refunds: Money.zero,
    transferIn: Money.zero,
    transferOut: Money.zero,
    count: 0,
  );

  final Money income;
  final Money grossExpense;
  final Money refunds;
  final Money transferIn;
  final Money transferOut;

  /// Number of income, expense and refund rows (transfers not counted).
  final int count;

  /// Net expense = expenses − refunds.
  Money get expense => grossExpense - refunds;

  /// Net savings / movement = income − net expense.
  Money get net => income - expense;

  bool get hasTransfers => !transferIn.isZero || !transferOut.isZero;
  bool get isEmpty => count == 0 && !hasTransfers;

  @override
  bool operator ==(Object other) =>
      other is PeriodTotals &&
      other.income == income &&
      other.grossExpense == grossExpense &&
      other.refunds == refunds &&
      other.transferIn == transferIn &&
      other.transferOut == transferOut &&
      other.count == count;

  @override
  int get hashCode => Object.hash(income, grossExpense, refunds, transferIn, transferOut, count);
}

class DailyAmount {
  const DailyAmount({required this.date, required this.income, required this.expense});

  final LocalDate date;
  final Money income;

  /// Net expense of the day.
  final Money expense;

  @override
  bool operator ==(Object other) =>
      other is DailyAmount && other.date == date && other.income == income && other.expense == expense;

  @override
  int get hashCode => Object.hash(date, income, expense);

  @override
  String toString() => 'DailyAmount($date, in: $income, out: $expense)';
}

class MonthAmount {
  const MonthAmount({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  final int year;
  final int month;
  final Money income;
  final Money expense;

  LocalDate get firstDay => LocalDate(year, month, 1);

  @override
  bool operator ==(Object other) =>
      other is MonthAmount &&
      other.year == year &&
      other.month == month &&
      other.income == income &&
      other.expense == expense;

  @override
  int get hashCode => Object.hash(year, month, income, expense);
}

/// One slice of a category breakdown.
class CategoryAmount {
  const CategoryAmount({
    required this.category,
    required this.amount,
    required this.percent,
    this.withoutSubcategory = false,
  });

  /// NULL when the category row no longer exists.
  final Category? category;
  final Money amount;

  /// Share of the positive total, 0–100. Shares of a breakdown add up to 100.
  final int percent;

  /// In a subcategory breakdown: spending on the parent without a
  /// subcategory.
  final bool withoutSubcategory;
}

class WorkspaceSplit {
  const WorkspaceSplit({required this.type, required this.income, required this.expense});

  final WorkspaceType type;
  final Money income;
  final Money expense;
}
