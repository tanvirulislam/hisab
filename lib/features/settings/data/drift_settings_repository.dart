import '../../../core/database/app_database.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/week_start.dart';
import '../domain/app_settings.dart';
import '../domain/settings_repository.dart';

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<AppSettings> watchSettings() =>
      _db.settingsDao.watchAll().map(fromMap).distinct();

  @override
  Future<void> setLanguage(AppLanguage language) =>
      _put(AppSettingKeys.language, language.code);

  @override
  Future<void> setTheme(AppThemePreference theme) =>
      _put(AppSettingKeys.theme, theme.name);

  @override
  Future<void> setBanglaDigits(bool enabled) =>
      _put(AppSettingKeys.banglaDigits, enabled ? '1' : '0');

  @override
  Future<void> setWeekStart(WeekStart start) => _put(AppSettingKeys.weekStart, start.name);

  @override
  Future<void> setReminderEnabled(bool enabled) => _putBool(AppSettingKeys.reminderEnabled, enabled);

  @override
  Future<void> setReminderMinutes(int minutes) {
    RangeError.checkValueInInterval(minutes, 0, 24 * 60 - 1, 'minutes');
    return _put(AppSettingKeys.reminderMinutes, '$minutes');
  }

  @override
  Future<void> setBudgetAlerts(bool enabled) => _putBool(AppSettingKeys.budgetAlerts, enabled);

  @override
  Future<void> setRecurringAlerts(bool enabled) => _putBool(AppSettingKeys.recurringAlerts, enabled);

  @override
  Future<void> setMonthlySummary(bool enabled) => _putBool(AppSettingKeys.monthlySummary, enabled);

  @override
  Future<void> setBudgetWarningDefault(int percent) {
    RangeError.checkValueInInterval(percent, 1, 100, 'percent');
    return _put(AppSettingKeys.budgetWarningDefault, '$percent');
  }

  Future<void> _putBool(String key, bool value) => _put(key, value ? '1' : '0');

  Future<void> _put(String key, String value) =>
      _db.settingsDao.put(key, value, _db.clock.nowMillis());

  /// Missing or unknown values fall back to defaults, so an old or
  /// hand-edited backup can never crash the app.
  static AppSettings fromMap(Map<String, String> map) => AppSettings(
    language: AppLanguage.parse(map[AppSettingKeys.language]),
    theme: AppThemePreference.parse(map[AppSettingKeys.theme]),
    banglaDigits: map[AppSettingKeys.banglaDigits] != '0',
    weekStart: WeekStart.parse(map[AppSettingKeys.weekStart]),
    reminderEnabled: map[AppSettingKeys.reminderEnabled] == '1',
    reminderMinutes: _intIn(map[AppSettingKeys.reminderMinutes], 0, 24 * 60 - 1)
        ?? AppSettings.defaultReminderMinutes,
    budgetAlerts: map[AppSettingKeys.budgetAlerts] != '0',
    recurringAlerts: map[AppSettingKeys.recurringAlerts] != '0',
    monthlySummary: map[AppSettingKeys.monthlySummary] != '0',
    budgetWarningDefault: _intIn(map[AppSettingKeys.budgetWarningDefault], 1, 100)
        ?? AppSettings.defaultBudgetThreshold,
  );

  static int? _intIn(String? raw, int min, int max) {
    final v = raw == null ? null : int.tryParse(raw);
    return v == null || v < min || v > max ? null : v;
  }
}
