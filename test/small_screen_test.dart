import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hisab/features/reports/domain/report_math.dart';

import 'helpers/app_harness.dart';
import 'features/reports/dashboard_reports_widget_test.dart' show seed;

/// Every main screen must lay out without overflow on a small phone
/// (360×740 dp), in both languages.
void main() {
  for (final lang in ['bn', 'en']) {
    testWidgets('no overflow on a 360dp phone ($lang)', (tester) async {
      await pumpHisab(tester, logicalSize: const Size(360, 740), language: lang, seed: seed);
      final nav = find.byType(NavigationDestination);
      for (final i in [1, 3, 4, 0]) {
        await tester.tap(nav.at(i));
        await settle(tester);
      }
      // Reports: every period.
      await tester.tap(nav.at(3));
      await settle(tester);
      for (final seg in [0, 1, 2]) {
        await tester.tap(find.byType(SegmentedButton<ReportPeriod>));
        await tester.tap(find.descendant(
            of: find.byType(SegmentedButton<ReportPeriod>), matching: find.byType(Text)).at(seg));
        await settle(tester);
      }
      await tester.tap(nav.at(0));
      await settle(tester);
      // Entry form in all three modes.
      await tester.tap(nav.at(2));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.south_west).first);
      await settle(tester);
      await tester.tap(find.byIcon(Icons.swap_horiz).first);
      await settle(tester);
      await tester.tap(find.byType(CloseButton));
      await settle(tester);

      // Management screens.
      await tester.tap(nav.at(4));
      await settle(tester);
      for (final icon in [Icons.category_outlined, Icons.account_balance_wallet_outlined, Icons.settings_outlined]) {
        await tester.tap(find.byIcon(icon));
        await settle(tester);
        // pageBack() looks for an English tooltip; tap the button instead.
        await tester.tap(find.byType(BackButton));
        await settle(tester);
      }
      // Phase 4 screens: budgets (with one budget), voice.
      await tester.tap(find.byIcon(Icons.savings_outlined));
      await settle(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await tester.tap(nav.at(0));
      await settle(tester);
      // The savings hint makes Home taller than a 360dp screen: scroll the action into view.
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.mic_none));
      await settle(tester);
      await tester.tap(find.byType(CloseButton));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
