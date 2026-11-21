import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/app.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/providers.dart';
import 'package:hisab/core/services/local_prefs.dart';

import 'app_smoke_test.dart' show settle, disposeApp;
import 'helpers/test_db.dart';

/// Every main screen must lay out without overflow on a small phone
/// (360×740 dp), in both languages.
void main() {
  for (final lang in ['bn', 'en']) {
    testWidgets('no overflow on a 360dp phone ($lang)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3; // 360×740 dp
      addTearDown(tester.view.reset);
      final db = await tester.runAsync(openTestDb) as AppDatabase;
      addTearDown(db.close);
      await tester.runAsync(() => db.settingsDao.put('language', lang, 0));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPrefsProvider.overrideWithValue(InMemoryLocalPrefs()),
        ],
        retry: (_, _) => null,
        child: const HisabApp(),
      ));
      await settle(tester);

      final nav = find.byType(NavigationDestination);
      for (final i in [1, 3, 4, 0]) {
        await tester.tap(nav.at(i));
        await settle(tester);
      }
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
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    });
  }
}
