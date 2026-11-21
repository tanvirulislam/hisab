import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/core/utils/local_date.dart';
import 'package:hisab/features/reports/domain/report_math.dart';
import 'package:hisab/features/reports/presentation/report_providers.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    db = await openTestDb();
    c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localPrefsProvider.overrideWithValue(InMemoryLocalPrefs()),
    ]);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('starts on the current month and returns to today after navigating', () {
    final f = c.read(reportFilterProvider.notifier);
    expect(c.read(reportRangeProvider), DateRange.month(2026, 11));
    f.shift(-1);
    expect(c.read(reportRangeProvider), DateRange.month(2026, 10));
    f.shift(1);
    expect(c.read(reportFilterProvider).anchor, LocalDate(2026, 11, 21));
    f.setPeriod(ReportPeriod.day);
    expect(c.read(reportRangeProvider), DateRange.day(LocalDate(2026, 11, 21)));
  });

  test('weekly range follows the week-start setting (Saturday by default)', () async {
    final f = c.read(reportFilterProvider.notifier);
    f.setPeriod(ReportPeriod.week);
    expect(c.read(reportRangeProvider).start, LocalDate(2026, 11, 21)); // a Saturday
  });
}
