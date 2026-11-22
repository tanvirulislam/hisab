import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/providers.dart';
import '../../../core/services/local_prefs.dart';
import '../../../core/services/today_provider.dart';
import '../../../core/utils/bn_digits.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/presentation/budget_providers.dart';
import '../../recurring/domain/recurring_rule.dart';
import '../../recurring/presentation/recurring_providers.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/notification_plan.dart';

part 'notification_coordinator.g.dart';

/// Whether anything was recorded since [epochMillis] (start of today).
@riverpod
Stream<bool> recordedSince(Ref ref, int epochMillis) =>
    ref.watch(appDatabaseProvider).transactionsDao.watchAnyCreatedSince(epochMillis);

class NotificationInputs {
  const NotificationInputs({required this.settings, required this.today, required this.recordedToday, required this.rules});

  final AppSettings settings;
  final LocalDate today;
  final bool recordedToday;
  final List<RecurringRuleItem> rules;
}

@Riverpod(keepAlive: true)
NotificationInputs? notificationInputs(Ref ref) {
  final settings = ref.watch(appSettingsProvider).value;
  final today = ref.currentDate();
  final recorded = ref.watch(recordedSinceProvider(today.toDateTime().millisecondsSinceEpoch)).value;
  final rules = ref.watch(allRecurringRulesProvider).value;
  if (settings == null || recorded == null || rules == null) return null;
  return NotificationInputs(settings: settings, today: today, recordedToday: recorded, rules: rules);
}

/// Keeps device notifications in line with the data (§15, §12.1):
/// reschedules reminders when settings, today's entries or recurring rules
/// change, and announces budgets crossing a threshold. Work is queued so
/// platform calls never interleave.
@Riverpod(keepAlive: true)
class NotificationCoordinator extends _$NotificationCoordinator {
  Future<void> _queue = Future.value();
  String? _signature;
  Set<int>? _scheduled;

  NotificationService get _service => ref.read(notificationServiceProvider);

  @override
  void build() {
    ref.listen(notificationInputsProvider, (_, next) {
      if (next != null) _enqueue(() => _reschedule(next));
    }, fireImmediately: true);
    ref.listen(allCurrentBudgetStatusesProvider, (_, next) {
      final statuses = next.value;
      if (statuses != null) _enqueue(() => _budgetAlerts(statuses));
    }, fireImmediately: true);
  }

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((Object e, StackTrace st) {
      debugPrint('Notification update failed: $e\n$st');
    });
  }

  /// Completes when queued work is done (tests).
  @visibleForTesting
  Future<void> get idle => _queue;

  AppLocalizations _l10n(AppSettings s) => lookupAppLocalizations(Locale(s.language.code));

  MoneyFormatter _money(AppSettings s) => MoneyFormatter(banglaDigits: s.useBanglaDigits);

  String _digits(AppSettings s, String text) => s.useBanglaDigits ? BnDigits.toBangla(text) : text;

  // ----------------------------------------------------------- schedule

  Future<void> _reschedule(NotificationInputs input) async {
    final s = input.settings;
    final l = _l10n(s);
    final lang = s.language.code;
    final plan = NotificationPlanner.plan(
      now: ref.read(clockProvider).now(),
      reminderEnabled: s.reminderEnabled,
      reminderMinutes: s.reminderMinutes,
      recordedToday: input.recordedToday,
      monthlySummary: s.monthlySummary,
      recurringAlerts: s.recurringAlerts,
      upcoming: [
        for (final item in input.rules)
          if (!item.rule.isPaused && !item.rule.hasEnded)
            UpcomingRule(
              ruleId: item.rule.id,
              dueDate: item.rule.nextDueDate,
              title: item.rule.description ??
                  (item.subcategory ?? item.category)?.displayName(lang) ??
                  l.entryTransfer,
              amount: item.rule.amount,
            ),
      ],
    );
    final signature = '$lang|${s.useBanglaDigits}|${plan.map((n) => n.signature).join('|')}';
    if (signature == _signature) return;

    // The first run also clears whatever a previous process scheduled.
    final ids = {for (final n in plan) n.id};
    for (final id in (_scheduled ?? NoticeIds.scheduledSlots.toSet()).difference(ids)) {
      await _service.cancel(id);
    }
    final reminders = NoticeChannel('reminders', l.channelReminders);
    for (final n in plan) {
      final (channel, title, body) = switch (n.kind) {
        NoticeKind.dailyReminder => (reminders, l.reminderNoticeTitle, l.reminderNoticeBody),
        NoticeKind.monthlySummary => (reminders, l.summaryNoticeTitle(_monthName(s, n.payload)), l.summaryNoticeBody),
        NoticeKind.recurringUpcoming => (
          NoticeChannel('recurring', l.channelRecurring),
          l.recurringNoticeTitle(n.rule!.title, _money(s).format(n.rule!.amount)),
          l.recurringNoticeBody,
        ),
      };
      await _service.schedule(id: n.id, channel: channel, at: n.at, title: title, body: body, payload: n.payload);
    }
    _scheduled = ids;
    _signature = signature;
  }

  String _monthName(AppSettings s, String summaryPayload) {
    final ym = int.parse(summaryPayload.split(':').last);
    final date = DateTime(ym ~/ 100, ym % 100);
    try {
      return _digits(s, DateFormat.yMMMM(s.language.code).format(date));
    } on Object {
      return _digits(s, '${date.month}/${date.year}'); // date symbols not loaded yet
    }
  }

  // ------------------------------------------------------- budget alerts

  Future<void> _budgetAlerts(List<BudgetStatus> statuses) async {
    final prefs = ref.read(localPrefsProvider);
    Map<String, int> announced;
    try {
      announced = (jsonDecode(prefs.getString(LocalPrefKeys.budgetAlertLevels) ?? '{}') as Map)
          .map((k, v) => MapEntry(k as String, v as int));
    } on Object {
      announced = {};
    }
    final result = BudgetAlertPolicy.evaluate(statuses, announced);
    await prefs.setString(LocalPrefKeys.budgetAlertLevels, jsonEncode(result.levels));

    final s = ref.read(appSettingsProvider).value ?? const AppSettings();
    if (!s.budgetAlerts || result.alerts.isEmpty) return;
    final l = _l10n(s);
    final money = _money(s);
    final channel = NoticeChannel('budgets', l.channelBudgets);
    for (final a in result.alerts) {
      final st = a.status;
      final name = st.category.displayName(s.language.code);
      final amount = money.format(st.budget.amount);
      final (title, body) = switch (a.level) {
        BudgetLevel.warning => (
          l.budgetAlertWarningTitle(name),
          l.budgetAlertWarningBody(_digits(s, '${st.percent}'), amount, money.format(st.remaining)),
        ),
        BudgetLevel.reached => (l.budgetAlertReachedTitle(name), l.budgetAlertReachedBody(amount)),
        BudgetLevel.over || BudgetLevel.normal => (
          l.budgetAlertOverTitle(name),
          l.budgetAlertOverBody(money.format(st.spent), amount, money.format(-st.remaining)),
        ),
      };
      await _service.show(
        id: NoticeIds.budget(st.budget.id),
        channel: channel,
        title: title,
        body: body,
        payload: NoticePayload.budgets,
      );
    }
  }
}
