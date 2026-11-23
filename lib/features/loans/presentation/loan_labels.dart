import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../l10n/l10n.dart';
import '../domain/loan.dart';

String loanKindLabel(AppLocalizations l, LoanKind kind) => switch (kind) {
  LoanKind.lent => l.loanKindLent,
  LoanKind.repaidToMe => l.loanKindRepaidToMe,
  LoanKind.borrowed => l.loanKindBorrowed,
  LoanKind.repaidByMe => l.loanKindRepaidByMe,
};

IconData loanKindIcon(LoanKind kind) => switch (kind) {
  LoanKind.lent => Icons.call_made,
  LoanKind.repaidToMe => Icons.call_received,
  LoanKind.borrowed => Icons.call_received,
  LoanKind.repaidByMe => Icons.call_made,
};

/// Green when money comes to me, red when it leaves (same colours as
/// income / expense, but loans are never counted as those).
Color loanKindColor(FinanceColors colors, LoanKind kind) =>
    kind.isOutflow ? colors.expense : colors.income;

/// Plain text for an amount field, without the currency sign.
String amountFieldText(Money m) =>
    m.paisaPart == 0 ? '${m.taka}' : '${m.taka}.${m.paisaPart.toString().padLeft(2, '0')}';
