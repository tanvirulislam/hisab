import '../../../core/utils/week_start.dart';
import 'app_settings.dart';

abstract interface class SettingsRepository {
  Stream<AppSettings> watchSettings();

  Future<void> setLanguage(AppLanguage language);

  Future<void> setTheme(AppThemePreference theme);

  Future<void> setBanglaDigits(bool enabled);

  Future<void> setWeekStart(WeekStart start);

  /// [day] in 1..28 (MonthCycle.minDay..maxDay).
  Future<void> setMonthStartDay(int day);

  Future<void> setReminderEnabled(bool enabled);

  /// [minutes] after midnight, 0..1439.
  Future<void> setReminderMinutes(int minutes);

  Future<void> setBudgetAlerts(bool enabled);

  Future<void> setRecurringAlerts(bool enabled);

  Future<void> setMonthlySummary(bool enabled);

  /// [percent] in 1..100.
  Future<void> setBudgetWarningDefault(int percent);
}
