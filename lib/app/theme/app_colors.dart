import 'package:flutter/material.dart';

/// Brand palette from PRD §18.2.
abstract final class AppColors {
  static const Color primary = Color(0xFF153D32);
  static const Color secondary = Color(0xFF398B72);
  static const Color accent = Color(0xFFF4B942);
  static const Color background = Color(0xFFF5F6F2);

  static const Color darkBackground = Color(0xFF0E1713);
  static const Color darkSurface = Color(0xFF16221D);
}

/// Semantic money colors, available through
/// `Theme.of(context).extension<FinanceColors>()!`.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
  });

  static const light = FinanceColors(
    income: Color(0xFF1E8E5A),
    expense: Color(0xFFC0392B),
    transfer: Color(0xFF2D6CDF),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFB3261E),
  );

  static const dark = FinanceColors(
    income: Color(0xFF6FD3A0),
    expense: Color(0xFFFF8A80),
    transfer: Color(0xFF8AB4F8),
    warning: Color(0xFFF4B942),
    danger: Color(0xFFF2B8B5),
  );

  final Color income;
  final Color expense;
  final Color transfer;
  final Color warning;
  final Color danger;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? danger,
  }) => FinanceColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    transfer: transfer ?? this.transfer,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension FinanceColorsX on BuildContext {
  FinanceColors get financeColors =>
      Theme.of(this).extension<FinanceColors>() ?? FinanceColors.light;
}
