import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/app.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';
import 'package:hisab/core/widgets/amount_field.dart';

import '../../app_smoke_test.dart' show settle, disposeApp;
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    db = await tester.runAsync(openTestDb) as AppDatabase;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPrefsProvider.overrideWithValue(InMemoryLocalPrefs()),
      ],
      retry: (_, _) => null,
      child: const HisabApp(),
    ));
    await settle(tester);
  }

  tearDown(() => db.close());

  testWidgets('record an expense, see it on Home and History, delete and undo', (tester) async {
    await pumpApp(tester);

    // Open quick entry from the centre nav item.
    await tester.tap(find.text('যোগ করুন'));
    await settle(tester);
    await tester.enterText(
        find.descendant(of: find.byType(AmountField), matching: find.byType(TextField)), '350');
    await tester.tap(find.text('খাবার-দাবার'));
    await settle(tester);
    await tester.tap(find.text('দুপুরের খাবার')); // subcategory chip
    await tester.tap(find.text('সংরক্ষণ করুন'));
    await settle(tester);

    // Back on Home: balance and recent list reflect the expense.
    expect(find.text('-৳৩৫০'), findsNWidgets(2));
    expect(find.text('দুপুরের খাবার'), findsOneWidget);

    // History groups it under today with the day total.
    await tester.tap(find.text('ইতিহাস'));
    await settle(tester);
    expect(find.textContaining('আজ'), findsWidgets);
    expect(find.text('খরচ ৳৩৫০'), findsOneWidget);

    // Detail → delete (with confirmation) → undo.
    await tester.tap(find.text('দুপুরের খাবার'));
    await settle(tester);
    await tester.tap(find.byTooltip('মুছুন'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'মুছুন'));
    await settle(tester);
    expect(find.text('এখনো কিছু লেখা হয়নি'), findsOneWidget);
    await tester.tap(find.text('ফিরিয়ে আনুন'));
    await settle(tester);
    expect(find.text('দুপুরের খাবার'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('save without amount or category shows errors and saves nothing', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('যোগ করুন'));
    await settle(tester);
    await tester.tap(find.text('সংরক্ষণ করুন'));
    await settle(tester);
    expect(find.text('শূন্যের বেশি একটি পরিমাণ লিখুন।'), findsOneWidget);
    expect(find.text('একটি ক্যাটাগরি বাছাই করুন'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.transactions).get()), isEmpty);
    await disposeApp(tester);
  });

  testWidgets('transfer between Personal and Family from the quick action', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('ট্রান্সফার').first); // Home quick action
    await settle(tester);
    await tester.enterText(
        find.descendant(of: find.byType(AmountField), matching: find.byType(TextField)), '2000');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await settle(tester);
    await tester.tap(find.textContaining('ব্যক্তিগত · Cash').last);
    await settle(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await settle(tester);
    await tester.tap(find.textContaining('পরিবার · Cash').last);
    await settle(tester);
    expect(find.text('এক ওয়ার্কস্পেস থেকে আরেকটিতে টাকা যাবে। এটি আয় বা খরচ হিসেবে গোনা হবে না।'),
        findsOneWidget);
    await tester.tap(find.text('সংরক্ষণ করুন'));
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.transactions).get());
    expect(rows!.map((r) => r.type).toSet(), {'transfer_out', 'transfer_in'});
    expect(find.text('-৳২,০০০'), findsOneWidget, reason: 'Personal balance');
    await disposeApp(tester);
  });
}
