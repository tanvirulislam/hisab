import 'app_settings.dart';

abstract interface class SettingsRepository {
  Stream<AppSettings> watchSettings();

  Future<void> setLanguage(AppLanguage language);

  Future<void> setTheme(AppThemePreference theme);

  Future<void> setBanglaDigits(bool enabled);
}
