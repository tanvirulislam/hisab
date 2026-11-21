import '../../../core/utils/local_date.dart';

enum Frequency {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const Frequency(this.dbValue);

  final String dbValue;

  static Frequency fromDb(String value) => values.firstWhere((f) => f.dbValue == value,
      orElse: () => throw ArgumentError('Unknown frequency: $value'));
}

/// A schedule: every [interval] × [frequency], anchored on [start]
/// (§14: daily, weekly, monthly, custom = any interval).
///
/// Occurrence n is computed from [start], never from the previous
/// occurrence, so a rule that starts on the 31st falls on the last day of
/// short months and returns to the 31st afterwards (Jan 31 → Feb 28 → Mar 31).
class Recurrence {
  Recurrence({required this.frequency, required this.interval, required this.start, this.end}) {
    if (interval < 1) throw ArgumentError.value(interval, 'interval');
    if (end != null && end!.isBefore(start)) throw ArgumentError('end before start');
  }

  final Frequency frequency;
  final int interval;
  final LocalDate start;

  /// Last day an occurrence may fall on (inclusive). NULL = no end.
  final LocalDate? end;

  /// The [n]th occurrence (0 = [start]), ignoring [end].
  LocalDate occurrence(int n) => switch (frequency) {
    Frequency.daily => start.addDays(n * interval),
    Frequency.weekly => start.addDays(n * interval * 7),
    Frequency.monthly => start.addMonths(n * interval),
    Frequency.yearly => start.addMonths(n * interval * 12),
  };

  /// First occurrence on or after [date], or null once the schedule ended.
  LocalDate? firstOnOrAfter(LocalDate date) => _withinEnd(scheduledOnOrAfter(date));

  /// First occurrence strictly after [date].
  LocalDate? firstAfter(LocalDate date) => firstOnOrAfter(date.addDays(1));

  /// Like [firstOnOrAfter] but ignoring [end]. A rule stores this as its
  /// next due date, so a date past [end] marks the rule as ended.
  LocalDate scheduledOnOrAfter(LocalDate date) {
    if (!date.isAfter(start)) return start;
    // Estimate the index from the distance, then step forward. The estimate
    // never overshoots, because it rounds down.
    final n0 = switch (frequency) {
      Frequency.daily => _daysBetween(start, date) ~/ interval,
      Frequency.weekly => _daysBetween(start, date) ~/ (7 * interval),
      Frequency.monthly => _monthsBetween(start, date) ~/ interval,
      Frequency.yearly => _monthsBetween(start, date) ~/ (12 * interval),
    };
    var n = n0 > 0 ? n0 - 1 : 0;
    while (occurrence(n).isBefore(date)) {
      n++;
    }
    return occurrence(n);
  }

  /// Every occurrence in [from]..[to] (inclusive), oldest first.
  List<LocalDate> between(LocalDate from, LocalDate to) {
    final result = <LocalDate>[];
    var next = firstOnOrAfter(from);
    while (next != null && !next.isAfter(to)) {
      result.add(next);
      next = firstAfter(next);
    }
    return result;
  }

  LocalDate? _withinEnd(LocalDate d) => end != null && d.isAfter(end!) ? null : d;

  static int _daysBetween(LocalDate a, LocalDate b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static int _monthsBetween(LocalDate a, LocalDate b) =>
      (b.year * 12 + b.month) - (a.year * 12 + a.month);
}
