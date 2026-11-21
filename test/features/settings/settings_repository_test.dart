import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/features/settings/data/drift_settings_repository.dart';
import 'package:hisab/features/settings/domain/app_settings.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late DriftSettingsRepository repo;

  setUp(() async {
    db = await openTestDb();
    repo = DriftSettingsRepository(db);
  });
  tearDown(() => db.close());

  test('defaults: Bangla, system theme, Bangla digits', () async {
    final s = await repo.watchSettings().first;
    expect(s, const AppSettings());
    expect(s.language, AppLanguage.bangla);
    expect(s.useBanglaDigits, isTrue);
  });

  test('round-trips every setting through the database', () async {
    await repo.setLanguage(AppLanguage.english);
    await repo.setTheme(AppThemePreference.dark);
    await repo.setBanglaDigits(false);
    final s = await repo.watchSettings().first;
    expect(s.language, AppLanguage.english);
    expect(s.theme, AppThemePreference.dark);
    expect(s.banglaDigits, isFalse);
  });

  test('Bangla digits apply only when the language is Bangla', () {
    expect(const AppSettings(language: AppLanguage.english).useBanglaDigits, isFalse);
    expect(const AppSettings(banglaDigits: false).useBanglaDigits, isFalse);
  });

  test('unknown or corrupt stored values fall back to defaults', () {
    final s = DriftSettingsRepository.fromMap({
      AppSettingKeys.language: 'fr',
      AppSettingKeys.theme: 'neon',
      AppSettingKeys.banglaDigits: 'maybe',
    });
    expect(s, const AppSettings());
  });
}
