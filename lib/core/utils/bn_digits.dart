/// Conversion between Latin (0-9) and Bangla (০-৯) digits.
abstract final class BnDigits {
  static const _bangla = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  /// Replaces Latin digits with Bangla digits.
  static String toBangla(String input) {
    final out = StringBuffer();
    for (final unit in input.codeUnits) {
      if (unit >= 0x30 && unit <= 0x39) {
        out.write(_bangla[unit - 0x30]);
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }

  /// Replaces Bangla digits (U+09E6..U+09EF) with Latin digits.
  static String toLatin(String input) {
    final out = StringBuffer();
    for (final unit in input.codeUnits) {
      if (unit >= 0x09E6 && unit <= 0x09EF) {
        out.writeCharCode(0x30 + unit - 0x09E6);
      } else {
        out.writeCharCode(unit);
      }
    }
    return out.toString();
  }
}
