import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/month_cycle.dart';
import '../../../core/utils/week_start.dart';

part 'app_settings.freezed.dart';

enum AppLanguage {
  bangla('bn'),
  english('en');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage parse(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.bangla);
}

enum AppThemePreference {
  system,
  light,
  dark;

  static AppThemePreference parse(String? value) => values.firstWhere(
    (t) => t.name == value,
    orElse: () => AppThemePreference.system,
  );
}

@freezed
abstract class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    @Default(AppLanguage.bangla) AppLanguage language,
    @Default(AppThemePreference.system) AppThemePreference theme,

    /// Show Bangla digits (৳১,৫০০) when the language is Bangla.
    @Default(true) bool banglaDigits,

    /// First day of the week in weekly reports.
    @Default(WeekStart.saturday) WeekStart weekStart,

    /// Day of the month a "month" starts on (e.g. salary day), 1..28 (D15).
    @Default(1) int monthStartDay,

    /// Daily "record today's expenses" reminder (§15). Off until the user
    /// turns it on, so the app never asks for permission unprompted.
    @Default(false) bool reminderEnabled,

    /// Reminder time as minutes after midnight (default 21:00).
    @Default(AppSettings.defaultReminderMinutes) int reminderMinutes,

    /// Notify when a budget crosses its warning threshold, 100%, or more.
    @Default(true) bool budgetAlerts,


    /// Notify on the 1st that last month's summary is ready.
    @Default(true) bool monthlySummary,

    /// Warning threshold (percent) for new budgets (§12.1 default 80%).
    @Default(AppSettings.defaultBudgetThreshold) int budgetWarningDefault,
  }) = _AppSettings;

  static const int defaultReminderMinutes = 21 * 60;
  static const int defaultBudgetThreshold = 80;

  MonthCycle get monthCycle => MonthCycle(monthStartDay);

  /// Whether amounts and numbers should actually be shown in Bangla digits.
  bool get useBanglaDigits => language == AppLanguage.bangla && banglaDigits;
}

/// Storage keys in the `app_settings` table. Never rename: backups use them.
abstract final class AppSettingKeys {
  static const String language = 'language';
  static const String theme = 'theme';
  static const String banglaDigits = 'bangla_digits';
  static const String weekStart = 'week_start';
  static const String monthStartDay = 'month_start_day';
  static const String reminderEnabled = 'reminder_enabled';
  static const String reminderMinutes = 'reminder_minutes';
  static const String budgetAlerts = 'budget_alerts';
  static const String monthlySummary = 'monthly_summary';
  static const String budgetWarningDefault = 'budget_warning_default';
}
