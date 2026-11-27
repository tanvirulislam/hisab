import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/notifications/notification_providers.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/clock.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/backup/data/backup_repository.dart';
import 'package:hisab/features/backup/data/safety_backups.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';
import 'package:hisab/features/backup/presentation/backup_providers.dart';
import 'package:hisab/features/notifications/domain/notification_plan.dart';
import 'package:hisab/features/notifications/presentation/notification_coordinator.dart';
import 'package:hisab/features/settings/presentation/settings_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_db.dart';
import 'backup_helpers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late FakeGoogleAccount google;
  late FakeBackupStore store;
  late SafetyBackups safety;
  late InMemoryLocalPrefs prefs;
  late RecordingNotifications notices;
  late FixedClock clock;

  setUp(() async {
    clock = FixedClock(testNow);
    db = await openTestDb(clock: clock);
    google = FakeGoogleAccount(signedInEmail: 'owner@example.com');
    store = FakeBackupStore();
    safety = tempSafetyBackups();
    prefs = InMemoryLocalPrefs({LocalPrefKeys.backupSignedIn: '1'});
    notices = RecordingNotifications();
    c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localPrefsProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notices),
      googleAccountProvider.overrideWithValue(google),
      backupStoreProvider.overrideWithValue(store),
      safetyBackupsProvider.overrideWithValue(safety),
    ], retry: (_, _) => null);
    // Stream providers pause without a listener (CLAUDE.md gotcha).
    c.listen(appSettingsProvider, (_, _) {});
    c.listen(notificationCoordinatorProvider, (_, _) {});
    c.listen(backupControllerProvider, (_, _) {});
  });
  tearDown(() async {
    // Let providers that are still loading finish before the container goes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(notificationCoordinatorProvider.notifier).idle;
    c.dispose();
    await db.close();
  });

  BackupController ctrl() => c.read(backupControllerProvider.notifier);

  /// A backup taken from another DB that holds everything.
  Future<EncodedBackup> otherPhoneBackup({String reminder = '0'}) async {
    final other = await openTestDb();
    await seedEverything(other);
    await other.settingsDao.put('reminder_enabled', reminder, 1);
    final b = await BackupRepository(other).export(appVersion: 'x', now: testNow.subtract(const Duration(days: 1)));
    await other.close();
    return b;
  }

  test('back up now uploads, records success, and the next auto run is not due', () async {
    await seedEverything(db);
    await ctrl().start();
    expect(c.read(backupControllerProvider).email, 'owner@example.com');
    await ctrl().backupNow();
    expect(store.files, hasLength(1));
    expect(store.files.values.single.meta.transactionCount, 4);
    expect(c.read(backupControllerProvider).lastSuccess, testNow);
    expect(prefs.getString(LocalPrefKeys.backupLastSuccess), '${testNow.millisecondsSinceEpoch}');

    await ctrl().autoBackupIfDue();
    expect(store.uploads, 1, reason: 'just backed up');
    clock.value = testNow.add(const Duration(hours: 25));
    await ctrl().autoBackupIfDue();
    expect(store.uploads, 1, reason: 'data did not change');
    await db.settingsDao.put('theme', 'dark', clock.nowMillis());
    await ctrl().autoBackupIfDue();
    expect(store.uploads, 2);
  });

  test('auto backup stays silent without sign-in or user data', () async {
    google.signedInEmail = null;
    await seedEverything(db);
    await ctrl().autoBackupIfDue();
    expect(store.uploads, 0);
  });

  test('no silent sign-in for someone who never signed in here', () async {
    await prefs.setString(LocalPrefKeys.backupSignedIn, '');
    await seedEverything(db);
    await ctrl().autoBackupIfDue();
    expect(c.read(backupControllerProvider).email, isNull);
    expect(store.uploads, 0);
  });

  test('sign in remembers it; sign out forgets it', () async {
    await prefs.setString(LocalPrefKeys.backupSignedIn, '');
    google.signedInEmail = null;
    await ctrl().signIn();
    expect(prefs.getString(LocalPrefKeys.backupSignedIn), '1');
    await ctrl().signOut();
    expect(prefs.getString(LocalPrefKeys.backupSignedIn), '');
    expect(c.read(backupControllerProvider).signedIn, isFalse);
  });

  test('auto backup does not back up an empty fresh install', () async {
    await ctrl().autoBackupIfDue();
    expect(store.uploads, 0);
  });

  test('a failure is recorded, not thrown by auto backup', () async {
    await seedEverything(db);
    store.failWith = BackupError.network;
    await ctrl().autoBackupIfDue();
    final s = c.read(backupControllerProvider);
    expect(s.lastErrorCode, BackupError.network);
    expect(s.lastErrorAt, testNow);
    expect(() => ctrl().backupNow(), throwsBackup(BackupError.network));
  });

  test('the newest 10 stay on Drive', () async {
    await seedEverything(db);
    for (var i = 0; i < 12; i++) {
      clock.value = testNow.add(Duration(minutes: i));
      await ctrl().backupNow();
    }
    expect(store.files, hasLength(10));
  });

  test('restore writes a safety copy first, keeps 3, and can be undone', () async {
    await seedEverything(db);
    final repo = BackupRepository(db);
    final mine = await repo.dumpTables();
    store.put('b1', await otherPhoneBackup());

    final prepared = await ctrl().prepare('b1');
    await ctrl().restore(prepared);
    final safetyCopy = BackupCodec.decode((await safety.latest())!);
    expect(safetyCopy.tables, mine, reason: 'safety copy is the data from before the restore');
    expect(c.read(backupControllerProvider).hasSafety, isTrue);
    expect(await repo.dumpTables(), isNot(mine));

    for (var i = 0; i < 3; i++) {
      clock.value = testNow.add(Duration(minutes: i + 1));
      await ctrl().restore(prepared);
    }
    expect(await safety.count(), 3);

    // Undo goes back one step: the state before the last restore.
    final beforeLast = BackupCodec.decode((await safety.latest())!).tables;
    await ctrl().undoRestore();
    expect(await repo.dumpTables(), beforeLast);
    expect(await safety.count(), 2);
  });

  test('restore reschedules notifications and resets per-device state', () async {
    await prefs.setString(LocalPrefKeys.budgetAlertLevels, '{"x":2}');
    await prefs.setString(LocalPrefKeys.lastAccountId, '{"ws":"gone-account"}');
    await c.read(notificationCoordinatorProvider.notifier).idle;
    expect(notices.scheduled.keys.where((id) => id >= NoticeIds.reminderBase && id < NoticeIds.reminderBase + 100), isEmpty);

    store.put('b1', await otherPhoneBackup(reminder: '1'));
    await ctrl().restore(await ctrl().prepare('b1'));
    // Let the settings stream deliver the restored values.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await c.read(notificationCoordinatorProvider.notifier).idle;
    }
    expect(notices.scheduled.keys.where((id) => id >= NoticeIds.reminderBase && id < NoticeIds.reminderBase + 100), isNotEmpty);
    expect(prefs.getString(LocalPrefKeys.budgetAlertLevels), '{}');
    expect(prefs.getString(LocalPrefKeys.lastAccountId), '{}');
    expect(c.read(appSettingsProvider).value?.monthStartDay, 25);
  });

  test('a corrupt Drive file changes nothing', () async {
    await seedEverything(db);
    final repo = BackupRepository(db);
    final before = await repo.dumpTables();
    final good = await otherPhoneBackup();
    store.put('bad', EncodedBackup(bytes: good.bytes.sublist(0, 100), header: good.header));
    await expectLater(ctrl().prepare('bad'), throwsBackup(BackupError.corruptFile));
    expect(await repo.dumpTables(), before);
    expect(await safety.hasAny(), isFalse);
  });
}
