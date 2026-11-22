import '../../../core/utils/local_date.dart';
import '../../../core/utils/month_cycle.dart';
import '../../../core/utils/money.dart';
import '../../budgets/domain/budget.dart';

enum NoticeKind { dailyReminder, monthlySummary, recurringUpcoming }

/// A notification to schedule. Text is added by the caller in the user's
/// language, so this stays pure and testable.
class PlannedNotice {
  const PlannedNotice({required this.id, required this.kind, required this.at, required this.payload, this.rule});

  final int id;
  final NoticeKind kind;
  final DateTime at;
  final String payload;

  /// For [NoticeKind.recurringUpcoming].
  final UpcomingRule? rule;

  /// Identity of the schedule, used to skip rescheduling when nothing changed.
  String get signature => '$id@${at.millisecondsSinceEpoch}:$payload:${rule?.signature ?? ''}';
}

class UpcomingRule {
  const UpcomingRule({required this.ruleId, required this.dueDate, required this.title, required this.amount});

  final String ruleId;
  final LocalDate dueDate;
  final String title;
  final Money amount;

  String get signature => '$ruleId:$dueDate:$title:${amount.paisa}';
}

/// Notification IDs are fixed per slot, so rescheduling replaces rather
/// than duplicates.
abstract final class NoticeIds {
  static const int reminderBase = 1000;
  static const int reminderDays = 14;
  static const int monthlySummary = 2000;
  static const int recurringBase = 3000;
  static const int recurringMax = 50;
  static const int budgetBase = 100000;

  /// Every scheduled slot, for cancelling a previous plan.
  static Iterable<int> get scheduledSlots sync* {
    for (var i = 0; i < reminderDays; i++) {
      yield reminderBase + i;
    }
    yield monthlySummary;
    for (var i = 0; i < recurringMax; i++) {
      yield recurringBase + i;
    }
  }

  /// Stable per budget (FNV-1a), so a newer alert replaces an older one.
  static int budget(String budgetId) {
    var h = 0x811c9dc5;
    for (final c in budgetId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return budgetBase + h % 900000;
  }
}

/// Payloads say where a tapped notification leads.
abstract final class NoticePayload {
  static const String addEntry = 'route:/add';
  static const String budgets = 'route:/more/budgets';
  static const String recurring = 'route:/more/recurring';

  /// Opens the monthly report of the cycle whose key is [month].
  static String summary(LocalDate month) => 'summary:${month.year * 100 + month.month}';
}

/// Plans scheduled notifications (§15) from the current state.
///
/// - Daily reminder: one per day for the next [NoticeIds.reminderDays] days
///   at the chosen time. Today's is dropped once something was recorded
///   today, so it only nudges about missing entries. If the app is not
///   opened for two weeks the reminders stop rather than nag forever.
/// - Monthly summary: the first day of the next month cycle (the 1st, or the
///   chosen month start day, D15), pointing at the cycle that just ended.
/// - Upcoming recurring: the day before each due occurrence.
abstract final class NotificationPlanner {
  static List<PlannedNotice> plan({
    required DateTime now,
    required bool reminderEnabled,
    required int reminderMinutes,
    required bool recordedToday,
    required bool monthlySummary,
    required bool recurringAlerts,
    required List<UpcomingRule> upcoming,
    MonthCycle cycle = const MonthCycle(),
  }) {
    final today = LocalDate.fromDateTime(now);
    DateTime at(LocalDate d) => DateTime(d.year, d.month, d.day, reminderMinutes ~/ 60, reminderMinutes % 60);
    final notices = <PlannedNotice>[];

    if (reminderEnabled) {
      for (var i = 0; i < NoticeIds.reminderDays; i++) {
        if (i == 0 && recordedToday) continue;
        final when = at(today.addDays(i));
        if (!when.isAfter(now)) continue;
        notices.add(PlannedNotice(
            id: NoticeIds.reminderBase + i, kind: NoticeKind.dailyReminder, at: when, payload: NoticePayload.addEntry));
      }
    }

    if (monthlySummary) {
      var key = cycle.keyOf(today);
      if (!at(cycle.rangeOfKey(key).start).isAfter(now)) key = key.addMonths(1);
      notices.add(PlannedNotice(
        id: NoticeIds.monthlySummary,
        kind: NoticeKind.monthlySummary,
        at: at(cycle.rangeOfKey(key).start),
        payload: NoticePayload.summary(key.addMonths(-1)),
      ));
    }

    if (recurringAlerts) {
      final horizon = today.addDays(NoticeIds.reminderDays);
      final soon = upcoming
          .where((r) => r.dueDate.isAfter(today) && !r.dueDate.isAfter(horizon))
          .map((r) => (r, at(r.dueDate.addDays(-1))))
          .where((e) => e.$2.isAfter(now))
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (i, (rule, time)) in soon.take(NoticeIds.recurringMax).indexed) {
        notices.add(PlannedNotice(
          id: NoticeIds.recurringBase + i,
          kind: NoticeKind.recurringUpcoming,
          at: time,
          payload: NoticePayload.recurring,
          rule: rule,
        ));
      }
    }
    return notices;
  }
}

/// A budget that just got worse and should be announced.
class BudgetAlert {
  const BudgetAlert(this.status, this.level);

  final BudgetStatus status;
  final BudgetLevel level;
}

/// Decides budget notifications (§12.1). Each budget is announced once per
/// level it reaches (warning → reached → over). If spending drops again
/// (refund, deletion, larger budget), the stored level drops too, so a
/// later rise is announced again.
abstract final class BudgetAlertPolicy {
  static ({List<BudgetAlert> alerts, Map<String, int> levels}) evaluate(
    List<BudgetStatus> statuses,
    Map<String, int> announced,
  ) {
    final alerts = <BudgetAlert>[];
    final levels = <String, int>{};
    for (final s in statuses) {
      final level = s.level;
      final previous = announced[s.budget.id] ?? BudgetLevel.normal.index;
      if (level.index > previous) alerts.add(BudgetAlert(s, level));
      levels[s.budget.id] = level.index;
    }
    return (alerts: alerts, levels: levels);
  }
}
