import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/app.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';

import 'helpers/test_db.dart';

void main() {
  late AppDatabase db;

  Future<void> pumpApp(WidgetTester tester) async {
    db = await tester.runAsync(openTestDb) as AppDatabase;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPrefsProvider.overrideWithValue(InMemoryLocalPrefs()),
        ],
        retry: (_, _) => null,
        child: const HisabApp(),
      ),
    );
    await settle(tester);
  }

  tearDown(() => db.close());

  testWidgets('starts in Bangla with five nav items and a live zero balance', (tester) async {
    await pumpApp(tester);
    for (final label in ['হোম', 'ইতিহাস', 'যোগ করুন', 'রিপোর্ট', 'আরও']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('মোট ব্যালেন্স'), findsOneWidget);
    expect(find.text('৳০'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('switching language to English updates the UI', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('আরও'));
    await settle(tester);
    await tester.tap(find.text('সেটিংস'));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('Add opens full-screen and closes back to the same tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('যোগ করুন'));
    await settle(tester);
    expect(find.byType(CloseButton), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await settle(tester);
    expect(find.text('মোট ব্যালেন্স'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('categories screen lists seeded categories in Bangla', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('আরও'));
    await settle(tester);
    await tester.tap(find.text('ক্যাটাগরি'));
    await settle(tester);
    expect(find.text('বাজার ও মুদি'), findsOneWidget);
    expect(find.text('যাতায়াত'), findsOneWidget);
    await disposeApp(tester);
  });
}

/// Lets real DB futures complete between frames (drift runs real async I/O).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Unmount so drift stream subscriptions are cancelled before the test ends.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}
