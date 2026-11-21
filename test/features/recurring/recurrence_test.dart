import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/budgets/domain/budget.dart';
import 'package:hisab/features/recurring/domain/recurrence.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  group('Recurrence', () {
    test('monthly on the 31st clamps and returns to the 31st', () {
      final r = Recurrence(frequency: Frequency.monthly, interval: 1, start: d(2026, 1, 31));
      expect(r.between(d(2026, 1, 1), d(2026, 5, 31)),
          [d(2026, 1, 31), d(2026, 2, 28), d(2026, 3, 31), d(2026, 4, 30), d(2026, 5, 31)]);
    });

    test('leap day yearly falls on Feb 28 in other years', () {
      final r = Recurrence(frequency: Frequency.yearly, interval: 1, start: d(2028, 2, 29));
      expect(r.occurrence(1), d(2029, 2, 28));
      expect(r.occurrence(4), d(2032, 2, 29));
    });

    test('every 2 weeks', () {
      final r = Recurrence(frequency: Frequency.weekly, interval: 2, start: d(2026, 11, 2));
      expect(r.between(d(2026, 11, 1), d(2026, 12, 31)),
          [d(2026, 11, 2), d(2026, 11, 16), d(2026, 11, 30), d(2026, 12, 14), d(2026, 12, 28)]);
    });

    test('daily every 3 days across a month end', () {
      final r = Recurrence(frequency: Frequency.daily, interval: 3, start: d(2026, 10, 29));
      expect(r.between(d(2026, 10, 29), d(2026, 11, 8)),
          [d(2026, 10, 29), d(2026, 11, 1), d(2026, 11, 4), d(2026, 11, 7)]);
    });

    test('firstOnOrAfter finds the exact next occurrence', () {
      final r = Recurrence(frequency: Frequency.monthly, interval: 1, start: d(2026, 1, 31));
      expect(r.firstOnOrAfter(d(2026, 2, 15)), d(2026, 2, 28));
      expect(r.firstOnOrAfter(d(2026, 2, 28)), d(2026, 2, 28));
      expect(r.firstAfter(d(2026, 2, 28)), d(2026, 3, 31));
      expect(r.firstOnOrAfter(d(2025, 1, 1)), d(2026, 1, 31));
    });

    test('end date stops the schedule', () {
      final r = Recurrence(frequency: Frequency.monthly, interval: 1, start: d(2026, 1, 5), end: d(2026, 3, 5));
      expect(r.between(d(2026, 1, 1), d(2026, 12, 31)), [d(2026, 1, 5), d(2026, 2, 5), d(2026, 3, 5)]);
      expect(r.firstAfter(d(2026, 3, 5)), isNull);
      // The stored next due date may pass the end; that marks the rule ended.
      expect(r.scheduledOnOrAfter(d(2026, 3, 6)), d(2026, 4, 5));
    });

    test('a quarterly schedule (every 3 months)', () {
      final r = Recurrence(frequency: Frequency.monthly, interval: 3, start: d(2026, 1, 10));
      expect(r.between(d(2026, 1, 1), d(2026, 12, 31)),
          [d(2026, 1, 10), d(2026, 4, 10), d(2026, 7, 10), d(2026, 10, 10)]);
    });

    test('rejects an interval below 1 and an end before the start', () {
      expect(() => Recurrence(frequency: Frequency.daily, interval: 0, start: d(2026, 1, 1)),
          throwsArgumentError);
      expect(() => Recurrence(frequency: Frequency.daily, interval: 1, start: d(2026, 1, 2), end: d(2026, 1, 1)),
          throwsArgumentError);
    });
  });

  group('BudgetLevel (§12.1)', () {
    BudgetLevel level(int spent, int amount, [int threshold = 80]) => BudgetLevel.of(
        spent: Money.fromTaka(spent), amount: Money.fromTaka(amount), warningThreshold: threshold);

    test('thresholds 80 / 100 / above 100', () {
      expect(level(2399, 3000), BudgetLevel.normal);
      expect(level(2400, 3000), BudgetLevel.warning);
      expect(level(2999, 3000), BudgetLevel.warning);
      expect(level(3000, 3000), BudgetLevel.reached);
      expect(level(3001, 3000), BudgetLevel.over);
    });

    test('custom warning threshold', () {
      expect(level(1400, 2000, 70), BudgetLevel.warning);
      expect(level(1399, 2000, 70), BudgetLevel.normal);
      // A 100% threshold warns only when the limit is reached.
      expect(level(1999, 2000, 100), BudgetLevel.normal);
    });

    test('integer comparison is exact at paisa level', () {
      expect(BudgetLevel.of(spent: const Money(239999), amount: Money.fromTaka(3000), warningThreshold: 80),
          BudgetLevel.normal);
      expect(BudgetLevel.of(spent: const Money(240000), amount: Money.fromTaka(3000), warningThreshold: 80),
          BudgetLevel.warning);
    });

    test('refunds larger than spending are normal', () {
      expect(level(-100, 3000), BudgetLevel.normal);
    });
  });
}
