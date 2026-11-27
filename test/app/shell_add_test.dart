import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/shell.dart';
import 'package:hisab/core/database/app_database.dart';

import '../helpers/app_harness.dart';

/// D21: the More screens have no FAB; the tab bar's Add button adds what the
/// current screen lists, and opens the transaction form everywhere else.
void main() {
  late AppDatabase db;

  Finder navAdd() => find.byType(AppNavItem).at(2);

  Future<void> openMoreItem(WidgetTester tester, String label) async {
    await tester.tap(find.byType(AppNavItem).at(4));
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('Add opens each More screen\'s own sheet, and no FAB is left', (tester) async {
    db = await pumpHisab(tester, language: 'en');
    final cases = {
      'Budgets': 'Add budget',
      'Categories': 'Add category',
      'Accounts': 'Add account',
      'Loans & debts': 'Add entry',
    };
    for (final MapEntry(key: screen, value: sheetTitle) in cases.entries) {
      await openMoreItem(tester, screen);
      expect(find.byType(FloatingActionButton), findsNothing, reason: screen);
      await tester.tap(navAdd());
      await settle(tester);
      expect(find.text(sheetTitle), findsOneWidget, reason: screen);
      expect(find.text('New transaction'), findsNothing, reason: screen);
      await closeSheet(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
    }
  });

  testWidgets('Add on the Income tab of Categories adds an income category', (tester) async {
    db = await pumpHisab(tester, language: 'en');
    await openMoreItem(tester, 'Categories');
    await tester.tap(find.text('Income'));
    await settle(tester);
    await tester.tap(navAdd());
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Freelance');
    await tester.tap(find.text('Save'));
    await settle(tester);
    final rows = await tester.runAsync(() => db.categoriesDao.getAll());
    final made = rows!.where((c) => c.name == 'Freelance').single;
    expect(made.type, 'income');
  });

  testWidgets('Add opens the transaction form outside those screens', (tester) async {
    db = await pumpHisab(tester, language: 'en');
    // On Home.
    await tester.tap(navAdd());
    await settle(tester);
    expect(find.text('New transaction'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);

    // Back on the More list after visiting Budgets: the Budgets action is gone.
    await openMoreItem(tester, 'Budgets');
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(navAdd());
    await settle(tester);
    expect(find.text('New transaction'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);

    // Budgets stays open in the More tab while Home is shown: Add on Home
    // still opens the transaction form.
    await openMoreItem(tester, 'Budgets');
    await tester.tap(find.byType(AppNavItem).at(0));
    await settle(tester);
    await tester.tap(navAdd());
    await settle(tester);
    expect(find.text('New transaction'), findsOneWidget);
  });
}
