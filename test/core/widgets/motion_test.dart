import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/app/shell.dart';
import 'package:hisab/app/theme/app_theme.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/core/widgets/motion.dart';
import 'package:hisab/core/widgets/save_morph_button.dart';

/// Animations (D20): they run to the right end state, keep tab state, and
/// switch off when the system asks for no animations.
void main() {
  String tk(Money m) => '৳${m.paisa ~/ 100}';

  Widget host(Widget child, {bool reduced = false}) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );

  testWidgets('a money figure counts up from zero, then runs to a new value', (tester) async {
    await tester.pumpWidget(host(CountUpMoney(value: Money.fromTaka(1000), format: tk)));
    expect(find.text('৳0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!.substring(1));
    expect(mid, inExclusiveRange(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('৳1000'), findsOneWidget);

    await tester.pumpWidget(host(CountUpMoney(value: Money.fromTaka(650), format: tk)));
    await tester.pump(const Duration(milliseconds: 300));
    final down = int.parse(tester.widget<Text>(find.byType(Text)).data!.substring(1));
    expect(down, inExclusiveRange(650, 1000), reason: 'runs down from the old value, not from zero');
    await tester.pumpAndSettle();
    expect(find.text('৳650'), findsOneWidget);
  });

  testWidgets('with animations off the figure shows its value at once', (tester) async {
    await tester.pumpWidget(host(CountUpMoney(value: Money.fromTaka(1000), format: tk), reduced: true));
    await tester.pump();
    expect(find.text('৳1000'), findsOneWidget);
  });

  testWidgets('save button: tick first, then onDone', (tester) async {
    var done = 0;
    Widget button(SaveButtonPhase phase) => host(SizedBox(
      width: 300,
      child: SaveMorphButton(label: 'Save', phase: phase, onPressed: () {}, onDone: () => done++),
    ));
    await tester.pumpWidget(button(SaveButtonPhase.idle));
    expect(find.text('Save'), findsOneWidget);
    await tester.pumpWidget(button(SaveButtonPhase.busy));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(button(SaveButtonPhase.done));
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, 0, reason: 'the screen stays until the tick is drawn');
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(tester.getSize(find.byType(AnimatedContainer)).width, SaveMorphButton.height);
  });

  testWidgets('switching tabs keeps each tab\'s state and hides the old one after the fade', (tester) async {
    Widget tabs(int i) => host(SizedBox(
      width: 300,
      height: 300,
      child: AnimatedBranchContainer(currentIndex: i, children: const [_Counter('a'), _Counter('b')]),
    ));
    await tester.pumpWidget(tabs(0));
    await tester.tap(find.text('a 0'));
    await tester.pump();
    expect(find.text('a 1'), findsOneWidget);

    await tester.pumpWidget(tabs(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('a 1'), findsOneWidget, reason: 'the old tab is still fading out');
    await tester.pumpAndSettle();
    expect(find.text('a 1'), findsNothing);
    expect(find.text('b 0'), findsOneWidget);

    await tester.pumpWidget(tabs(0));
    await tester.pumpAndSettle();
    expect(find.text('a 1'), findsOneWidget, reason: 'state survives the switch');
  });

  testWidgets('a new row opens up from nothing; an old one is there at once', (tester) async {
    Widget rows() => host(const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RowReveal(animate: false, child: SizedBox(height: 40, child: Text('old'))),
        RowReveal(animate: true, child: SizedBox(height: 40, child: Text('new'))),
      ],
    ));
    await tester.pumpWidget(rows());
    expect(tester.getSize(find.byType(RowReveal).first).height, 40);
    expect(tester.getSize(find.byType(RowReveal).last).height, lessThan(5));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(RowReveal).last).height, 40);
  });
}

class _Counter extends StatefulWidget {
  const _Counter(this.name);

  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) =>
      Center(child: TextButton(onPressed: () => setState(() => n++), child: Text('${widget.name} $n')));
}
