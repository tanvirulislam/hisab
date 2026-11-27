import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/shell.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/backup/data/backup_repository.dart';
import 'package:hisab/features/backup/domain/backup_file.dart';
import 'package:hisab/features/backup/presentation/backup_screen.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fakes.dart';
import '../../helpers/test_db.dart';
import 'backup_helpers.dart';

/// A backup from "another phone" that holds everything [seedEverything] makes.
Future<EncodedBackup> otherPhoneBackup() async {
  final other = await openTestDb();
  await seedEverything(other);
  // The restored app should stay in the test's language.
  await other.settingsDao.put('language', 'en', 1);
  final b = await BackupRepository(other).export(appVersion: 'x', now: DateTime(2026, 11, 20, 21, 30));
  await other.close();
  return b;
}

Future<void> openBackupScreen(WidgetTester tester) async {
  await tester.tap(find.byType(AppNavItem).at(4));
  await settle(tester);
  await tester.tap(find.byIcon(Icons.backup_outlined));
  await settle(tester);
}

/// Scrolls the Backup screen's list until [finder] is on screen.
Future<void> scrollBackupTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.descendant(of: find.byType(BackupScreen), matching: find.byType(Scrollable)),
  );
  await settle(tester);
}

void main() {
  testWidgets('sign in, back up now, restore from Drive, undo', (tester) async {
    final store = FakeBackupStore();
    store.put('old', (await tester.runAsync(otherPhoneBackup))!, transactionCount: 4);
    final google = FakeGoogleAccount();
    final db = await pumpHisab(tester, language: 'en', google: google, backupStore: store);
    await openBackupScreen(tester);

    // Signed out: explanation and the sign-in button.
    expect(find.textContaining('your own Google Drive'), findsOneWidget);
    await tester.tap(find.text('Sign in with Google'));
    await settle(tester);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Hisab Backup'), findsOneWidget);
    expect(find.text('No backup yet'), findsOneWidget);

    await tester.tap(find.text('Back up now'));
    await settleBrief(tester);
    expect(find.text('Backup saved to Drive'), findsOneWidget);
    expect(store.uploads, 1);
    await settle(tester);
    expect(find.text('just now'), findsOneWidget);

    // The list: newest first, with the transaction count.
    await tester.tap(find.text('Restore from Drive'));
    await settle(tester);
    expect(find.text('4 transactions'), findsOneWidget);
    expect(find.text('0 transactions'), findsOneWidget);
    await tester.tap(find.text('4 transactions'));
    await settle(tester);

    // Preview with counts, then the confirm dialog.
    expect(find.text('What this backup holds'), findsOneWidget);
    expect(find.textContaining('Taken 20 Nov 2026'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settle(tester);
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('All current data will be replaced'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settleBrief(tester);
    expect(find.text('Data restored'), findsOneWidget);
    await settle(tester);

    // Back on the Backup screen; the data is the backup's.
    expect(find.text('Undo last restore'), findsOneWidget);
    final persons = await tester.runAsync(() => db.select(db.persons).get());
    expect(persons!.single.name, 'Karim');

    // Home shows the restored data (streams refreshed by themselves).
    await tester.tap(find.byType(AppNavItem).at(0));
    await settle(tester);
    expect(find.text('Have data on Drive?'), findsNothing);

    // Undo puts back the empty install.
    await tester.tap(find.byType(AppNavItem).at(4));
    await settle(tester);
    await tester.tap(find.text('Undo last restore'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settleBrief(tester);
    expect(find.text('Previous data is back'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.persons).get()), isEmpty);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  for (final (lang, noInternet, failedPrefix) in [
    ('en', 'No internet', 'Last backup failed'),
    ('bn', 'ইন্টারনেট নেই', 'শেষ backup হয়নি'),
  ]) {
    testWidgets('no internet shows the error ($lang)', (tester) async {
      final store = FakeBackupStore()..failWith = BackupError.network;
      await pumpHisab(
        tester,
        language: lang,
        google: FakeGoogleAccount(signedInEmail: 'owner@example.com'),
        prefs: InMemoryLocalPrefs({LocalPrefKeys.backupSignedIn: '1'}),
        backupStore: store,
        seed: seedEverything,
      );
      await openBackupScreen(tester);
      await scrollBackupTo(tester, find.byIcon(Icons.backup_outlined).last);
      await tester.tap(find.byIcon(Icons.backup_outlined).last);
      await settleBrief(tester);
      expect(find.text(noInternet), findsOneWidget);
      await settle(tester);
      expect(find.text('$failedPrefix: $noInternet'), findsOneWidget);

      await scrollBackupTo(tester, find.byIcon(Icons.restore));
      await tester.tap(find.byIcon(Icons.restore));
      await settle(tester);
      expect(find.text(noInternet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sign-in that is not set up says so', (tester) async {
    await pumpHisab(tester, language: 'en', google: FakeGoogleAccount(signInError: BackupError.notConfigured));
    await openBackupScreen(tester);
    await tester.tap(find.text('Sign in with Google'));
    await settleBrief(tester);
    expect(find.textContaining('Backup is not set up yet'), findsOneWidget);
    await settle(tester);
  });

  group('fresh-install restore offer', () {
    testWidgets('shows on an empty install, once', (tester) async {
      final prefs = InMemoryLocalPrefs();
      await pumpHisab(tester, language: 'en', prefs: prefs);
      expect(find.text('Have data on Drive?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(find.text('Have data on Drive?'), findsNothing);
      expect(prefs.getString(LocalPrefKeys.backupRestoreOfferDone), '1');
    });

    testWidgets('does not show again after it was answered', (tester) async {
      final prefs = InMemoryLocalPrefs({LocalPrefKeys.backupRestoreOfferDone: '1'});
      await pumpHisab(tester, language: 'en', prefs: prefs);
      expect(find.text('Have data on Drive?'), findsNothing);
    });

    testWidgets('does not show when there is data, and never will', (tester) async {
      final prefs = InMemoryLocalPrefs();
      await pumpHisab(tester, language: 'en', prefs: prefs, seed: seedEverything);
      expect(find.text('Have data on Drive?'), findsNothing);
      expect(prefs.getString(LocalPrefKeys.backupRestoreOfferDone), '1');
    });

    testWidgets('its Restore opens the Backup screen', (tester) async {
      await pumpHisab(tester, language: 'en');
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await settle(tester);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });

  for (final lang in ['bn', 'en']) {
    testWidgets('no overflow on a 360dp phone ($lang)', (tester) async {
      final store = FakeBackupStore();
      store.put('old', (await tester.runAsync(otherPhoneBackup))!, transactionCount: 4);
      await pumpHisab(tester, logicalSize: const Size(360, 740), language: lang, backupStore: store);
      // Home with the offer card.
      expect(tester.takeException(), isNull);
      await openBackupScreen(tester);
      await tester.tap(find.byIcon(Icons.login));
      await settle(tester);
      await scrollBackupTo(tester, find.byIcon(Icons.restore));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.restore));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
