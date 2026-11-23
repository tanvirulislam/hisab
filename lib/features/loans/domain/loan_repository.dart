import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import 'loan.dart';

abstract final class LoanError {
  static const amountInvalid = 'loan.amount_invalid';
  static const nameInvalid = 'loan.name_invalid';
  static const nameDuplicate = 'loan.name_duplicate';
  static const personNotFound = 'loan.person_not_found';
  static const personInUse = 'loan.person_in_use';
  static const entryNotFound = 'loan.entry_not_found';
  static const accountRequired = 'loan.account_required';
  static const accountNotFound = 'loan.account_not_found';
  static const accountInactive = 'loan.account_inactive';
  static const exceedsOutstanding = 'loan.exceeds_outstanding';
  static const noteTooLong = 'loan.note_too_long';
}

/// A new loan step. Give either [personId] (existing person) or
/// [personName] (the person is found by name, or created).
class LoanEntryDraft {
  const LoanEntryDraft({
    required this.workspaceId,
    this.personId,
    this.personName,
    required this.kind,
    required this.amount,
    required this.date,
    this.accountId,
    this.note,
  });

  final String workspaceId;
  final String? personId;
  final String? personName;
  final LoanKind kind;
  final Money amount;
  final LocalDate date;

  /// Required for repayments. For `lent` / `borrowed`, null means an old loan
  /// that changes no account balance.
  final String? accountId;
  final String? note;
}

abstract interface class LoanRepository {
  Stream<List<PersonLoanSummary>> watchSummaries(List<String> workspaceIds);

  Stream<Person?> watchPerson(String id);

  /// Entries of one person, newest first.
  Stream<List<LoanEntry>> watchEntries(String personId);

  /// Creates the entry and returns its id. Throws [ValidationException] for
  /// bad input and [ConflictException] with [LoanError.exceedsOutstanding]
  /// when a repayment is larger than what is still open.
  Future<String> addEntry(LoanEntryDraft draft);

  /// Kind and person of an entry never change. The rule that a repayment
  /// cannot exceed the open amount is re-checked after the change.
  Future<void> updateEntry(
    String id, {
    required Money amount,
    required LocalDate date,
    String? accountId,
    String? note,
  });

  /// Soft delete. Refused when it would leave a repayment larger than what
  /// is open (delete the repayment first).
  Future<void> deleteEntry(String id);

  Future<void> updatePerson(String id, {required String name, String? phone});

  /// Soft delete; only for a person with no live entries.
  Future<void> deletePerson(String id);
}
