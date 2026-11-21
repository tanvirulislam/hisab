import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/constants/default_categories.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';
import 'package:hisab/features/voice/domain/category_lexicon.dart';
import 'package:hisab/features/voice/domain/number_words.dart';
import 'package:hisab/features/voice/domain/rule_based_parser.dart';
import 'package:hisab/features/voice/domain/text_tokens.dart';
import 'package:hisab/features/voice/domain/transaction_text_parser.dart';

/// The seeded tree with system keys as IDs, so tests read naturally.
List<Category> seededCategories() {
  final list = <Category>[];
  var order = 0;
  for (final top in [...defaultExpenseCategories, ...defaultIncomeCategories]) {
    final type = top.isIncome ? CategoryType.income : CategoryType.expense;
    Category make(DefaultCategory d, String? parent) => Category(
      id: d.key,
      parentId: parent,
      type: type,
      systemKey: d.key,
      name: d.en,
      iconKey: d.icon,
      color: d.color ?? top.color!,
      isDefault: true,
      isActive: true,
      sortOrder: order++,
    );
    list.add(make(top, null));
    for (final c in top.children) {
      list.add(make(c, top.key));
    }
  }
  return list;
}

void main() {
  final today = LocalDate(2026, 11, 21); // a Saturday
  final ctx = ParseContext(today: today, lexicon: CategoryLexicon.build(seededCategories()));
  const parser = RuleBasedBnEnParser();
  List<ParsedProposal> parse(String s) => parser.parse(s, ctx);
  ParsedProposal one(String s) {
    final r = parse(s);
    expect(r, hasLength(1), reason: 'expected one item from "$s", got ${r.map((p) => p.sourceText)}');
    return r.single;
  }

  int? paisa(String s) {
    final spans = NumberWords.findAll(TextTokens.tokenize(s));
    return spans.isEmpty ? null : spans.first.paisa;
  }

  group('numbers', () {
    test('digits in both scripts, separators and decimals', () {
      expect(paisa('৩৫০'), 35000);
      expect(paisa('1,500'), 150000);
      expect(paisa('১,২৫০.৫০'), 125050);
      expect(paisa('350টাকা'), 35000);
      expect(paisa('৳500'), 50000);
    });

    test('Bangla number words', () {
      expect(paisa('তিনশো পঞ্চাশ'), 35000);
      expect(paisa('তিন শো'), 30000);
      expect(paisa('পাঁচশ'), 50000);
      expect(paisa('দুই হাজার পাঁচশো'), 250000);
      expect(paisa('দেড় হাজার'), 150000);
      expect(paisa('দেড়শো'), 15000);
      expect(paisa('আড়াইশো'), 25000);
      expect(paisa('সাড়ে তিন হাজার'), 350000);
      expect(paisa('পৌনে দুই লাখ'), 17500000);
      expect(paisa('এক লাখ বিশ হাজার'), 12000000);
      expect(paisa('নিরানব্বই'), 9900);
      expect(paisa('ঊনত্রিশ'), 2900);
      expect(paisa('উনত্রিশ'), 2900);
    });

    test('English number words and shorthand', () {
      expect(paisa('two thousand five hundred'), 250000);
      expect(paisa('twenty five'), 2500);
      expect(paisa('fifty-five'), 5500);
      expect(paisa('1.5k'), 150000);
      expect(paisa('2k'), 200000);
      expect(paisa('1 lakh 20 thousand'), 12000000);
      expect(paisa('a hundred'), 10000);
    });

    test('two plain numbers stay separate', () {
      final spans = NumberWords.findAll(TextTokens.tokenize('350 500'));
      expect(spans.map((s) => s.paisa), [35000, 50000]);
    });
  });

  group('PRD §9 examples', () {
    test('Example 1: office transport', () {
      final p = one('আজকে অফিস যাওয়া আসায় ৮০ টাকা খরচ হয়েছে।');
      expect(p.type, EntryType.expense);
      expect(p.amount, Money.fromTaka(80));
      expect(p.categoryId, 'transport');
      expect(p.subcategoryId, 'transport.office');
      expect(p.date, today);
      expect(p.description, TextTokens.canonical('অফিস যাওয়া আসায়'));
      expect(p.needsReview, isFalse);
    });

    test('Example 2: two items in one sentence', () {
      final r = parse('আজকে বাজারে মাছ কিনেছি ৩৫০ টাকা আর সবজি কিনেছি ১৫০ টাকা।');
      expect(r, hasLength(2));
      expect(r[0].amount, Money.fromTaka(350));
      expect((r[0].categoryId, r[0].subcategoryId), ('grocery', 'grocery.fish'));
      expect(r[1].amount, Money.fromTaka(150));
      expect((r[1].categoryId, r[1].subcategoryId), ('grocery', 'grocery.vegetables'));
      expect(r.every((p) => p.date == today), isTrue);
    });

    test('Example 3: medicine', () {
      final p = one('আজকে ওষুধ কিনেছি ৫০০ টাকা।');
      expect(p.amount, Money.fromTaka(500));
      expect((p.categoryId, p.subcategoryId), ('health', 'health.medicine'));
    });
  });

  group('items', () {
    test('items without a conjunction are split after each amount', () {
      final r = parse('মাছ ৩৫০ টাকা সবজি ১৫০ টাকা ডিম ১২০ টাকা');
      expect(r.map((p) => p.amount), [Money.fromTaka(350), Money.fromTaka(150), Money.fromTaka(120)]);
      expect(r.map((p) => p.subcategoryId), ['grocery.fish', 'grocery.vegetables', 'grocery.eggs']);
    });

    test('a piece without an amount joins its neighbour', () {
      final p = one('চাল আর ডাল কিনেছি ৫০০ টাকা');
      expect(p.amount, Money.fromTaka(500));
      // Two grocery items: the category, without guessing one subcategory.
      expect((p.categoryId, p.subcategoryId), ('grocery', null));
    });

    test('quantities are not amounts', () {
      final p = one('২ কেজি চাল ১২০ টাকা');
      expect(p.amount, Money.fromTaka(120));
      expect(p.subcategoryId, 'grocery.rice');
      expect(p.description, '২ কেজি চাল');
    });

    test('a number before the currency amount stays in the description', () {
      final p = one('১০ নম্বর বাসে ২০ টাকা');
      expect(p.amount, Money.fromTaka(20));
      expect(p.subcategoryId, 'transport.bus');
    });

    test('a bare amount continues the previous item', () {
      final r = parse('রিকশা ভাড়া ৫০ টাকা আর ৩০ টাকা');
      expect(r, hasLength(2));
      expect(r[1].subcategoryId, 'transport.rickshaw');
      expect(r[1].needsReview, isTrue);
    });

    test('English sentence', () {
      final r = parse('Spent 250 taka on lunch and 40 tk for tea');
      expect(r, hasLength(2));
      expect((r[0].amount, r[0].subcategoryId), (Money.fromTaka(250), 'food.lunch'));
      expect((r[1].amount, r[1].subcategoryId), (Money.fromTaka(40), 'food.tea_coffee'));
    });

    test('number words as the amount', () {
      final p = one('রিকশায় পঞ্চাশ টাকা');
      expect(p.amount, Money.fromTaka(50));
      expect(p.subcategoryId, 'transport.rickshaw');
    });
  });

  group('word matching', () {
    test('চাল is rice, not tea; চার is four, not tea', () {
      expect(one('চাল ৬০০ টাকা').subcategoryId, 'grocery.rice');
      expect(one('চার কাপ চা ৪০ টাকা').subcategoryId, 'food.tea_coffee');
      expect(one('চার কাপ চা ৪০ টাকা').amount, Money.fromTaka(40));
    });

    test('আমি is not আম (mango)', () {
      final p = one('আমি ২০০ টাকা দিয়েছি');
      expect(p.categoryId, SystemCategoryKeys.otherExpense);
      expect(p.needsReview, isTrue);
    });

    test('nearest specific word wins between categories', () {
      final p = one('অফিস যাওয়ার পথে চা খেয়েছি ২০ টাকা');
      expect(p.subcategoryId, 'food.tea_coffee');
    });

    test('decomposed nukta letters match', () {
      // ড় written as ড + ় (U+09A1 U+09BC).
      final p = one('বা\u09A1\u09BCি ভা\u09A1\u09BCা ১৫০০০ টাকা');
      expect(p.categoryId, 'rent_bills');
    });

    test('nothing recognised falls back to Others for review', () {
      final p = one('কিছু একটা ৯০ টাকা');
      expect(p.categoryId, SystemCategoryKeys.otherExpense);
      expect(p.needsReview, isTrue);
    });

    test('no amount still proposes an item to complete', () {
      final p = one('বাজারে মাছ কিনেছি');
      expect(p.amount, isNull);
      expect(p.subcategoryId, 'grocery.fish');
      expect(p.needsReview, isTrue);
    });
  });

  group('income vs expense', () {
    test('salary received is income', () {
      final p = one('বেতন পেয়েছি ৫০০০০ টাকা');
      expect(p.type, EntryType.income);
      expect(p.categoryId, 'income.salary');
    });

    test('a paid school fee is an expense, despite বেতন', () {
      final p = one('স্কুলের বেতন ২০০০ টাকা দিয়েছি');
      expect(p.type, EntryType.expense);
      expect(p.categoryId, 'education');
    });

    test('a refund is never income (D5)', () {
      expect(one('দোকান থেকে ২০০ টাকা ফেরত পেয়েছি').type, EntryType.expense);
    });

    test('mixed items', () {
      final r = parse('বোনাস পেয়েছি ১০০০০ টাকা আর বাজার করেছি ২০০০ টাকা');
      expect(r.map((p) => p.type), [EntryType.income, EntryType.expense]);
      expect(r[0].categoryId, 'income.bonus');
      expect(r[1].categoryId, 'grocery');
    });

    test('English income', () {
      final p = one('received salary 45000');
      expect((p.type, p.categoryId, p.amount), (EntryType.income, 'income.salary', Money.fromTaka(45000)));
    });
  });

  group('dates', () {
    test('yesterday and the day before', () {
      expect(one('গতকাল রিকশা ৫০ টাকা').date, today.addDays(-1));
      expect(one('yesterday bus 30 tk').date, today.addDays(-1));
      expect(one('গত পরশু ওষুধ ২০০ টাকা').date, today.addDays(-2));
    });

    test('n days ago', () {
      final p = one('৩ দিন আগে মাছ ৪০০ টাকা');
      expect(p.date, today.addDays(-3));
      expect(p.amount, Money.fromTaka(400));
    });

    test('weekday names', () {
      // Today is Saturday 21 Nov; last Friday is the 20th.
      expect(one('শুক্রবার মাছ ৪০০ টাকা').date, LocalDate(2026, 11, 20));
      expect(one('গত শনিবার মাছ ৪০০ টাকা').date, LocalDate(2026, 11, 14));
      expect(one('শনিবার মাছ ৪০০ টাকা').date, today);
    });

    test('day of month, this month or last', () {
      expect(one('১৫ তারিখে বিদ্যুৎ বিল ১২০০ টাকা').date, LocalDate(2026, 11, 15));
      expect(one('২৫ তারিখে বিদ্যুৎ বিল ১২০০ টাকা').date, LocalDate(2026, 10, 25));
    });

    test('a date carries over to the following items', () {
      final r = parse('গতকাল মাছ ৩০০ টাকা আর সবজি ১০০ টাকা');
      expect(r.map((p) => p.date), [today.addDays(-1), today.addDays(-1)]);
    });
  });

  test('empty or punctuation-only text gives nothing', () {
    expect(parse(''), isEmpty);
    expect(parse(' ।, '), isEmpty);
  });

  test('user-created categories are found by name', () {
    final cats = [
      ...seededCategories(),
      const Category(
        id: 'pet',
        type: CategoryType.expense,
        name: 'Pet food',
        iconKey: 'pets',
        color: 0xFF000000,
        isDefault: false,
        isActive: true,
        sortOrder: 99,
      ),
    ];
    final p = const RuleBasedBnEnParser()
        .parse('pet food 800 tk', ParseContext(today: today, lexicon: CategoryLexicon.build(cats)))
        .single;
    expect(p.categoryId, 'pet');
  });

  test('archived categories are never proposed', () {
    final cats = [
      for (final c in seededCategories()) c.id == 'grocery.fish' ? c.copyWith(isActive: false) : c,
    ];
    final p = const RuleBasedBnEnParser()
        .parse('মাছ ৩০০ টাকা', ParseContext(today: today, lexicon: CategoryLexicon.build(cats)))
        .single;
    expect(p.subcategoryId, isNull);
  });
}
