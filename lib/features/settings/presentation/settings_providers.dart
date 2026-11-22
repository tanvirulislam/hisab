import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/month_cycle.dart';
import '../data/drift_settings_repository.dart';
import '../domain/app_settings.dart';
import '../domain/settings_repository.dart';

part 'settings_providers.g.dart';

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    DriftSettingsRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
Stream<AppSettings> appSettings(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watchSettings();

/// Formatter that follows the language and digit settings.
@Riverpod(keepAlive: true)
MoneyFormatter moneyFormatter(Ref ref) {
  final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();
  return MoneyFormatter(banglaDigits: settings.useBanglaDigits);
}

/// How "a month" is cut (calendar or from a chosen start day), D15.
@Riverpod(keepAlive: true)
MonthCycle monthCycle(Ref ref) =>
    (ref.watch(appSettingsProvider).value ?? const AppSettings()).monthCycle;
