import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/month_cycle.dart';
import '../../../core/utils/week_start.dart';
import 'report_models.dart';

export '../../../core/utils/month_cycle.dart';
export '../../../core/utils/week_start.dart';

enum ReportPeriod { day, week, month }

/// Pure, integer-only report calculations (§11, rule 14).
abstract final class ReportMath {
  static DateRange weekContaining(LocalDate date, WeekStart start) {
    final back = (date.weekday - start.isoWeekday + 7) % 7;
    final first = date.addDays(-back);
    return DateRange(first, first.addDays(6));
  }

  static DateRange rangeFor(ReportPeriod period, LocalDate anchor, WeekStart weekStart,
          [MonthCycle cycle = const MonthCycle()]) =>
      switch (period) {
        ReportPeriod.day => DateRange.day(anchor),
        ReportPeriod.week => weekContaining(anchor, weekStart),
        ReportPeriod.month => cycle.containing(anchor),
      };

  /// Moves [anchor] by [steps] periods. A month step lands on the first day
  /// of the target month cycle (D15).
  static LocalDate shift(ReportPeriod period, LocalDate anchor, int steps,
          [MonthCycle cycle = const MonthCycle()]) =>
      switch (period) {
        ReportPeriod.day => anchor.addDays(steps),
        ReportPeriod.week => anchor.addDays(7 * steps),
        ReportPeriod.month => cycle.rangeOfKey(cycle.keyOf(anchor).addMonths(steps)).start,
      };

  /// One entry per day of [range], zero where nothing was recorded.
  static List<DailyAmount> fillDays(DateRange range, Iterable<DailyAmount> sparse) {
    final byDate = {for (final d in sparse) d.date: d};
    return [
      for (var d = range.start; !d.isAfter(range.end); d = d.addDays(1))
        byDate[d] ?? DailyAmount(date: d, income: Money.zero, expense: Money.zero),
    ];
  }

  /// One entry per month key from [first] to [last] (inclusive), zero-filled.
  static List<MonthAmount> fillMonths(LocalDate first, LocalDate last, Iterable<MonthAmount> sparse) {
    final byKey = {for (final m in sparse) m.year * 100 + m.month: m};
    final out = <MonthAmount>[];
    for (var d = first.firstOfMonth; !d.isAfter(last); d = d.addMonths(1)) {
      out.add(byKey[d.year * 100 + d.month] ??
          MonthAmount(year: d.year, month: d.month, income: Money.zero, expense: Money.zero));
    }
    return out;
  }

  /// The day with the largest net expense (earliest on ties), or null when
  /// nothing was spent.
  static DailyAmount? highestSpendingDay(Iterable<DailyAmount> days) {
    DailyAmount? best;
    for (final d in days) {
      if (d.expense.isPositive && (best == null || d.expense > best.expense)) best = d;
    }
    return best;
  }

  /// Days of [range] that have started by [today]: the whole range for a
  /// past period, the elapsed part of the current one, 0 for the future.
  static int elapsedDays(DateRange range, LocalDate today) {
    if (today.isBefore(range.start)) return 0;
    if (today.isAfter(range.end)) return range.lengthInDays;
    return DateRange(range.start, today).lengthInDays;
  }

  /// [total] / [days], rounded half away from zero to the nearest paisa.
  static Money average(Money total, int days) {
    if (days <= 0) return Money.zero;
    final p = total.paisa;
    final q = (p.abs() * 2 + days) ~/ (2 * days);
    return Money(p < 0 ? -q : q);
  }

  /// Percentage change from [previous] to [current], rounded to the nearest
  /// whole percent. Null when there is nothing to compare against.
  static int? percentChange(Money previous, Money current) {
    if (previous.paisa <= 0) return null;
    final diff = (current - previous).paisa;
    final q = (diff.abs() * 200 + previous.paisa) ~/ (2 * previous.paisa);
    return diff < 0 ? -q : q;
  }

  /// Whole-number shares of the positive [amounts] that add up to exactly 100
  /// (largest remainder method). Non-positive amounts get 0.
  static List<int> sharePercents(List<Money> amounts) {
    final positive = [for (final a in amounts) a.isPositive ? a.paisa : 0];
    final total = positive.fold<int>(0, (s, v) => s + v);
    if (total == 0) return List.filled(amounts.length, 0);
    final floors = [for (final v in positive) (v * 100) ~/ total];
    var left = 100 - floors.fold<int>(0, (s, v) => s + v);
    final order = List.generate(amounts.length, (i) => i)
      ..sort((a, b) {
        final ra = (positive[a] * 100) % total;
        final rb = (positive[b] * 100) % total;
        return rb != ra ? rb.compareTo(ra) : a.compareTo(b);
      });
    for (final i in order) {
      if (left == 0) break;
      if (positive[i] == 0) continue;
      floors[i]++;
      left--;
    }
    return floors;
  }
}
