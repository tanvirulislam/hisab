import '../../../core/utils/local_date.dart';
import 'recurring_rule.dart';

abstract interface class RecurringRepository {
  /// Rules (not deleted) of the given workspaces, next due first.
  Stream<List<RecurringRuleItem>> watchRules(List<String> workspaceIds);

  Stream<RecurringRule?> watchRule(String id);

  /// Validates the template like a real transaction would be validated.
  /// Throws [ValidationException] and persists nothing when invalid.
  Future<String> create(RecurringDraft draft);

  /// Changes apply to future occurrences only. Transactions already
  /// generated are kept as they are.
  Future<void> update(String id, RecurringDraft draft);

  /// Pausing skips occurrences. Resuming continues from today, so the
  /// skipped occurrences are not generated afterwards.
  Future<void> setPaused(String id, bool paused);

  /// Soft delete. Transactions already generated are kept.
  Future<void> delete(String id);

  /// Records every due occurrence up to [today] (D11). Each occurrence is
  /// written together with its execution row; the unique
  /// (rule_id, occurrence_date) index makes a second run a no-op.
  Future<GenerationResult> generateDue(LocalDate today);
}
