import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/bn_digits.dart';
import 'package:hisab/core/utils/local_date.dart';

void main() {
  group('LocalDate', () {
    test('int round-trip', () {
      final d = LocalDate(2026, 11, 21);
      expect(d.toInt(), 20261121);
      expect(LocalDate.fromInt(20261121), d);
      expect(d.toString(), '2026-11-21');
    });

    test('rejects invalid dates', () {
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
      expect(() => LocalDate(2026, 4, 31), throwsArgumentError);
      expect(LocalDate(2028, 2, 29).day, 29); // leap year
    });

    test('month boundaries (rule 13)', () {
      final d = LocalDate(2026, 2, 14);
      expect(d.firstOfMonth, LocalDate(2026, 2, 1));
      expect(d.lastOfMonth, LocalDate(2026, 2, 28));
      final range = DateRange.month(2026, 11);
      expect(range.start.toInt(), 20261101);
      expect(range.end.toInt(), 20261130);
      expect(range.lengthInDays, 30);
      expect(range.contains(LocalDate(2026, 11, 30)), isTrue);
      expect(range.contains(LocalDate(2026, 12, 1)), isFalse);
    });

    test('addDays crosses month and year', () {
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2026, 3, 1).addDays(-1), LocalDate(2026, 2, 28));
    });

    test('addMonths clamps to month length', () {
      expect(LocalDate(2026, 1, 31).addMonths(1), LocalDate(2026, 2, 28));
      expect(LocalDate(2026, 11, 15).addMonths(2), LocalDate(2027, 1, 15));
      expect(LocalDate(2026, 1, 15).addMonths(-1), LocalDate(2025, 12, 15));
    });

    test('ordering', () {
      final a = LocalDate(2026, 11, 20);
      final b = LocalDate(2026, 11, 21);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect([b, a]..sort(), [a, b]);
      expect(() => DateRange(b, a), throwsArgumentError);
    });
  });

  test('BnDigits round-trip', () {
    expect(BnDigits.toBangla('৳1,234.50'), '৳১,২৩৪.৫০');
    expect(BnDigits.toLatin('৳১,২৩৪.৫০'), '৳1,234.50');
    expect(BnDigits.toLatin('abc'), 'abc');
  });
}
