import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/test_db.dart';

/// Seeds November 2026 data (testNow = 21 Nov 2026 10:00):
/// Personal: salary 50,000; fish 350 today; bus 80 today; medicine 500 yesterday.
Future<void> seed(AppDatabase db) async {
  final repo = DriftTransactionRepository(db);
  final p = (await workspaceOfType(db, 'personal')).id;
  final pCash = (await firstAccountOf(db, p)).id;
  Future<String> cat(String k) async => (await categoryByKey(db, k)).id;
  Future<void> add(EntryType t, String ws, String acc, int taka, String c, {String? sub, DateTime? at}) =>
      repo.createEntry(EntryDraft(
          type: t, workspaceId: ws, accountId: acc, amount: Money.fromTaka(taka),
          categoryId: c, subcategoryId: sub, occurredAt: at ?? testNow));
  await add(EntryType.income, p, pCash, 50000, await cat('income.salary'), at: DateTime(2026, 11, 1));
  await add(EntryType.expense, p, pCash, 350, await cat('grocery'), sub: await cat('grocery.fish'));
  await add(EntryType.expense, p, pCash, 80, await cat('transport'));
  await add(EntryType.expense, p, pCash, 500, await cat('health'), at: DateTime(2026, 11, 20, 12));
}

void main() {
  Future<void> pumpApp(WidgetTester tester) =>
      pumpHisab(tester, logicalSize: const Size(432, 1200), seed: seed);

  testWidgets('dashboard shows live month and today figures (Personal only)', (tester) async {
    await pumpApp(tester);
    // Personal: income 50,000; expense 930; saved 49,070; today 430.
    expect(find.text('৳৫০,০০০'), findsWidgets);
    expect(find.text('৳৯৩০'), findsOneWidget);
    expect(find.text('৳৪৯,০৭০'), findsWidgets);
    expect(find.text('৳৪৩০'), findsOneWidget);
    // D19: "left this month" leads, the total balance is a tile below it.
    expect(find.text('এই মাসে বাকি'), findsOneWidget);
    expect(find.text('মোট ব্যালেন্স'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('এই মাসে বাকি')).dy,
      lessThan(tester.getTopLeft(find.text('মোট ব্যালেন্স')).dy),
    );
    // App bar: where today (21 Nov) sits in the month.
    expect(find.text('৯ দিন বাকি'), findsOneWidget);
    expect(find.text('১ নভে'), findsOneWidget);
    expect(find.text('আজ ২১ নভে'), findsOneWidget);
    expect(find.text('৩০ নভে'), findsOneWidget);
    expect(find.text('দৈনিক খরচ'), findsNothing); // daily chart lives only in Reports
    expect(find.text('এই মাসে সবচেয়ে বেশি খরচ'), findsOneWidget);

    // No workspace switcher (D14).
    expect(find.text('পরিবার'), findsNothing);
    expect(find.text('সম্মিলিত'), findsNothing);
  });

  testWidgets('an overspent month shows by how much (D19)', (tester) async {
    await pumpHisab(tester, logicalSize: const Size(432, 1200), seed: (db) async {
      final repo = DriftTransactionRepository(db);
      final p = (await workspaceOfType(db, 'personal')).id;
      final cash = (await firstAccountOf(db, p)).id;
      Future<void> add(EntryType t, int taka, String key) async => repo.createEntry(EntryDraft(
          type: t, workspaceId: p, accountId: cash, amount: Money.fromTaka(taka),
          categoryId: (await categoryByKey(db, key)).id, occurredAt: testNow));
      await add(EntryType.income, 1000, 'income.salary');
      await add(EntryType.expense, 1500, 'grocery');
    });
    expect(find.text('এই মাসে বাকি'), findsOneWidget);
    expect(find.text('আয়ের চেয়ে ৳৫০০ বেশি খরচ হয়েছে'), findsOneWidget);
  });

  testWidgets('reports: month, day, comparison, drill-down to filtered history', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('রিপোর্ট').last);
    await settle(tester);

    expect(find.text('নভেম্বর ২০২৬'), findsOneWidget);
    expect(find.text('তুলনার জন্য গত মাসে কোনো খরচ নেই'), findsOneWidget);
    expect(find.text('গত ৬ মাস'), findsOneWidget);
    expect(find.text('ওষুধ ও চিকিৎসা'), findsOneWidget);
    expect(find.text('৳৫০০'), findsWidgets);

    // Previous month is empty.
    await tester.tap(find.byTooltip('আগের'));
    await settle(tester);
    expect(find.text('এই সময়ে কোনো লেনদেন নেই'), findsOneWidget);
    await tester.tap(find.byTooltip('পরের'));
    await settle(tester);

    // Day view lists today's transactions.
    await tester.tap(find.text('দিন'));
    await settle(tester);
    await scrollTo(tester, find.text('মাছ'));
    expect(find.text('মাছ'), findsOneWidget);
    expect(find.text('যাতায়াত'), findsWidgets);

    // Drill into Grocery → subcategories → filtered History.
    await scrollTo(tester, find.text('বাজার ও মুদি'));
    await tester.tap(find.text('বাজার ও মুদি'));
    await settle(tester);
    expect(find.text('লেনদেন দেখুন'), findsOneWidget);
    await tester.tap(find.text('লেনদেন দেখুন'));
    await settle(tester);
    expect(find.text('মাছ'), findsOneWidget);
    expect(find.text('যাতায়াত'), findsNothing, reason: 'history is filtered to Grocery');
  });
}
