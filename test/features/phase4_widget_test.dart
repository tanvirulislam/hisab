import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/features/budgets/presentation/widgets/budget_widgets.dart';
import 'package:hisab/features/notifications/domain/notification_plan.dart';
import 'package:hisab/features/voice/data/speech_input.dart';

import '../helpers/app_harness.dart';
import '../helpers/fakes.dart';
import 'reports/dashboard_reports_widget_test.dart' show seed;

Future<List<TransactionRow>> _rows(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => db.select(db.transactions).get()))!;

Future<void> _openMore(WidgetTester tester, String item) async {
  await tester.tap(find.byType(NavigationDestination).at(4));
  await settle(tester);
  await tester.tap(find.text(item));
  await settle(tester);
}

void main() {
  const tall = Size(432, 1400);

  testWidgets('budget: add, live utilization, alert, dashboard card (§12, §5.1)', (tester) async {
    final notifications = RecordingNotifications();
    await pumpHisab(tester, logicalSize: tall, seed: seed, notifications: notifications);
    // No budget yet: the dashboard only prompts.
    expect(find.text('মাসিক বাজেট ঠিক করুন'), findsOneWidget);

    await _openMore(tester, 'বাজেট');
    expect(find.text('এই মাসে কোনো বাজেট নেই'), findsOneWidget);
    await tester.tap(find.text('বাজেট যোগ করুন').last);
    await settle(tester);
    await tester.tap(find.text('বাজার ও মুদি'));
    await tester.enterText(find.byType(TextField), '400');
    await tester.tap(find.text('সংরক্ষণ করুন'));
    await settle(tester);

    // Personal grocery: ৳350 (fish) of ৳400 = 87%, a warning.
    expect(find.text('৳৪০০ এর মধ্যে ৳৩৫০'), findsOneWidget);
    expect(find.text('৮৭%'), findsOneWidget);
    expect(find.text('৳৫০ বাকি'), findsWidgets);
    expect(notifications.permissionRequests, 1, reason: 'asked when the first budget is created');
    final alert = notifications.shown.single;
    expect(alert.title, 'বাজেট সতর্কতা: বাজার ও মুদি');
    expect(alert.payload, NoticePayload.budgets);

    expect(find.text('পরিবার'), findsNothing, reason: 'no workspace switcher (D14)');

    // Dashboard: remaining budget card.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.byType(NavigationDestination).at(0));
    await settle(tester);
    expect(find.text('এই মাসে বাকি বাজেট'), findsOneWidget);
    expect(find.byType(BudgetTile), findsOneWidget);
    // The same alert is not repeated.
    expect(notifications.shown, hasLength(1));
  });

  testWidgets('voice: microphone text → two proposals → confirm saves both (§9)', (tester) async {
    final speech = ScriptedSpeech(script: 'আজকে বাজারে মাছ কিনেছি ৩৫০ টাকা আর সবজি কিনেছি ১৫০ টাকা');
    final db = await pumpHisab(tester, logicalSize: tall, speech: speech);
    await tester.tap(find.text('ভয়েস'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await settle(tester);
    expect(speech.lastLocale, 'bn_BD');
    expect(find.text(speech.script), findsOneWidget, reason: 'recognised text is displayed');

    await tester.tap(find.text('পরবর্তী'));
    await settle(tester);
    expect(find.byKey(const ValueKey('proposal-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-1')), findsOneWidget);
    expect(find.textContaining('মাছ'), findsWidgets);
    expect(await _rows(tester, db), isEmpty, reason: 'nothing is saved before confirming');

    await tester.tap(find.text('২টি সংরক্ষণ করুন'));
    await settleBrief(tester);
    final rows = await _rows(tester, db);
    expect(rows.map((r) => r.amountPaisa).toList()..sort(), [15000, 35000]);
    expect(rows.every((r) => r.source == 'voice'), isTrue);
    expect(find.text('২টি লেনদেন সংরক্ষিত হয়েছে'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // let the toast close itself
    expect(find.text('২টি লেনদেন সংরক্ষিত হয়েছে'), findsNothing);
  });

  testWidgets('voice: permission denied still allows typing; items can be left out', (tester) async {
    final speech = ScriptedSpeech(failure: SpeechFailure.permissionDenied);
    final db = await pumpHisab(tester, logicalSize: tall, speech: speech);
    await tester.tap(find.text('ভয়েস'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await settle(tester);
    expect(find.textContaining('মাইক্রোফোনের অনুমতি'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('voice-text')), 'রিকশা ৫০ টাকা আর চা ২০ টাকা');
    await tester.pump(); // rebuild so Continue is enabled
    await tester.tap(find.text('পরবর্তী'));
    await settle(tester);
    // Leave the tea out.
    await scrollTo(tester, find.byKey(const ValueKey('proposal-1')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('proposal-1')), matching: find.byType(Checkbox)));
    await settle(tester);
    await tester.tap(find.text('১টি সংরক্ষণ করুন'));
    await settle(tester);
    final rows = await _rows(tester, db);
    expect(rows.single.amountPaisa, 5000);
  });

  testWidgets('settings: reminder needs permission and schedules two weeks (§15)', (tester) async {
    final notifications = RecordingNotifications()..permitted = false;
    await pumpHisab(tester, logicalSize: tall, notifications: notifications);
    await _openMore(tester, 'সেটিংস');
    await scrollTo(tester, find.text('দৈনিক রিমাইন্ডার'));
    await tester.tap(find.text('দৈনিক রিমাইন্ডার'));
    await settleBrief(tester);
    expect(find.textContaining('নোটিফিকেশন বন্ধ'), findsOneWidget);
    expect(notifications.scheduled.keys.where((id) => id < NoticeIds.monthlySummary), isEmpty);

    notifications.permitted = true;
    await tester.tap(find.text('দৈনিক রিমাইন্ডার'));
    await settle(tester);
    final reminders = notifications.scheduled.values.where((n) => n.id < NoticeIds.monthlySummary).toList();
    expect(reminders, hasLength(NoticeIds.reminderDays));
    expect(reminders.first.title, 'আজকের খরচ লিখেছেন?');
    expect(reminders.map((n) => n.at!.hour).toSet(), {21});
    // The monthly summary is on by default.
    expect(notifications.scheduled[NoticeIds.monthlySummary]?.payload, 'summary:202611');
  });
}
