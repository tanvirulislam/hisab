import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _AppSettings;

  /// Whether amounts and numbers should actually be shown in Bangla digits.
  bool get useBanglaDigits => language == AppLanguage.bangla && banglaDigits;
}

/// Storage keys in the `app_settings` table. Never rename: backups use them.
abstract final class AppSettingKeys {
  static const String language = 'language';
  static const String theme = 'theme';
  static const String banglaDigits = 'bangla_digits';
  static const String weekStart = 'week_start';
}
