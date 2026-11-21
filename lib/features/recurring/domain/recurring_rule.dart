import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/ledger_entry.dart';
import '../../workspaces/domain/workspace.dart';
import 'recurrence.dart';

part 'recurring_rule.freezed.dart';

enum RecurringType {
  expense('expense'),
  income('income'),
  transfer('transfer');

  const RecurringType(this.dbValue);

  final String dbValue;

  EntryType? get entryType => switch (this) {
    expense => EntryType.expense,
    income => EntryType.income,
    transfer => null,
  };

  static RecurringType fromDb(String value) => values.firstWhere((t) => t.dbValue == value,
      orElse: () => throw ArgumentError('Unknown recurring type: $value'));
}

/// Template plus schedule of a repeating transaction (§14).
@freezed
abstract class RecurringRule with _$RecurringRule {
  const RecurringRule._();

  const factory RecurringRule({
    required String id,
    required String workspaceId,
    required RecurringType type,
    required String accountId,

    /// Destination account of a transfer.
    String? counterAccountId,
    String? categoryId,
    String? subcategoryId,
    required Money amount,
    String? description,
    required Frequency frequency,
    required int interval,
    required LocalDate startDate,
    LocalDate? endDate,

    /// The next occurrence that has not been generated yet.
    required LocalDate nextDueDate,
    required bool isPaused,
  }) = _RecurringRule;

  Recurrence get recurrence =>
      Recurrence(frequency: frequency, interval: interval, start: startDate, end: endDate);

  /// True once every occurrence up to [endDate] has been generated.
  bool get hasEnded => endDate != null && nextDueDate.isAfter(endDate!);
}

/// A rule with what the list screen needs to show it.
@freezed
abstract class RecurringRuleItem with _$RecurringRuleItem {
  const factory RecurringRuleItem({
    required RecurringRule rule,
    required WorkspaceType workspaceType,
    required Account account,
    Account? counterAccount,
    Category? category,
    Category? subcategory,
  }) = _RecurringRuleItem;
}

/// Input for creating or editing a rule.
@freezed
abstract class RecurringDraft with _$RecurringDraft {
  const factory RecurringDraft({
    required RecurringType type,

    /// Ignored for transfers: the rule belongs to the source account's
    /// workspace.
    required String workspaceId,
    required String accountId,
    String? counterAccountId,
    String? categoryId,
    String? subcategoryId,
    required Money amount,
    String? description,
    required Frequency frequency,
    @Default(1) int interval,
    required LocalDate startDate,
    LocalDate? endDate,
  }) = _RecurringDraft;
}

/// What one run of the generator did.
class GenerationResult {
  const GenerationResult({this.created = 0, this.pausedRuleIds = const []});

  /// Number of occurrences recorded.
  final int created;

  /// Rules paused because their template is no longer valid (for example
  /// the account was deactivated).
  final List<String> pausedRuleIds;
}

abstract final class RecurringError {
  static const notFound = 'recurring.not_found';
  static const intervalInvalid = 'recurring.interval_invalid';
  static const startInPast = 'recurring.start_in_past';
  static const endBeforeStart = 'recurring.end_before_start';
}
