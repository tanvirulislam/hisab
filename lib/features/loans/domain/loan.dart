import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';

part 'loan.freezed.dart';

/// The four steps of a loan (D16).
enum LoanKind {
  /// I gave money to someone: account −, they owe me more.
  lent('lent'),

  /// They paid me back: account +, they owe me less.
  repaidToMe('repaid_to_me'),

  /// I took money from someone: account +, I owe more.
  borrowed('borrowed'),

  /// I paid someone back: account −, I owe less.
  repaidByMe('repaid_by_me');

  const LoanKind(this.dbValue);

  final String dbValue;

  /// True for the two steps that start a loan (they may have no account).
  bool get isOrigin => this == lent || this == borrowed;

  /// Money leaves the account.
  bool get isOutflow => this == lent || this == repaidByMe;

  /// The origin kind a repayment settles.
  LoanKind? get settles => switch (this) {
    repaidToMe => lent,
    repaidByMe => borrowed,
    _ => null,
  };

  static LoanKind fromDb(String value) => values.firstWhere(
    (k) => k.dbValue == value,
    orElse: () => throw ArgumentError('Unknown loan kind: $value'),
  );
}

@freezed
abstract class Person with _$Person {
  const factory Person({
    required String id,
    required String workspaceId,
    required String name,
    String? phone,
  }) = _Person;
}

@freezed
abstract class LoanEntry with _$LoanEntry {
  const factory LoanEntry({
    required String id,
    required String personId,
    required String workspaceId,

    /// NULL for an old loan that does not touch any account balance.
    String? accountId,
    required LoanKind kind,
    required Money amount,
    required LocalDate date,
    String? note,
  }) = _LoanEntry;
}

/// What is still open with one person. Always computed from the entries
/// (D6): `owedToMe = lent − repaidToMe`, `iOwe = borrowed − repaidByMe`.
@freezed
abstract class PersonLoanSummary with _$PersonLoanSummary {
  const PersonLoanSummary._();

  const factory PersonLoanSummary({
    required Person person,
    required Money owedToMe,
    required Money iOwe,
    LocalDate? lastDate,
  }) = _PersonLoanSummary;

  /// Positive: they owe me on balance. Negative: I owe them.
  Money get net => owedToMe - iOwe;

  bool get isSettled => owedToMe.isZero && iOwe.isZero;
}

@freezed
abstract class LoanTotals with _$LoanTotals {
  const factory LoanTotals({
    @Default(Money.zero) Money owedToMe,
    @Default(Money.zero) Money iOwe,
  }) = _LoanTotals;
}
