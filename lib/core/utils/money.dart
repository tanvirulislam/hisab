import 'bn_digits.dart';

/// A monetary amount in BDT, stored as an integer number of paisa
/// (1 taka = 100 paisa).
///
/// Never use floating point for money. All arithmetic stays in [int].
extension type const Money(int paisa) implements Object {
  static const Money zero = Money(0);

  /// Largest amount accepted from user input: ৳10,000,000,000 (1000 crore).
  static const int maxInputPaisa = 1000000000000;

  factory Money.fromTaka(int taka) => Money(taka * 100);

  /// Whole-taka part (truncated toward zero).
  int get taka => paisa ~/ 100;

  /// Paisa remainder in 0..99 (absolute value).
  int get paisaPart => (paisa % 100).abs();

  bool get isZero => paisa == 0;
  bool get isPositive => paisa > 0;
  bool get isNegative => paisa < 0;

  Money operator +(Money other) => Money(paisa + other.paisa);
  Money operator -(Money other) => Money(paisa - other.paisa);
  Money operator -() => Money(-paisa);
  bool operator <(Money other) => paisa < other.paisa;
  bool operator <=(Money other) => paisa <= other.paisa;
  bool operator >(Money other) => paisa > other.paisa;
  bool operator >=(Money other) => paisa >= other.paisa;

  Money abs() => Money(paisa.abs());

  /// Percentage of [total] that this amount represents, as an integer
  /// rounded down (e.g. budget utilization). Returns 0 when [total] is zero.
  int percentOf(Money total) =>
      total.paisa == 0 ? 0 : (paisa * 100) ~/ total.paisa;

  static Money sum(Iterable<Money> values) =>
      values.fold(Money.zero, (a, b) => a + b);

  /// Parses user input such as `350`, `1,500.50`, `৳ ১৫০০`, `100.5`.
  ///
  /// Returns `null` for empty, negative, malformed input, more than two
  /// decimal places, or amounts above [maxInputPaisa].
  static Money? tryParse(String input) {
    final s = BnDigits.toLatin(input.trim())
        .replaceAll('৳', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    if (s.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(s);
    if (match == null) return null;
    final whole = match.group(1)!;
    if (whole.length > 13) return null;
    final frac = (match.group(2) ?? '').padRight(2, '0');
    final value = int.parse(whole) * 100 + int.parse(frac);
    if (value > maxInputPaisa) return null;
    return Money(value);
  }
}
