import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'recurring_dao.g.dart';

@DriftAccessor(tables: [RecurringRules, RecurringExecutions])
class RecurringDao extends DatabaseAccessor<AppDatabase> with _$RecurringDaoMixin {
  RecurringDao(super.attachedDatabase);

  /// Rules that are not deleted, in [workspaceIds], next due first. An empty
  /// list returns nothing (D9).
  Stream<List<RecurringRuleRow>> watchRules(List<String> workspaceIds) {
    if (workspaceIds.isEmpty) return Stream.value(const []);
    return (select(recurringRules)
          ..where((r) => r.workspaceId.isIn(workspaceIds) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.nextDueDate), (r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  Stream<RecurringRuleRow?> watchById(String id) =>
      (select(recurringRules)..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
          .watchSingleOrNull();

  Future<RecurringRuleRow?> findById(String id) =>
      (select(recurringRules)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Active rules with an occurrence due on or before [today] that is within
  /// the rule's end date.
  Future<List<RecurringRuleRow>> dueRules(int today) => (select(recurringRules)
        ..where((r) =>
            r.deletedAt.isNull() &
            r.isPaused.equals(false) &
            r.nextDueDate.isSmallerOrEqualValue(today) &
            (r.endDate.isNull() | r.endDate.isBiggerOrEqual(r.nextDueDate))))
      .get();

  /// The latest occurrence date already recorded for [ruleId], if any.
  Future<int?> lastOccurrence(String ruleId) async {
    final max = recurringExecutions.occurrenceDate.max();
    final row = await (selectOnly(recurringExecutions)
          ..addColumns([max])
          ..where(recurringExecutions.ruleId.equals(ruleId)))
        .getSingle();
    return row.read(max);
  }

  Future<void> insertRule(RecurringRulesCompanion row) => into(recurringRules).insert(row);

  Future<void> updateRule(String id, RecurringRulesCompanion row) =>
      (update(recurringRules)..where((r) => r.id.equals(id))).write(row);

  /// Fails with a unique-constraint error if the occurrence was already
  /// recorded, which rolls back the surrounding transaction (D11).
  Future<void> insertExecution(RecurringExecutionsCompanion row) =>
      into(recurringExecutions).insert(row, mode: InsertMode.insert);
}
