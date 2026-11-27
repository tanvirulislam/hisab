import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/shell.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/widgets/amount_field.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;

  Future<int> cashBalance(WidgetTester tester) async {
    final rows = await tester.runAsync(() async {
      final ws = await workspaceOfType(db, 'personal');
      return db.accountsDao.watchWithBalances([ws.id]).first;
    });
    return rows!.first.balancePaisa;
  }

  Future<void> openLoans(WidgetTester tester, String moreTab, String loansLabel) async {
    await tester.tap(find.text(moreTab));
    await settle(tester);
    await tester.tap(find.text(loansLabel));
    await settle(tester);
  }

  Finder amountInput() =>
      find.descendant(of: find.byType(AmountField), matching: find.byType(TextField));

  testWidgets('an old loan is repaid: balance goes up, income stays zero, loan settles', (tester) async {
    db = await pumpHisab(tester, language: 'en');
    await openLoans(tester, 'More', 'Loans & debts');
    expect(find.text('No loans yet'), findsOneWidget);

    // Record the old loan: no account change.
    await tester.tap(find.byType(AppNavItem).at(2)); // Add opens the loan sheet here (D21)
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Karim');
    await tester.enterText(amountInput(), '5000');
    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.text('Karim'), findsOneWidget);
    expect(find.textContaining('Owes you'), findsOneWidget);
    expect(await cashBalance(tester), 0, reason: 'old loan must not move any balance');

    // Open Karim and record the repayment with the "full amount" shortcut.
    await tester.tap(find.text('Karim'));
    await settle(tester);
    expect(find.textContaining('Old loan, no account change'), findsOneWidget);
    await tester.tap(find.text('Got it back'));
    await settle(tester);
    await tester.tap(find.textContaining('Full amount'));
    await settle(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.text('Settled'), findsWidgets);
    expect(await cashBalance(tester), 500000);
    final income = await tester.runAsync(
      () => db.customSelect("SELECT COUNT(*) AS n FROM transactions WHERE type = 'income'").getSingle(),
    );
    expect(income!.read<int>('n'), 0, reason: 'a repayment is not income');
  });

  testWidgets('a repayment larger than what is open is refused with a message', (tester) async {
    db = await pumpHisab(tester, language: 'en');
    await openLoans(tester, 'More', 'Loans & debts');
    await tester.tap(find.byType(AppNavItem).at(2)); // Add opens the loan sheet here (D21)
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Rahim');
    await tester.enterText(amountInput(), '100');
    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    await tester.tap(find.text('Rahim'));
    await settle(tester);
    await tester.tap(find.text('Got it back'));
    await settle(tester);
    await tester.enterText(amountInput(), '150');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settleBrief(tester);
    expect(find.text("A repayment can't be more than what is still open."), findsOneWidget);
    expect(await cashBalance(tester), 0);
    await settle(tester); // let the toast close by itself
  });

  testWidgets('home shows the owed/owe card only while a loan is open', (tester) async {
    db = await pumpHisab(tester, language: 'en', seed: (db) async {
      final ws = await workspaceOfType(db, 'personal');
      final now = testNow.millisecondsSinceEpoch;
      await db.into(db.persons).insert(PersonsCompanion.insert(
          id: 'p', workspaceId: ws.id, name: 'Karim', createdAt: now, updatedAt: now));
      await db.into(db.loanEntries).insert(LoanEntriesCompanion.insert(
          id: 'l', workspaceId: ws.id, personId: 'p', kind: 'borrowed', amountPaisa: 250000,
          localDate: 20261121, createdAt: now, updatedAt: now));
    });
    expect(find.text('You will get'), findsOneWidget);
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('৳2,500'), findsWidgets);
  });

  for (final lang in ['bn', 'en']) {
    testWidgets('loan screens do not overflow on a 360dp phone ($lang)', (tester) async {
      db = await pumpHisab(tester, logicalSize: const Size(360, 740), language: lang, seed: (db) async {
        final ws = await workspaceOfType(db, 'personal');
        final now = testNow.millisecondsSinceEpoch;
        await db.into(db.persons).insert(PersonsCompanion.insert(
            id: 'p', workspaceId: ws.id, name: 'Abdur Rahman Chowdhury', createdAt: now, updatedAt: now));
        await db.into(db.loanEntries).insert(LoanEntriesCompanion.insert(
            id: 'l1', workspaceId: ws.id, personId: 'p', kind: 'lent', amountPaisa: 123456700,
            localDate: 20261121, note: const Value('a long note that goes on and on for a while'),
            createdAt: now, updatedAt: now));
        await db.into(db.loanEntries).insert(LoanEntriesCompanion.insert(
            id: 'l2', workspaceId: ws.id, personId: 'p', kind: 'borrowed', amountPaisa: 5000000,
            localDate: 20261120, createdAt: now, updatedAt: now));
      });
      await tester.tap(find.byIcon(Icons.menu).last);
      await settle(tester);
      await tester.tap(find.byIcon(Icons.handshake_outlined));
      await settle(tester);
      await tester.tap(find.byType(AppNavItem).at(2)); // Add opens the loan sheet here (D21)
      await settle(tester);
      await tester.binding.handlePopRoute(); // close the sheet (system back)
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Abdur Rahman Chowdhury'));
      await settle(tester);
      await tester.tap(find.byType(FilledButton).first);
      await settle(tester);
    });
  }
}
