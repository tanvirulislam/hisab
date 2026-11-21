import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/today_provider.dart';
import '../../../core/utils/bn_digits.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money_format.dart';
import '../domain/app_settings.dart';
import 'settings_providers.dart';

part 'app_formats.g.dart';

/// Locale-aware formatting for money, dates and times, honouring the
/// language and Bangla-digit settings.
class AppFormats {
  AppFormats({required this.languageCode, required this.banglaDigits, required this.today})
      : money = MoneyFormatter(banglaDigits: banglaDigits);

  final String languageCode;
  final bool banglaDigits;
  final LocalDate today;
  final MoneyFormatter money;

  String _digits(String s) => banglaDigits ? BnDigits.toBangla(s) : BnDigits.toLatin(s);

  /// "21 November" (adds the year when it is not the current year).
  String date(LocalDate d) {
    final pattern = d.year == today.year ? 'd MMMM' : 'd MMMM y';
    return _digits(DateFormat(pattern, languageCode).format(d.toDateTime()));
  }

  /// "Sat, 21 Nov 2026"
  String dateLong(LocalDate d) =>
      _digits(DateFormat('EEE, d MMM y', languageCode).format(d.toDateTime()));

  String time(DateTime t) => _digits(DateFormat.jm(languageCode).format(t));

  String integer(int n) => money.formatInt(n);

  /// Today / Yesterday, or null for older dates.
  bool isToday(LocalDate d) => d == today;
  bool isYesterday(LocalDate d) => d == today.addDays(-1);
}

@riverpod
AppFormats appFormats(Ref ref) {
  final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();
  return AppFormats(
    languageCode: settings.language.code,
    banglaDigits: settings.useBanglaDigits,
    today: ref.currentDate(),
  );
}
