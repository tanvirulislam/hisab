import '../../../core/utils/money.dart';
import 'text_tokens.dart';

/// A number found in a sentence: tokens [start]..[end) with value [paisa].
class NumberSpan {
  const NumberSpan(this.start, this.end, this.paisa);

  final int start;
  final int end;
  final int paisa;

  @override
  String toString() => 'NumberSpan($start..$end = $paisa)';
}

/// Reads spoken amounts in Bangla and English (D12):
/// ৩৫০, 1,500, 1.5k, তিনশো পঞ্চাশ, দুই হাজার পাঁচশো, দেড় হাজার, আড়াইশো,
/// সাড়ে তিন হাজার, পৌনে দুই লাখ, two thousand five hundred, 1 lakh 20 thousand.
///
/// Values are computed in paisa (hundredths of a taka), so fractions such as
/// দেড় (1.5) stay exact integers. Uses the South-Asian scale: শো/hundred,
/// হাজার/thousand, লাখ/lakh, কোটি/crore.
abstract final class NumberWords {
  static final Map<String, int> _bangla = _buildBangla();

  static Map<String, int> _buildBangla() {
    const words = <String>[
      'এক', 'দুই', 'তিন', 'চার', 'পাঁচ', 'ছয়', 'সাত', 'আট', 'নয়', 'দশ',
      'এগারো', 'বারো', 'তেরো', 'চৌদ্দ', 'পনেরো', 'ষোলো', 'সতেরো', 'আঠারো', 'উনিশ', 'বিশ',
      'একুশ', 'বাইশ', 'তেইশ', 'চব্বিশ', 'পঁচিশ', 'ছাব্বিশ', 'সাতাশ', 'আটাশ', 'উনত্রিশ', 'ত্রিশ',
      'একত্রিশ', 'বত্রিশ', 'তেত্রিশ', 'চৌত্রিশ', 'পঁয়ত্রিশ', 'ছত্রিশ', 'সাঁইত্রিশ', 'আটত্রিশ', 'উনচল্লিশ', 'চল্লিশ',
      'একচল্লিশ', 'বিয়াল্লিশ', 'তেতাল্লিশ', 'চুয়াল্লিশ', 'পঁয়তাল্লিশ', 'ছেচল্লিশ', 'সাতচল্লিশ', 'আটচল্লিশ', 'উনপঞ্চাশ', 'পঞ্চাশ',
      'একান্ন', 'বায়ান্ন', 'তিপ্পান্ন', 'চুয়ান্ন', 'পঞ্চান্ন', 'ছাপ্পান্ন', 'সাতান্ন', 'আটান্ন', 'উনষাট', 'ষাট',
      'একষট্টি', 'বাষট্টি', 'তেষট্টি', 'চৌষট্টি', 'পঁয়ষট্টি', 'ছেষট্টি', 'সাতষট্টি', 'আটষট্টি', 'উনসত্তর', 'সত্তর',
      'একাত্তর', 'বাহাত্তর', 'তিয়াত্তর', 'চুয়াত্তর', 'পঁচাত্তর', 'ছিয়াত্তর', 'সাতাত্তর', 'আটাত্তর', 'উনআশি', 'আশি',
      'একাশি', 'বিরাশি', 'তিরাশি', 'চুরাশি', 'পঁচাশি', 'ছিয়াশি', 'সাতাশি', 'অষ্টাশি', 'উননব্বই', 'নব্বই',
      'একানব্বই', 'বিরানব্বই', 'তিরানব্বই', 'চুরানব্বই', 'পঁচানব্বই', 'ছিয়ানব্বই', 'সাতানব্বই', 'আটানব্বই', 'নিরানব্বই',
    ];
    final map = <String, int>{};
    void add(String w, int n) => map[TextTokens.canonical(w)] = n * 100;
    for (var i = 0; i < words.length; i++) {
      add(words[i], i + 1);
      // ঊন- is also written উন-.
      if (words[i].startsWith('উন')) add('ঊন${words[i].substring(2)}', i + 1);
    }
    const variants = {
      'দু': 2, 'ছ': 6, 'ন': 9, 'এগার': 11, 'তের': 13, 'পনের': 15, 'ষোল': 16, 'সতের': 17,
      'আঠার': 18, 'কুড়ি': 20, 'ঊনিশ': 19, 'একশ': 100,
    };
    variants.forEach(add);
    map[TextTokens.canonical('দেড়')] = 150;
    map[TextTokens.canonical('আড়াই')] = 250;
    return map;
  }

  static const Map<String, int> _englishUnits = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8,
    'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
  };

  static const Map<String, int> _englishTens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
    'eighty': 80, 'ninety': 90,
  };

  static final Map<String, int> _multipliers = {
    TextTokens.canonical('শো'): 100,
    TextTokens.canonical('শ'): 100,
    TextTokens.canonical('শত'): 100,
    TextTokens.canonical('হাজার'): 1000,
    TextTokens.canonical('লাখ'): 100000,
    TextTokens.canonical('লক্ষ'): 100000,
    TextTokens.canonical('কোটি'): 10000000,
    'hundred': 100,
    'thousand': 1000,
    'k': 1000,
    'lakh': 100000,
    'lakhs': 100000,
    'lac': 100000,
    'lacs': 100000,
    'million': 1000000,
    'crore': 10000000,
    'crores': 10000000,
  };

  /// সাড়ে X = X + ½, পৌনে X = X − ¼ (in paisa: +50 / −25 per unit).
  static final Map<String, int> _modifiers = {
    TextTokens.canonical('সাড়ে'): 50,
    TextTokens.canonical('পৌনে'): -25,
  };

  static final RegExp _numeric = RegExp(r'^\d+(?:\.\d{1,2})?$');

  /// A plain number word or digits, in paisa.
  static int? _base(String key) {
    if (_numeric.hasMatch(key)) {
      final parts = key.split('.');
      if (parts[0].length > 13) return null;
      final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
      return int.parse(parts[0]) * 100 + int.parse(frac);
    }
    final bn = _bangla[key];
    if (bn != null) return bn;
    final en = _englishUnits[key] ?? _englishTens[key];
    return en == null ? null : en * 100;
  }

  /// "তিনশো" → (300 paisa ×) 100, "দেড়হাজার" → 150 × 1000.
  static (int, int)? _compound(String key) {
    for (final m in _multipliers.entries) {
      if (key.length > m.key.length && key.endsWith(m.key)) {
        final base = _base(key.substring(0, key.length - m.key.length));
        if (base != null && !_numeric.hasMatch(key)) return (base, m.value);
      }
    }
    return null;
  }

  static bool startsNumber(String key) =>
      _base(key) != null || _compound(key) != null || _multipliers.containsKey(key) || _modifiers.containsKey(key);

  /// Every number phrase in [tokens], left to right.
  static List<NumberSpan> findAll(List<Token> tokens) {
    final spans = <NumberSpan>[];
    var i = 0;
    while (i < tokens.length) {
      final span = startsNumber(tokens[i].key) ? _parseAt(tokens, i) : null;
      if (span == null) {
        i++;
      } else {
        spans.add(span);
        i = span.end;
      }
    }
    return spans;
  }

  static NumberSpan? _parseAt(List<Token> tokens, int start) {
    var total = 0;
    var group = 0;
    var any = false;
    var lastBase = 0; // value of the previous token when it was a plain number
    var lastWasEnglishTens = false;
    var modifier = 0;
    var end = start;

    void addBase(int value) {
      group += value + modifier;
      modifier = 0;
      any = true;
    }

    void applyMultiplier(int m) {
      final g = group == 0 ? 100 : group;
      if (m == 100) {
        group = g * 100;
      } else {
        total += g * m;
        group = 0;
      }
      any = true;
    }

    for (var j = start; j < tokens.length; j++) {
      final key = tokens[j].key;
      final mod = _modifiers[key];
      if (mod != null) {
        if (modifier != 0 || lastBase != 0) break;
        modifier = mod;
        continue;
      }
      final compound = _compound(key);
      if (compound != null) {
        if (lastBase != 0) break;
        addBase(compound.$1);
        applyMultiplier(compound.$2);
        lastBase = 0;
        lastWasEnglishTens = false;
        end = j + 1;
        continue;
      }
      final base = _base(key);
      if (base != null) {
        // Two plain numbers in a row are two numbers ("350 500"), except an
        // English tens word followed by a unit ("twenty five").
        final englishCompound = lastWasEnglishTens && _englishUnits[key] != null && _englishUnits[key]! < 10;
        if (lastBase != 0 && !englishCompound) break;
        addBase(base);
        lastBase = base;
        lastWasEnglishTens = _englishTens.containsKey(key);
        end = j + 1;
        continue;
      }
      final m = _multipliers[key];
      if (m != null && modifier == 0) {
        applyMultiplier(m);
        lastBase = 0;
        lastWasEnglishTens = false;
        end = j + 1;
        continue;
      }
      break;
    }
    final value = total + group;
    if (!any || end == start || value <= 0 || value > Money.maxInputPaisa) return null;
    return NumberSpan(start, end, value);
  }
}
