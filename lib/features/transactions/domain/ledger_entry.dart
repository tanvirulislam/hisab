import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';
import '../../workspaces/domain/workspace.dart';

part 'ledger_entry.freezed.dart';

/// Kind of a stored ledger row (D4/D5). The user-facing types are
/// income / expense / transfer; refunds belong to the expense workflow.
enum EntryKind {
  income('income'),
  expense('expense'),
  refund('refund'),
  transferOut('transfer_out'),
  transferIn('transfer_in');

  const EntryKind(this.dbValue);

  final String dbValue;

  bool get isTransfer => this == transferOut || this == transferIn;

  static EntryKind fromDb(String value) =>
      values.firstWhere((k) => k.dbValue == value,
          orElse: () => throw ArgumentError('Unknown entry kind: $value'));
}

/// The two kinds created through the income/expense form.
enum EntryType {
  expense,
  income;

  EntryKind get kind => this == expense ? EntryKind.expense : EntryKind.income;

  CategoryType get categoryType =>
      this == expense ? CategoryType.expense : CategoryType.income;
}

enum EntrySource {
  manual('manual'),
  voice('voice'),
  recurring('recurring'),
  repeat('repeat');

  const EntrySource(this.dbValue);

  final String dbValue;

  static EntrySource fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value, orElse: () => manual);
}

@freezed
abstract class LedgerEntry with _$LedgerEntry {
  const LedgerEntry._();

  const factory LedgerEntry({
    required String id,
    required String workspaceId,
    required String accountId,
    required EntryKind kind,
    required Money amount,
    String? categoryId,
    String? subcategoryId,
    String? description,
    required LocalDate date,
    required DateTime occurredAt,
    String? transferGroupId,
    String? counterAccountId,
    String? refundOfId,
    required EntrySource source,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _LedgerEntry;

  /// Effect on the account balance (D6).
  Money get signedAmount => switch (kind) {
    EntryKind.income || EntryKind.refund || EntryKind.transferIn => amount,
    EntryKind.expense || EntryKind.transferOut => -amount,
  };
}

/// A ledger row with everything the UI needs to show it.
@freezed
abstract class HistoryItem with _$HistoryItem {
  const HistoryItem._();

  const factory HistoryItem({
    required LedgerEntry entry,
    required WorkspaceType workspaceType,
    required Account account,
    Category? category,
    Category? subcategory,

    /// Other side of a transfer.
    Account? counterAccount,
  }) = _HistoryItem;

  /// For a transfer shown as a single row: the source account.
  Account get fromAccount =>
      entry.kind == EntryKind.transferIn ? counterAccount! : account;

  /// For a transfer shown as a single row: the destination account.
  Account get toAccount =>
      entry.kind == EntryKind.transferIn ? account : counterAccount!;
}

/// A recent income/expense combination that the user can repeat.
@freezed
abstract class RecentTemplate with _$RecentTemplate {
  const factory RecentTemplate({
    required String sourceEntryId,
    required EntryType type,
    required String workspaceId,
    required String accountId,
    required Money amount,
    required Category category,
    Category? subcategory,
    String? description,
  }) = _RecentTemplate;
}
