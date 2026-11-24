import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/money.dart';

part 'account.freezed.dart';

enum AccountType {
  cash('cash'),
  bank('bank'),
  bkash('bkash'),
  nagad('nagad'),

  /// Money set aside (D17). Moved in and out by ordinary transfers.
  savings('savings'),
  other('other');

  const AccountType(this.dbValue);

  final String dbValue;

  static AccountType fromDb(String value) =>
      values.firstWhere((t) => t.dbValue == value,
          orElse: () => throw ArgumentError('Unknown account type: $value'));
}

@freezed
abstract class Account with _$Account {
  const factory Account({
    required String id,
    required String workspaceId,
    required String name,
    required AccountType type,
    required Money openingBalance,
    required bool isActive,
    required int sortOrder,
  }) = _Account;
}

/// An account with its balance derived from the opening balance and its
/// transactions (D6). The balance is never stored.
@freezed
abstract class AccountBalance with _$AccountBalance {
  const factory AccountBalance({
    required Account account,
    required Money balance,
  }) = _AccountBalance;
}
