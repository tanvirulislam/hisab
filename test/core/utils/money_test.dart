import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/core/utils/money_format.dart';

void main() {
  group('Money.tryParse', () {
    test('parses whole and fractional taka into paisa', () {
      expect(Money.tryParse('350'), const Money(35000));
      expect(Money.tryParse('100.50'), const Money(10050));
      expect(Money.tryParse('100.5'), const Money(10050));
      expect(Money.tryParse('0.01'), const Money(1));
      expect(Money.tryParse('12.'), const Money(1200));
    });

    test('accepts grouping, currency symbol, spaces and Bangla digits', () {
      expect(Money.tryParse('1,500'), const Money(150000));
      expect(Money.tryParse('৳ 35,000'), const Money(3500000));
      expect(Money.tryParse('১৫০০'), const Money(150000));
      expect(Money.tryParse('৳১,০০,০০০.৫০'), const Money(10000050));
    });

    test('rejects malformed, negative, over-precise and huge input', () {
      for (final bad in ['', '  ', 'abc', '-5', '1.234', '1.2.3', '.5', '5e3', '10000000001']) {
        expect(Money.tryParse(bad), isNull, reason: bad);
      }
    });

    test('accepts the maximum and rejects one paisa above it', () {
      expect(Money.tryParse('10000000000'), const Money(Money.maxInputPaisa));
      expect(Money.tryParse('10000000000.01'), isNull);
    });
  });

  group('Money arithmetic', () {
    test('is exact integer arithmetic (no floating point drift)', () {
      // 0.1 + 0.2 in floating point is 0.30000000000000004.
      final total = Money.sum(List.filled(3, const Money(10)));
      expect(total, const Money(30));
      expect(Money.sum(List.filled(1000, const Money(1))), const Money(1000));
    });

    test('taka / paisa parts', () {
      expect(const Money(10050).taka, 100);
      expect(const Money(10050).paisaPart, 50);
      expect(const Money(-10050).paisaPart, 50);
    });

    test('percentOf rounds down and handles zero total', () {
      expect(const Money(80000).percentOf(const Money(100000)), 80);
      expect(const Money(79999).percentOf(const Money(100000)), 79);
      expect(const Money(150000).percentOf(const Money(100000)), 150);
      expect(const Money(100).percentOf(Money.zero), 0);
    });
  });

  group('MoneyFormatter', () {
    const en = MoneyFormatter();
    const bn = MoneyFormatter(banglaDigits: true);

    test('PRD display examples', () {
      expect(en.format(Money.fromTaka(350)), '৳350');
      expect(en.format(Money.fromTaka(1500)), '৳1,500');
      expect(en.format(Money.fromTaka(35000)), '৳35,000');
    });

    test('lakh and crore grouping', () {
      expect(en.format(Money.fromTaka(100000)), '৳1,00,000');
      expect(en.format(Money.fromTaka(12345678)), '৳1,23,45,678');
      expect(MoneyFormatter.groupLakh(0), '0');
      expect(MoneyFormatter.groupLakh(999), '999');
      expect(MoneyFormatter.groupLakh(1000), '1,000');
    });

    test('paisa shown only when non-zero unless forced', () {
      expect(en.format(const Money(10050)), '৳100.50');
      expect(en.format(const Money(10005)), '৳100.05');
      expect(en.format(const Money(10000)), '৳100');
      expect(en.format(const Money(10000), alwaysShowPaisa: true), '৳100.00');
    });

    test('negative, signed and symbol-less', () {
      expect(en.format(const Money(-50000)), '-৳500');
      expect(en.format(const Money(50000), signed: true), '+৳500');
      expect(en.format(Money.zero, signed: true), '৳0');
      expect(en.format(Money.fromTaka(1500), withSymbol: false), '1,500');
    });

    test('Bangla digits', () {
      expect(bn.format(Money.fromTaka(1500)), '৳১,৫০০');
      expect(bn.format(const Money(10050)), '৳১০০.৫০');
      expect(bn.formatInt(100000), '১,০০,০০০');
    });

    test('format and parse round-trip', () {
      for (final p in [1, 99, 100, 10050, 150000, 1234567890]) {
        expect(Money.tryParse(en.format(Money(p))), Money(p));
        expect(Money.tryParse(bn.format(Money(p))), Money(p));
      }
    });
  });
}
