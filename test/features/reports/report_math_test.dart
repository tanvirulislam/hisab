import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/reports/domain/report_math.dart';
import 'package:hisab/features/reports/domain/report_models.dart';

void main() {
  test('week ranges honour the configured first day', () {
    final sat21 = LocalDate(2026, 11, 21); // Saturday
    expect(ReportMath.weekContaining(sat21, WeekStart.saturday), DateRange(sat21, LocalDate(2026, 11, 27)));
    expect(ReportMath.weekContaining(sat21, WeekStart.sunday),
        DateRange(LocalDate(2026, 11, 15), LocalDate(2026, 11, 21)));
    expect(ReportMath.weekContaining(sat21, WeekStart.monday),
        DateRange(LocalDate(2026, 11, 16), LocalDate(2026, 11, 22)));
    // Every day of a week maps to the same range.
    for (var i = 0; i < 7; i++) {
      expect(ReportMath.weekContaining(sat21.addDays(i), WeekStart.saturday).start, sat21);
    }
  });

  test('period ranges and shifting', () {
    final d = LocalDate(2026, 1, 31);
    expect(ReportMath.rangeFor(ReportPeriod.month, d, WeekStart.saturday), DateRange.month(2026, 1));
    expect(ReportMath.shift(ReportPeriod.month, d, 1), LocalDate(2026, 2, 1));
    expect(ReportMath.shift(ReportPeriod.month, d, -1), LocalDate(2025, 12, 1));
    expect(ReportMath.shift(ReportPeriod.week, d, 1), LocalDate(2026, 2, 7));
    expect(ReportMath.shift(ReportPeriod.day, d, 1), LocalDate(2026, 2, 1));
  });

  test('month periods follow the month start day (D15)', () {
    const c = MonthCycle(20);
    final d = LocalDate(2026, 11, 21);
    expect(ReportMath.rangeFor(ReportPeriod.month, d, WeekStart.saturday, c),
        DateRange(LocalDate(2026, 11, 20), LocalDate(2026, 12, 19)));
    expect(ReportMath.rangeFor(ReportPeriod.month, LocalDate(2026, 11, 5), WeekStart.saturday, c).start,
        LocalDate(2026, 10, 20));
    expect(ReportMath.shift(ReportPeriod.month, d, -1, c), LocalDate(2026, 10, 20));
    expect(ReportMath.shift(ReportPeriod.month, LocalDate(2026, 1, 5), 1, c), LocalDate(2026, 1, 20));
  });

  test('fillDays zero-fills every day of the range', () {
    final range = DateRange(LocalDate(2026, 11, 1), LocalDate(2026, 11, 3));
    final days = ReportMath.fillDays(range, [
      DailyAmount(date: LocalDate(2026, 11, 2), income: Money.zero, expense: const Money(500)),
    ]);
    expect(days.map((d) => d.expense.paisa), [0, 500, 0]);
  });

  test('highest spending day picks the earliest on ties and ignores zero days', () {
    DailyAmount day(int d, int paisa) =>
        DailyAmount(date: LocalDate(2026, 11, d), income: Money.zero, expense: Money(paisa));
    expect(ReportMath.highestSpendingDay([day(1, 100), day(2, 300), day(3, 300)])!.date.day, 2);
    expect(ReportMath.highestSpendingDay([day(1, 0)]), isNull);
  });

  test('elapsed days and rounded averages', () {
    final nov = DateRange.month(2026, 11);
    expect(ReportMath.elapsedDays(nov, LocalDate(2026, 11, 21)), 21);
    expect(ReportMath.elapsedDays(nov, LocalDate(2026, 12, 5)), 30);
    expect(ReportMath.elapsedDays(nov, LocalDate(2026, 10, 5)), 0);
    expect(ReportMath.average(const Money(1000), 3), const Money(333));
    expect(ReportMath.average(const Money(1001), 2), const Money(501)); // 500.5 rounds up
    expect(ReportMath.average(const Money(-1001), 2), const Money(-501));
    expect(ReportMath.average(const Money(1000), 0), Money.zero);
  });

  test('percent change', () {
    expect(ReportMath.percentChange(const Money(1000), const Money(1120)), 12);
    expect(ReportMath.percentChange(const Money(1000), const Money(880)), -12);
    expect(ReportMath.percentChange(const Money(3), const Money(4)), 33);
    expect(ReportMath.percentChange(Money.zero, const Money(100)), isNull);
  });

  test('shares always add up to 100 and ignore non-positive amounts', () {
    List<int> s(List<int> p) => ReportMath.sharePercents([for (final v in p) Money(v)]);
    expect(s([1, 1, 1]), [34, 33, 33]);
    expect(s([600000, 350000, 250000, 150000, 250000, 250000]).reduce((a, b) => a + b), 100);
    expect(s([500, -100, 500]), [50, 0, 50]);
    expect(s([0, 0]), [0, 0]);
    expect(s([7]), [100]);
  });
}
