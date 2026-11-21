import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import 'budget.dart';

class BudgetDraft {
  const BudgetDraft({
    required this.workspaceId,
    required this.categoryId,
    required this.amount,
    required this.year,
    required this.month,
    required this.warningThreshold,
  });

  final String workspaceId;

  /// A top-level expense category available in the workspace.
  final String categoryId;
  final Money amount;
  final int year;
  final int month;
  final int warningThreshold;
}

abstract interface class BudgetRepository {
  /// Budgets of one month in [workspaceIds] with live spending, most used
  /// first.
  Stream<List<BudgetStatus>> watchStatuses(List<String> workspaceIds, int year, int month);

  /// Throws [ValidationException] ([BudgetError]) and persists nothing when
  /// invalid. One budget per category, workspace and month.
  Future<String> create(BudgetDraft draft);

  /// Changes the amount and warning threshold. Category and month are fixed.
  Future<void> update(String id, {required Money amount, required int warningThreshold});

  Future<void> delete(String id);

  /// Copies the previous month's budgets of [workspaceId] into [year]/[month],
  /// skipping categories that already have a budget. Returns how many were
  /// copied.
  Future<int> copyFromPreviousMonth(String workspaceId, int year, int month);

  /// At the start of a month, carries last month's budgets forward for every
  /// workspace that has never had budgets in [today]'s month. A month in which
  /// the user deleted budgets is left alone.
  Future<void> rolloverIfNeeded(List<String> workspaceIds, LocalDate today);
}
