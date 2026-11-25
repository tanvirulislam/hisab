import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/month_cycle.dart';

void main() {
  test('start day 1 is the calendar month', () {
    const c = MonthCycle();
    expect(c.isCalendar, isTrue);
    for (var m = 1; m <= 12; m++) {
      expect(c.rangeOf(2026, m), DateRange.month(2026, m));
    }
    expect(c.keyOf(LocalDate(2026, 11, 30)), LocalDate(2026, 11, 1));
    expect(c.containing(LocalDate(2024, 2, 29)), DateRange.month(2024, 2));
  });

  test('a cycle from the 20th runs to the 19th of the next month', () {
    const c = MonthCycle(20);
    expect(c.rangeOf(2026, 11), DateRange(LocalDate(2026, 11, 20), LocalDate(2026, 12, 19)));
    // Before the start day a date belongs to the previous month's cycle.
    expect(c.keyOf(LocalDate(2026, 11, 15)), LocalDate(2026, 10, 1));
    expect(c.containing(LocalDate(2026, 11, 15)), DateRange(LocalDate(2026, 10, 20), LocalDate(2026, 11, 19)));
    expect(c.keyOf(LocalDate(2026, 11, 19)), LocalDate(2026, 10, 1));
    expect(c.keyOf(LocalDate(2026, 11, 20)), LocalDate(2026, 11, 1));
  });

  test('cycles wrap the year and cover February', () {
    const c = MonthCycle(20);
    expect(c.keyOf(LocalDate(2026, 1, 5)), LocalDate(2025, 12, 1));
    expect(c.rangeOf(2025, 12), DateRange(LocalDate(2025, 12, 20), LocalDate(2026, 1, 19)));
    expect(c.rangeOf(2026, 1).end, LocalDate(2026, 2, 19));
    expect(const MonthCycle(28).rangeOf(2026, 2), DateRange(LocalDate(2026, 2, 28), LocalDate(2026, 3, 27)));
    expect(const MonthCycle(28).rangeOf(2024, 1), DateRange(LocalDate(2024, 1, 28), LocalDate(2024, 2, 27)));
  });

  test('consecutive cycles touch with no gap or overlap', () {
    for (final day in [1, 2, 15, 20, 28]) {
      final c = MonthCycle(day);
      var key = LocalDate(2025, 1, 1);
      for (var i = 0; i < 24; i++) {
        final next = key.addMonths(1);
        expect(c.rangeOfKey(key).end.addDays(1), c.rangeOfKey(next).start, reason: 'day $day, $key');
        key = next;
      }
    }
  });

  test('days left and progress run from the first to the last day', () {
    final range = const MonthCycle(25).rangeOf(2026, 11); // 25 Nov – 24 Dec
    expect(range.daysLeftAfter(range.start), 29);
    expect(range.daysLeftAfter(LocalDate(2026, 12, 6)), 18);
    expect(range.daysLeftAfter(range.end), 0);
    expect(range.progressAt(range.start), 0);
    expect(range.progressAt(LocalDate(2026, 12, 6)), closeTo(11 / 29, 1e-9));
    expect(range.progressAt(range.end), 1);
  });
}
