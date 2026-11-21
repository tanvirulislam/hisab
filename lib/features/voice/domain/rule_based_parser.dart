import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/ledger_entry.dart';
import 'category_lexicon.dart';
import 'number_words.dart';
import 'text_tokens.dart';
import 'transaction_text_parser.dart';
import 'voice_keywords.dart';

/// Rule-based Bangla/English parser (D12). Pipeline:
/// 1. tokenize (Bangla nukta forms, digits, punctuation);
/// 2. find dates (আজ, গতকাল, ৩ দিন আগে, গত শুক্রবার, ২০ তারিখ, …);
/// 3. find numbers and pick each item's amount (a number next to টাকা/৳
///    wins; quantities like "২ কেজি" are skipped);
/// 4. split into items on আর / এবং / and / "," and between amounts that
///    follow each other (`মাছ ৩৫০ টাকা সবজি ১৫০ টাকা`); pieces without an
///    amount join their neighbour (`চাল আর ডাল ৫০০ টাকা` is one item);
/// 5. per item: type (income cues vs expense verbs), category (keywords),
///    description (the remaining words), confidence.
class RuleBasedBnEnParser implements TransactionTextParser {
  const RuleBasedBnEnParser();

  static final _phrases = _Phrases();

  @override
  List<ParsedProposal> parse(String text, ParseContext ctx) {
    final tokens = TextTokens.tokenize(text);
    if (tokens.every((t) => t.isSeparator)) return const [];

    final dates = _findDates(tokens, ctx.today);
    final consumed = <int>{for (final d in dates) ...d.indexes};
    final amounts = _findAmounts(tokens, consumed);
    final segments = _segments(tokens, amounts);

    final result = <ParsedProposal>[];
    var date = ctx.today;
    _Category? previousCategory;
    for (final seg in segments) {
      final segDate = dates.where((d) => d.index >= seg.start && d.index < seg.end).firstOrNull;
      if (segDate != null) date = segDate.date;
      // A number next to টাকা/৳ is the amount; "১০ নম্বর বাসে ২০ টাকা" is ৳20.
      final inSeg = amounts.where((a) => a.span.start >= seg.start && a.span.start < seg.end);
      final amount = inSeg.where((a) => a.strong).firstOrNull ?? inSeg.firstOrNull;
      final type = _typeOf(tokens, seg);
      var category = _categoryOf(tokens, seg, type, ctx.lexicon, amount?.span.start);
      // "রিকশা ৫০ আর ৩০": a bare amount continues the previous item's category.
      if (category == null && previousCategory != null && previousCategory.type == type) {
        category = previousCategory.inherited();
      }
      previousCategory = category;

      final skip = <int>{
        ...consumed,
        if (amount != null) ...amount.indexes,
      };
      final confidence = (amount == null ? 0.0 : (amount.strong ? 0.5 : 0.35)) +
          (category?.confidence ?? 0.0) +
          0.1;
      result.add(ParsedProposal(
        type: type == CategoryType.income ? EntryType.income : EntryType.expense,
        amount: amount == null ? null : Money(amount.span.paisa),
        categoryId: category?.categoryId ?? ctx.lexicon.fallbackFor(type),
        subcategoryId: category?.subcategoryId,
        date: date,
        description: _description(tokens, seg, skip),
        confidence: confidence > 1 ? 1 : confidence,
        sourceText: tokens.sublist(seg.start, seg.end).where((t) => !t.isSeparator).join(' '),
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------- dates

  static List<_DateHit> _findDates(List<Token> tokens, LocalDate today) {
    final hits = <_DateHit>[];
    for (var i = 0; i < tokens.length; i++) {
      final k = tokens[i].key;
      // "৩ দিন আগে" / "3 days ago"
      final n = int.tryParse(k);
      if (n != null && i + 2 < tokens.length) {
        final unit = tokens[i + 1].key;
        final ago = tokens[i + 2].key;
        if ((_phrases.isWord(unit, _phrases.dayUnits)) && _phrases.isWord(ago, _phrases.ago) && n <= 366) {
          hits.add(_DateHit(i, {i, i + 1, i + 2}, today.addDays(-n)));
          i += 2;
          continue;
        }
      }
      // "২০ তারিখ" → the 20th of this month, or of last month if still ahead.
      if (n != null && n >= 1 && n <= 31 && i + 1 < tokens.length && _phrases.isWord(tokens[i + 1].key, _phrases.dateOfMonth)) {
        var month = today.firstOfMonth;
        if (n > today.day) month = month.addMonths(-1);
        final day = n > LocalDate.daysInMonth(month.year, month.month) ? LocalDate.daysInMonth(month.year, month.month) : n;
        hits.add(_DateHit(i, {i, i + 1}, LocalDate(month.year, month.month, day)));
        i += 1;
        continue;
      }
      // "গত পরশু", "গত কাল", "last friday": the prefix belongs to the date.
      final withPrefix = i > 0 && _phrases.isWord(tokens[i - 1].key, _phrases.last);
      final indexes = {i, if (withPrefix) i - 1};
      if (_phrases.isWord(k, _phrases.today)) {
        hits.add(_DateHit(i, {i}, today));
      } else if (_phrases.isWord(k, _phrases.dayBeforeYesterday)) {
        hits.add(_DateHit(i, indexes, today.addDays(-2)));
      } else if (_phrases.isWord(k, _phrases.yesterday)) {
        hits.add(_DateHit(i, indexes, today.addDays(-1)));
      } else {
        final weekday = _phrases.weekdayOf(k);
        if (weekday != null) {
          // "গত শুক্রবার" is strictly before today; plain "শুক্রবার" may be today.
          var back = (today.weekday - weekday) % 7;
          if (withPrefix && back == 0) back = 7;
          hits.add(_DateHit(i, indexes, today.addDays(-back)));
        }
      }
    }
    return hits;
  }

  // -------------------------------------------------------------- amounts

  static List<_Amount> _findAmounts(List<Token> tokens, Set<int> consumed) {
    final result = <_Amount>[];
    for (final span in NumberWords.findAll(tokens)) {
      if (consumed.contains(span.start)) continue;
      final next = span.end < tokens.length ? tokens[span.end].key : null;
      final prev = span.start > 0 ? tokens[span.start - 1].key : null;
      if (next != null && _phrases.isWord(next, quantityUnits)) continue;
      final currencyAfter = next != null && _phrases.isWord(next, currencyWords);
      final currencyBefore = prev != null && _phrases.isWord(prev, currencyWords);
      result.add(_Amount(
        span,
        strong: currencyAfter || currencyBefore,
        currencyIndex: currencyAfter ? span.end : (currencyBefore ? span.start - 1 : null),
      ));
    }
    return result;
  }

  // ------------------------------------------------------------- segments

  static List<_Range> _segments(List<Token> tokens, List<_Amount> amounts) {
    // 1. Split on separators.
    final raw = <_Range>[];
    var start = 0;
    for (var i = 0; i <= tokens.length; i++) {
      final isSep = i == tokens.length ||
          tokens[i].isSeparator ||
          _phrases.isWord(tokens[i].key, itemSeparators);
      if (isSep) {
        if (i > start) raw.add(_Range(start, i));
        start = i + 1;
      }
    }
    // 2. Split again between amounts in the same piece ("মাছ ৩৫০ টাকা সবজি
    //    ১৫০ টাকা"), except a plain number before a currency amount, which
    //    is part of the description ("১০ নম্বর বাসে ২০ টাকা").
    final split = <_Range>[];
    for (final r in raw) {
      var from = r.start;
      final inside = amounts.where((a) => a.span.start >= r.start && a.span.start < r.end).toList();
      for (var j = 0; j < inside.length - 1; j++) {
        final a = inside[j];
        if (!a.strong && inside[j + 1].strong) continue;
        final cut = a.currencyIndex != null && a.currencyIndex! >= a.span.end ? a.currencyIndex! + 1 : a.span.end;
        if (cut > from && cut < r.end) {
          split.add(_Range(from, cut));
          from = cut;
        }
      }
      split.add(_Range(from, r.end));
    }
    // 3. Pieces without an amount join the next piece (or the previous one
    //    at the end).
    bool hasAmount(_Range r) => amounts.any((a) => a.span.start >= r.start && a.span.start < r.end);
    final merged = <_Range>[];
    _Range? pending;
    for (final r in split) {
      final cur = pending == null ? r : _Range(pending.start, r.end);
      if (hasAmount(cur)) {
        merged.add(cur);
        pending = null;
      } else {
        pending = cur;
      }
    }
    if (pending != null) {
      if (merged.isEmpty) {
        merged.add(pending);
      } else {
        merged[merged.length - 1] = _Range(merged.last.start, pending.end);
      }
    }
    return merged;
  }

  // ----------------------------------------------------------------- type

  static CategoryType _typeOf(List<Token> tokens, _Range seg) {
    bool any(List<String> words) => _phrases.containsAny(tokens, seg, words);
    final income = any(incomeCues) && !any(expenseVerbs) && !any(refundCues);
    return income ? CategoryType.income : CategoryType.expense;
  }

  // ------------------------------------------------------------- category

  static _Category? _categoryOf(
    List<Token> tokens,
    _Range seg,
    CategoryType type,
    CategoryLexicon lexicon,
    int? amountIndex,
  ) {
    final hits = <(LexiconEntry, int)>[];
    for (final e in lexicon.entries) {
      if (e.type != type) continue;
      for (var i = seg.start; i < seg.end; i++) {
        if (TextTokens.matchesPhrase(tokens, i, e.phrase)) hits.add((e, i));
      }
    }
    if (hits.isEmpty) return null;
    final best = hits.map((h) => h.$1.weight).reduce((a, b) => a > b ? a : b);
    final strongest = hits.where((h) => h.$1.weight == best).toList();
    // Several specific words from different categories: take the one
    // nearest the amount ("অফিস যাওয়ার পথে চা ২০ টাকা" → tea).
    int distance((LexiconEntry, int) h) => amountIndex == null ? h.$2 : (h.$2 - amountIndex).abs();
    strongest.sort((a, b) => distance(a).compareTo(distance(b)));
    final top = strongest.first.$1.categoryId;
    // Within that category, one subcategory named → use it; several (চাল আর
    // ডাল) → the category alone.
    final subs = {
      for (final h in hits)
        if (h.$1.categoryId == top && h.$1.subcategoryId != null) h.$1.subcategoryId!,
    };
    return _Category(
      type: type,
      categoryId: top,
      subcategoryId: subs.length == 1 ? subs.first : null,
      confidence: best >= CategoryLexicon.strong ? 0.4 : 0.25,
    );
  }

  // ---------------------------------------------------------- description

  static String? _description(List<Token> tokens, _Range seg, Set<int> skip) {
    final words = <String>[];
    for (var i = seg.start; i < seg.end; i++) {
      final t = tokens[i];
      if (skip.contains(i) || t.isSeparator) continue;
      if (_phrases.isWord(t.key, currencyWords) || _phrases.isWord(t.key, fillerWords)) continue;
      words.add(t.text);
    }
    if (words.isEmpty) return null;
    final text = words.join(' ');
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;
}

class _DateHit {
  const _DateHit(this.index, this.indexes, this.date);

  final int index;
  final Set<int> indexes;
  final LocalDate date;
}

class _Amount {
  _Amount(this.span, {required this.strong, this.currencyIndex});

  final NumberSpan span;

  /// Next to a currency word: almost certainly the amount.
  final bool strong;
  final int? currencyIndex;

  Set<int> get indexes => {
    for (var i = span.start; i < span.end; i++) i,
    ?currencyIndex,
  };
}

class _Category {
  const _Category({required this.type, required this.categoryId, this.subcategoryId, required this.confidence});

  final CategoryType type;
  final String categoryId;
  final String? subcategoryId;
  final double confidence;

  _Category inherited() =>
      _Category(type: type, categoryId: categoryId, subcategoryId: subcategoryId, confidence: 0.15);
}

/// Word lists normalised once into matching keys.
class _Phrases {
  _Phrases();

  final today = _keys(['আজ', 'আজকে', 'আজকের', 'today']);
  final yesterday = _keys(['গতকাল', 'গতকালকে', 'কাল', 'কালকে', 'yesterday']);
  final dayBeforeYesterday = _keys(['পরশু', 'পরশুদিন']);
  final last = _keys(['গত', 'last']);
  final dayUnits = _keys(['দিন', 'day', 'days']);
  final ago = _keys(['আগে', 'ago']);
  final dateOfMonth = _keys(['তারিখ', 'তারিখে']);

  final Map<String, int> _weekdays = {
    for (final e in {
      'সোমবার': 1, 'মঙ্গলবার': 2, 'বুধবার': 3, 'বৃহস্পতিবার': 4, 'শুক্রবার': 5, 'শনিবার': 6, 'রবিবার': 7,
      'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
    }.entries)
      TextTokens.keysOf(e.key).first: e.value,
  };

  final Map<List<String>, List<List<String>>> _cache = {};

  static List<String> _keys(List<String> words) => [for (final w in words) TextTokens.keysOf(w).first];

  int? weekdayOf(String key) {
    for (final e in _weekdays.entries) {
      if (TextTokens.matchesWord(key, e.key)) return e.value;
    }
    return null;
  }

  /// [key] equals one of [words] (raw word lists are normalised and cached).
  bool isWord(String key, List<String> words) =>
      _normalised(words).any((p) => p.length == 1 && TextTokens.matchesWord(key, p.first));

  /// Whether the segment contains any of [words] (single words or phrases).
  bool containsAny(List<Token> tokens, _Range seg, List<String> words) {
    for (final p in _normalised(words)) {
      for (var i = seg.start; i < seg.end; i++) {
        if (TextTokens.matchesPhrase(tokens, i, p)) return true;
      }
    }
    return false;
  }

  List<List<String>> _normalised(List<String> words) => _cache.putIfAbsent(
      words, () => [for (final w in words) TextTokens.keysOf(w).where((k) => k != ',').toList()]);
}
