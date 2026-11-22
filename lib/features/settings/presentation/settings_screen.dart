import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/utils/month_cycle.dart';
import '../../../core/utils/week_start.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../domain/app_settings.dart';
import 'app_formats.dart';
import 'settings_providers.dart';

/// A known date for each week start, used only to get its localized name.
final _sampleDay = {
  WeekStart.saturday: DateTime(2026, 11, 21),
  WeekStart.sunday: DateTime(2026, 11, 22),
  WeekStart.monday: DateTime(2026, 11, 23),
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreSettings)),
      body: AsyncValueView(
        value: ref.watch(appSettingsProvider),
        onRetry: () => ref.invalidate(appSettingsProvider),
        data: (settings) => ListView(
          children: [
            _SectionHeader(l10n.settingsLanguage),
            RadioGroup<AppLanguage>(
              groupValue: settings.language,
              onChanged: (v) => v == null ? null : repo.setLanguage(v),
              child: Column(
                children: [
                  RadioListTile(value: AppLanguage.bangla, title: Text(l10n.languageBangla)),
                  RadioListTile(value: AppLanguage.english, title: Text(l10n.languageEnglish)),
                ],
              ),
            ),
            SwitchListTile(
              value: settings.banglaDigits,
              onChanged: settings.language == AppLanguage.bangla
                  ? repo.setBanglaDigits
                  : null,
              title: Text(l10n.settingsBanglaDigits),
              subtitle: Text(l10n.settingsBanglaDigitsHint),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsWeekStart),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<WeekStart>(
                showSelectedIcon: false,
                segments: [
                  for (final w in WeekStart.values)
                    ButtonSegment(
                      value: w,
                      label: Text(DateFormat.EEEE(settings.language.code).format(_sampleDay[w]!)),
                    ),
                ],
                selected: {settings.weekStart},
                onSelectionChanged: (s) => repo.setWeekStart(s.first),
              ),
            ),
            _MonthStartTile(settings: settings),
            const Divider(),
            _SectionHeader(l10n.settingsTheme),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<AppThemePreference>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppThemePreference.system,
                    label: Text(l10n.themeSystem),
                    icon: const Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.light,
                    label: Text(l10n.themeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemePreference.dark,
                    label: Text(l10n.themeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.theme},
                onSelectionChanged: (s) => repo.setTheme(s.first),
              ),
            ),
            const Divider(),
            _SectionHeader(l10n.settingsNotifications),
            _NotificationSettings(settings: settings),
            const Divider(),
            _SectionHeader(l10n.moreBudgets),
            ListTile(
              title: Text(l10n.settingsBudgetDefault),
              subtitle: Text(l10n.settingsBudgetDefaultHint),
              trailing: Text('${ref.watch(appFormatsProvider).integer(settings.budgetWarningDefault)}%',
                  style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final f = ref.read(appFormatsProvider);
                final picked = await showDialog<int>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text(l10n.settingsBudgetDefault),
                    children: [
                      RadioGroup<int>(
                        groupValue: settings.budgetWarningDefault,
                        onChanged: (v) => Navigator.of(context).pop(v),
                        child: Column(
                          children: [
                            for (final p in const [50, 60, 70, 75, 80, 85, 90, 95, 100])
                              RadioListTile<int>(value: p, title: Text('${f.integer(p)}%')),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
                if (picked != null) await repo.setBudgetWarningDefault(picked);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Day of the month a "month" starts on, e.g. salary day (D15).
class _MonthStartTile extends ConsumerWidget {
  const _MonthStartTile({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final day = settings.monthStartDay;
    return ListTile(
      title: Text(l10n.settingsMonthStart),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day == 1 ? l10n.settingsMonthStartCalendar : l10n.settingsMonthStartDay(f.integer(day)),
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
          ),
          Text(l10n.settingsMonthStartHint),
        ],
      ),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.settingsMonthStart),
            content: SizedBox(
              width: 320,
              child: GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (var d = MonthCycle.minDay; d <= MonthCycle.maxDay; d++)
                    d == day
                        ? IconButton.filled(onPressed: () => Navigator.of(context).pop(d), icon: Text(f.integer(d)))
                        : IconButton(onPressed: () => Navigator.of(context).pop(d), icon: Text(f.integer(d))),
                ],
              ),
            ),
          ),
        );
        if (picked != null && picked != day) {
          await ref.read(settingsRepositoryProvider).setMonthStartDay(picked);
        }
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.secondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Daily reminder, budget alerts, upcoming recurring and monthly summary
/// (§15). Turning one on asks for the notification permission.
class _NotificationSettings extends ConsumerWidget {
  const _NotificationSettings({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final f = ref.watch(appFormatsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final minutes = settings.reminderMinutes;
    final time = f.time(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));

    Future<void> toggle(bool on, Future<void> Function(bool) save) async {
      if (on) {
        final allowed = await ref.read(notificationServiceProvider).requestPermission();
        if (!allowed) {
          if (context.mounted) showSnack(context, l.notificationsBlocked);
          return;
        }
      }
      await save(on);
    }

    return Column(
      children: [
        SwitchListTile(
          value: settings.reminderEnabled,
          onChanged: (v) => toggle(v, repo.setReminderEnabled),
          title: Text(l.settingsDailyReminder),
          subtitle: Text(l.settingsDailyReminderHint),
        ),
        ListTile(
          enabled: settings.reminderEnabled,
          title: Text(l.settingsReminderTime),
          trailing: Text(time, style: Theme.of(context).textTheme.titleMedium),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
            );
            if (picked != null) await repo.setReminderMinutes(picked.hour * 60 + picked.minute);
          },
        ),
        SwitchListTile(
          value: settings.budgetAlerts,
          onChanged: (v) => toggle(v, repo.setBudgetAlerts),
          title: Text(l.settingsBudgetAlerts),
          subtitle: Text(l.settingsBudgetAlertsHint),
        ),
        SwitchListTile(
          value: settings.recurringAlerts,
          onChanged: (v) => toggle(v, repo.setRecurringAlerts),
          title: Text(l.settingsRecurringAlerts),
          subtitle: Text(l.settingsRecurringAlertsHint),
        ),
        SwitchListTile(
          value: settings.monthlySummary,
          onChanged: (v) => toggle(v, repo.setMonthlySummary),
          title: Text(l.settingsMonthlySummary),
          subtitle: Text(l.settingsMonthlySummaryHint),
        ),
      ],
    );
  }
}
