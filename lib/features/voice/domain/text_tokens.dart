import '../../../core/utils/bn_digits.dart';

/// One word of a sentence. [text] is what the user said (for the
/// description); [key] is the form used for matching: Latin digits, lower
/// case, canonical Bangla letters.
class Token {
  const Token(this.text, this.key);

  final String text;
  final String key;

  bool get isSeparator => key == ',';

  @override
  String toString() => text;
}

abstract final class TextTokens {
  /// Canonical Bangla: precomposed ড় ঢ় য় (speech engines and keyboards emit
  /// either form) and no zero-width joiners.
  static String canonical(String s) => s
      .replaceAll('ড়', 'ড়')
      .replaceAll('ঢ়', 'ঢ়')
      .replaceAll('য়', 'য়')
      .replaceAll(RegExp('[‌‍]'), '');

  static final _digit = '[0-9০-৯]';

  /// Splits a sentence into tokens. Sentence punctuation becomes a ","
  /// separator token; "350টাকা" and "৳500" are split apart; "1,500" stays
  /// one number.
  static List<Token> tokenize(String input) {
    var s = canonical(input);
    s = s.replaceAll(RegExp('(?<=$_digit),(?=$_digit)'), '');
    s = s.replaceAll(RegExp(r'[।|!?;:"“”‘’()\[\]{}]'), ' , ');
    s = s.replaceAll(',', ' , ');
    s = s.replaceAll(RegExp('(?<!$_digit)\\.|\\.(?!$_digit)'), ' , ');
    s = s.replaceAll('৳', ' ৳ ');
    s = s.replaceAll(RegExp(r'[-–—/+&]'), ' ');
    s = s.replaceAllMapped(RegExp('($_digit)(?=[^0-9০-৯\\s.,])'), (m) => '${m[1]} ');
    s = s.replaceAllMapped(RegExp('([^0-9০-৯\\s.,৳])(?=$_digit)'), (m) => '${m[1]} ');
    return [
      for (final w in s.split(RegExp(r'\s+')))
        if (w.isNotEmpty) Token(w, BnDigits.toLatin(w).toLowerCase()),
    ];
  }

  /// Case endings and plural markers a keyword may carry: বাজার → বাজারে,
  /// রিকশা → রিকশায়, ওষুধ → ওষুধের, vegetable → vegetables.
  static final Set<String> _suffixes = {
    'ে', 'র', 'ের', 'য়', 'য়ে', 'য়ের', 'তে', 'কে', 'টা', 'টি', 'টার', 'টির', 'টাও',
    'গুলো', 'গুলি', 'ও', 'এ', 'এর', 'রা', 'দের', 'েরা', 'েই', 'তেই', 'েও', 'রও', 'য়ও',
    's', 'es', "'s",
  }.map(canonical).toSet();

  /// Two-letter keywords form real words with most endings (চা + র = চার
  /// "four", ফল + ে = ফলে "as a result"), so they only take these.
  static final Set<String> _shortSuffixes =
      {'য়', 'য়ে', 'য়ের', 'টা', 'টি', 'গুলো', 's'}.map(canonical).toSet();

  /// Whether [tokenKey] is the word [keyword], optionally with a suffix.
  /// Plain prefix matching would wrongly read চাল (rice) as চা (tea).
  static bool matchesWord(String tokenKey, String keyword) {
    if (tokenKey == keyword) return true;
    if (tokenKey.length <= keyword.length || !tokenKey.startsWith(keyword)) return false;
    final rest = tokenKey.substring(keyword.length);
    return keyword.length <= 2 ? _shortSuffixes.contains(rest) : _suffixes.contains(rest);
  }

  /// Whether the tokens starting at [start] spell [phrase] (keyword keys).
  static bool matchesPhrase(List<Token> tokens, int start, List<String> phrase) {
    if (start + phrase.length > tokens.length) return false;
    for (var i = 0; i < phrase.length; i++) {
      if (!matchesWord(tokens[start + i].key, phrase[i])) return false;
    }
    return true;
  }

  /// Keyword text → matching keys, normalised exactly like input.
  static List<String> keysOf(String keyword) => [for (final t in tokenize(keyword)) t.key];
}
