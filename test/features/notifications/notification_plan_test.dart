import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/core/utils/month_cycle.dart';
import 'package:hisab/features/budgets/domain/budget.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/notifications/domain/notification_plan.dart';
import 'package:hisab/features/workspaces/domain/workspace.dart';

void main() {
  final now = DateTime(2026, 11, 21, 10); // reminder at 21:00 is still ahead
  List<PlannedNotice> plan({
    DateTime? at,
    bool reminder = true,
    bool recordedToday = false,
    bool summary = false,
    MonthCycle cycle = const MonthCycle(),
  }) => NotificationPlanner.plan(
    cycle: cycle,
    now: at ?? now,
    reminderEnabled: reminder,
    reminderMinutes: 21 * 60,
    recordedToday: recordedToday,
    monthlySummary: summary,
  );

  group('daily reminder', () {
    test('two weeks of reminders at the chosen time', () {
      final r = plan();
      expect(r, hasLength(NoticeIds.reminderDays));
      expect(r.first.at, DateTime(2026, 11, 21, 21));
      expect(r.last.at, DateTime(2026, 12, 4, 21));
      expect(r.map((n) => n.id).toSet(), hasLength(NoticeIds.reminderDays));
      expect(r.every((n) => n.payload == NoticePayload.addEntry), isTrue);
    });

    test("today's reminder is dropped once something was recorded", () {
      final r = plan(recordedToday: true);
      expect(r.first.at, DateTime(2026, 11, 22, 21));
      expect(r, hasLength(NoticeIds.reminderDays - 1));
    });

    test('a time already passed today starts tomorrow', () {
      expect(plan(at: DateTime(2026, 11, 21, 22)).first.at, DateTime(2026, 11, 22, 21));
    });

    test('off means none', () => expect(plan(reminder: false), isEmpty));
  });

  test('monthly summary on the 1st points at last month', () {
    final s = plan(reminder: false, summary: true).single;
    expect(s.at, DateTime(2026, 12, 1, 21));
    expect(s.payload, 'summary:202611');
    // On the 1st before the time, it is today, about the month just ended.
    final first = plan(at: DateTime(2026, 12, 1, 8), reminder: false, summary: true).single;
    expect((first.at, first.payload), (DateTime(2026, 12, 1, 21), 'summary:202611'));
  });

  test('monthly summary follows the month start day (D15)', () {
    const c = MonthCycle(20);
    // 21 Nov: the November cycle just started, so the next summary is 20 Dec.
    final s = plan(reminder: false, summary: true, cycle: c).single;
    expect((s.at, s.payload), (DateTime(2026, 12, 20, 21), 'summary:202611'));
    // 15 Nov: the October cycle ends on the 19th; its summary comes on the 20th.
    final mid = plan(at: DateTime(2026, 11, 15, 8), reminder: false, summary: true, cycle: c).single;
    expect((mid.at, mid.payload), (DateTime(2026, 11, 20, 21), 'summary:202610'));
  });

  test('slots of the removed recurring reminders are still cancelled', () {
    expect(NoticeIds.scheduledSlots, contains(NoticeIds.legacyRecurringBase));
    expect(NoticeIds.scheduledSlots, contains(NoticeIds.legacyRecurringBase + NoticeIds.legacyRecurringCount - 1));
  });

  test('budget notification IDs are stable and stay out of scheduled slots', () {
    expect(NoticeIds.budget('abc'), NoticeIds.budget('abc'));
    expect(NoticeIds.budget('abc'), isNot(NoticeIds.budget('abd')));
    expect(NoticeIds.budget('x'), greaterThanOrEqualTo(NoticeIds.budgetBase));
    expect(NoticeIds.scheduledSlots, isNot(contains(NoticeIds.budget('x'))));
  });

  group('BudgetAlertPolicy', () {
    BudgetStatus status(String id, int spent) => BudgetStatus(
      budget: Budget(
          id: id, workspaceId: 'w', categoryId: 'c', amount: Money.fromTaka(1000), year: 2026, month: 11,
          warningThreshold: 80),
      category: const Category(
          id: 'c', type: CategoryType.expense, name: 'Grocery', iconKey: 'x', color: 0, isDefault: true,
          isActive: true, sortOrder: 0),
      workspaceType: WorkspaceType.personal,
      spent: Money.fromTaka(spent),
    );

    test('announces each level once, in order', () {
      var levels = <String, int>{};
      List<BudgetLevel> step(int spent) {
        final r = BudgetAlertPolicy.evaluate([status('b', spent)], levels);
        levels = r.levels;
        return r.alerts.map((a) => a.level).toList();
      }

      expect(step(500), isEmpty);
      expect(step(850), [BudgetLevel.warning]);
      expect(step(900), isEmpty); // still warning
      expect(step(1000), [BudgetLevel.reached]);
      expect(step(1200), [BudgetLevel.over]);
      expect(step(1300), isEmpty);
    });

    test('jumping straight over the limit announces once, at the worst level', () {
      final r = BudgetAlertPolicy.evaluate([status('b', 1500)], const {});
      expect(r.alerts.map((a) => a.level), [BudgetLevel.over]);
    });

    test('dropping back re-arms the alert', () {
      var levels = BudgetAlertPolicy.evaluate([status('b', 900)], const {}).levels;
      levels = BudgetAlertPolicy.evaluate([status('b', 100)], levels).levels; // refund
      expect(BudgetAlertPolicy.evaluate([status('b', 850)], levels).alerts, hasLength(1));
    });

    test('budgets that disappear are forgotten', () {
      final r = BudgetAlertPolicy.evaluate([status('a', 0)], {'gone': 3});
      expect(r.levels.keys, ['a']);
    });
  });
}
