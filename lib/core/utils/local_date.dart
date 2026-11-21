/// A calendar date with no time or timezone, stored as an `yyyymmdd`
/// integer (e.g. 20261121).
///
/// Reports, grouping and month boundaries use this value, never
/// `created_at`, so they stay correct whatever the device timezone is.
final class LocalDate implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
      throw ArgumentError('Invalid date: $year-$month-$day');
    }
  }

  factory LocalDate.fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  /// Parses an `yyyymmdd` integer as stored in the database.
  factory LocalDate.fromInt(int value) =>
      LocalDate(value ~/ 10000, (value ~/ 100) % 100, value % 100);

  final int year;
  final int month;
  final int day;

  int toInt() => year * 10000 + month * 100 + day;

  /// Local midnight at the start of this date.
  DateTime toDateTime() => DateTime(year, month, day);

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(DateTime(year, month, day + days));

  LocalDate get firstOfMonth => LocalDate(year, month, 1);
  LocalDate get lastOfMonth => LocalDate(year, month, daysInMonth(year, month));

  /// Same day-of-month in another month, clamped to that month's length
  /// (Jan 31 + 1 month → Feb 28/29).
  LocalDate addMonths(int months) {
    final total = year * 12 + (month - 1) + months;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final d = day > daysInMonth(y, m) ? daysInMonth(y, m) : day;
    return LocalDate(y, m, d);
  }

  /// ISO weekday: Monday = 1 … Sunday = 7.
  int get weekday => toDateTime().weekday;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  @override
  int compareTo(LocalDate other) => toInt().compareTo(other.toInt());

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.toInt() == toInt();

  @override
  int get hashCode => toInt();

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// An inclusive range of calendar dates.
final class DateRange {
  DateRange(this.start, this.end) {
    if (end.isBefore(start)) {
      throw ArgumentError('DateRange end $end is before start $start');
    }
  }

  factory DateRange.month(int year, int month) {
    final first = LocalDate(year, month, 1);
    return DateRange(first, first.lastOfMonth);
  }

  factory DateRange.day(LocalDate date) => DateRange(date, date);

  final LocalDate start;
  final LocalDate end;

  bool contains(LocalDate date) => !date.isBefore(start) && !date.isAfter(end);

  int get lengthInDays =>
      end.toDateTime().difference(start.toDateTime()).inDays + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}
