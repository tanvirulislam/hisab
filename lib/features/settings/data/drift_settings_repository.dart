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

  Future<void> _put(String key, String value) =>
      _db.settingsDao.put(key, value, _db.clock.nowMillis());

  /// Missing or unknown values fall back to defaults, so an old or
  /// hand-edited backup can never crash the app.
  static AppSettings fromMap(Map<String, String> map) => AppSettings(
    language: AppLanguage.parse(map[AppSettingKeys.language]),
    theme: AppThemePreference.parse(map[AppSettingKeys.theme]),
    banglaDigits: map[AppSettingKeys.banglaDigits] != '0',
    weekStart: WeekStart.parse(map[AppSettingKeys.weekStart]),
  );
}
