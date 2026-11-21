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
/// Family: grocery 1,000 today.
Future<void> seed(AppDatabase db) async {
  final repo = DriftTransactionRepository(db);
  final p = (await workspaceOfType(db, 'personal')).id;
  final f = (await workspaceOfType(db, 'family')).id;
  final pCash = (await firstAccountOf(db, p)).id;
  final fCash = (await firstAccountOf(db, f)).id;
  Future<String> cat(String k) async => (await categoryByKey(db, k)).id;
  Future<void> add(EntryType t, String ws, String acc, int taka, String c, {String? sub, DateTime? at}) =>
      repo.createEntry(EntryDraft(
          type: t, workspaceId: ws, accountId: acc, amount: Money.fromTaka(taka),
          categoryId: c, subcategoryId: sub, occurredAt: at ?? testNow));
  await add(EntryType.income, p, pCash, 50000, await cat('income.salary'), at: DateTime(2026, 11, 1));
  await add(EntryType.expense, p, pCash, 350, await cat('grocery'), sub: await cat('grocery.fish'));
  await add(EntryType.expense, p, pCash, 80, await cat('transport'));
  await add(EntryType.expense, p, pCash, 500, await cat('health'), at: DateTime(2026, 11, 20, 12));
  await add(EntryType.expense, f, fCash, 1000, await cat('grocery'));
}

void main() {
  Future<void> pumpApp(WidgetTester tester) =>
      pumpHisab(tester, logicalSize: const Size(432, 1200), seed: seed);

  testWidgets('dashboard shows live month and today figures for the scope', (tester) async {
    await pumpApp(tester);
    // Personal: income 50,000; expense 930; saved 49,070; today 430.
    expect(find.text('৳৫০,০০০'), findsWidgets);
    expect(find.text('৳৯৩০'), findsOneWidget);
    expect(find.text('৳৪৯,০৭০'), findsWidgets);
    expect(find.text('৳৪৩০'), findsOneWidget);
    expect(find.text('দৈনিক খরচ'), findsOneWidget);
    expect(find.text('এই মাসে সবচেয়ে বেশি খরচ'), findsOneWidget);

    // Family scope: only the family grocery.
    await tester.tap(find.text('পরিবার').first);
    await settle(tester);
    expect(find.text('৳১,০০০'), findsWidgets);
    expect(find.text('৳৯৩০'), findsNothing);

    // Combined: 1,930 expense and the Personal/Family split card.
    await tester.tap(find.text('সম্মিলিত').first);
    await settle(tester);
    expect(find.text('৳১,৯৩০'), findsOneWidget);
    expect(find.text('ব্যক্তিগত ও পরিবার'), findsOneWidget);
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
