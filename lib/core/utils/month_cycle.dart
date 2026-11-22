import 'local_date.dart';

/// A "month" that starts on a chosen day (e.g. salary day), D15.
///
/// Each cycle is identified by the first day of the calendar month it starts
/// in: with [startDay] 20, the November cycle runs 20 Nov – 19 Dec. With
/// [startDay] 1 every cycle is exactly a calendar month.
final class MonthCycle {
  const MonthCycle([this.startDay = 1])
      : assert(startDay >= minDay && startDay <= maxDay);

  static const int minDay = 1;

  /// Kept at 28 so every month has the start day (no February clamping).
  static const int maxDay = 28;

  /// Day of the month a cycle starts on, [minDay]..[maxDay].
  final int startDay;

  bool get isCalendar => startDay == 1;

  /// The key (first of the start month) of the cycle that contains [d].
  LocalDate keyOf(LocalDate d) {
    final first = d.firstOfMonth;
    return d.day >= startDay ? first : first.addMonths(-1);
  }

  /// The cycle that starts in [year]/[month].
  DateRange rangeOf(int year, int month) {
    final start = LocalDate(year, month, startDay);
    return DateRange(start, start.addMonths(1).addDays(-1));
  }

  /// The cycle whose key is [key] (any date in the key month works).
  DateRange rangeOfKey(LocalDate key) => rangeOf(key.year, key.month);

  /// The cycle that contains [d].
  DateRange containing(LocalDate d) => rangeOfKey(keyOf(d));

  /// SQL expression giving the cycle key as `yyyymm` for a `local_date`
  /// (yyyymmdd) column. Bind [startDay] to its single `?`.
  static String sqlKey(String column) =>
      'CASE WHEN $column % 100 >= ? THEN $column / 100 '
      'WHEN ($column / 100) % 100 = 1 THEN $column / 100 - 89 '
      'ELSE $column / 100 - 1 END';

  @override
  bool operator ==(Object other) => other is MonthCycle && other.startDay == startDay;

  @override
  int get hashCode => startDay;

  @override
  String toString() => 'MonthCycle($startDay)';
}
