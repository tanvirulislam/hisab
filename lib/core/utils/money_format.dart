import 'bn_digits.dart';
import 'money.dart';

/// Formats [Money] for display, using integer arithmetic only.
///
/// Uses South-Asian (lakh) grouping: ৳1,500 · ৳35,000 · ৳1,00,000.
/// Paisa are shown only when non-zero (৳100.50), unless [alwaysShowPaisa].
class MoneyFormatter {
  const MoneyFormatter({this.banglaDigits = false});

  final bool banglaDigits;

  static const String symbol = '৳';

  String format(
    Money amount, {
    bool withSymbol = true,
    bool alwaysShowPaisa = false,
    bool signed = false,
  }) {
    final negative = amount.paisa < 0;
    final abs = amount.paisa.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;

    final buf = StringBuffer();
    if (negative) {
      buf.write('-');
    } else if (signed && abs > 0) {
      buf.write('+');
    }
    if (withSymbol) buf.write(symbol);
    buf.write(groupLakh(whole));
    if (frac != 0 || alwaysShowPaisa) {
      buf.write('.');
      buf.write(frac.toString().padLeft(2, '0'));
    }
    final text = buf.toString();
    return banglaDigits ? BnDigits.toBangla(text) : text;
  }

  /// Formats a plain integer with lakh grouping (no currency symbol).
  String formatInt(int value) {
    final text = (value < 0 ? '-' : '') + groupLakh(value.abs());
    return banglaDigits ? BnDigits.toBangla(text) : text;
  }

  /// 1234567 → "12,34,567".
  static String groupLakh(int nonNegative) {
    assert(nonNegative >= 0);
    final s = nonNegative.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}
