import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/app.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/notifications/notification_providers.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/features/backup/data/backup_store.dart';
import 'package:hisab/features/backup/data/google_account.dart';
import 'package:hisab/features/backup/data/safety_backups.dart';
import 'package:hisab/features/backup/presentation/backup_providers.dart';
import 'package:hisab/features/voice/data/speech_input.dart';
import 'package:hisab/features/voice/presentation/voice_providers.dart';
import 'package:toastification/toastification.dart';

import 'fakes.dart';
import 'test_db.dart';

/// Pumps the whole app on a fresh in-memory database.
///
/// Teardown unmounts the app and then closes the database with real async,
/// so a failing test reports its error instead of hanging on `db.close()`
/// inside fake async.
Future<AppDatabase> pumpHisab(
  WidgetTester tester, {
  Size logicalSize = const Size(432, 960),
  Future<void> Function(AppDatabase db)? seed,
  String? language,
  RecordingNotifications? notifications,
  SpeechInput? speech,
  LocalPrefs? prefs,
  GoogleAccount? google,
  BackupStore? backupStore,
  SafetyBackups? safety,
}) async {
  tester.view.physicalSize = logicalSize * 2.5;
  tester.view.devicePixelRatio = 2.5;
  final db = await tester.runAsync(openTestDb) as AppDatabase;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    // Toasts live in a global manager; clear them so no auto-close timer
    // outlives the test.
    toastification.dismissAll(delayForAnimation: false);
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(db.close);
    tester.view.reset();
  });
  if (language != null) await tester.runAsync(() => db.settingsDao.put('language', language, 0));
  if (seed != null) await tester.runAsync(() => seed(db));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      localPrefsProvider.overrideWithValue(prefs ?? InMemoryLocalPrefs()),
      googleAccountProvider.overrideWithValue(google ?? FakeGoogleAccount()),
      backupStoreProvider.overrideWithValue(backupStore ?? FakeBackupStore()),
      safetyBackupsProvider.overrideWithValue(safety ?? tempSafetyBackups()),
      notificationServiceProvider.overrideWithValue(notifications ?? RecordingNotifications()),
      speechInputProvider.overrideWithValue(speech ?? ScriptedSpeech()),
    ],
    retry: (_, _) => null,
    child: const HisabApp(),
  ));
  await settle(tester);
  return db;
}

/// Like [settle] but stops after ~0.8s of fake time. Use it when a toast must
/// still be on screen: [settle] runs the clock past the toast's auto-close.
Future<void> settleBrief(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets real DB futures complete between frames (drift runs real async I/O)
/// until nothing is loading. The final settle is bounded, so a stuck
/// spinner fails clearly instead of hanging.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
    final loading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (i >= 4 && !loading) break;
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Brings [finder] on screen: scrolls to it if it is already built (above
/// or below), otherwise drags the main list down until it is built.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(finder, find.byType(ListView).first, const Offset(0, -300));
  }
  await tester.ensureVisible(finder.first);
  await settle(tester);
}
