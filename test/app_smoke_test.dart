import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => pumpHisab(tester);

  testWidgets('starts in Bangla with five nav items and a live zero balance', (tester) async {
    await pumpApp(tester);
    for (final label in ['হোম', 'ইতিহাস', 'যোগ করুন', 'রিপোর্ট', 'আরও']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('মোট ব্যালেন্স'), findsOneWidget);
    expect(find.text('৳০'), findsWidgets);
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
  });

  testWidgets('Add opens full-screen and closes back to the same tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('যোগ করুন'));
    await settle(tester);
    expect(find.byType(CloseButton), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await settle(tester);
    expect(find.text('মোট ব্যালেন্স'), findsOneWidget);
  });

  testWidgets('categories screen lists seeded categories in Bangla', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('আরও'));
    await settle(tester);
    await tester.tap(find.text('ক্যাটাগরি'));
    await settle(tester);
    expect(find.text('বাজার ও মুদি'), findsOneWidget);
    expect(find.text('যাতায়াত'), findsOneWidget);
  });
}
