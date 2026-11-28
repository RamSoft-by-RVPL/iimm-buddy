// The moving parts: they end exactly at rest, leave taps alone and stand
// still when the phone asks for less motion.

import 'package:attendance_planner/glass.dart';
import 'package:attendance_planner/mascot.dart';
import 'package:attendance_planner/motion.dart';
import 'package:attendance_planner/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {bool still = false}) => MaterialApp(
    theme: appTheme(Brightness.light),
    home: Builder(
        builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(body: Center(child: child)))));

Matrix4 leanOf(WidgetTester t) => t
    .widget<Transform>(find.descendant(
        of: find.byType(Tilt), matching: find.byType(Transform)))
    .transform;

void main() {
  test('the glass keeps the minimum at one height', () {
    expect(glassLevel(85, 85), 0.6);
    expect(glassLevel(100, 85), 1);
    expect(glassLevel(0, 85), 0);
    expect(glassLevel(92.5, 85), closeTo(0.8, 1e-9));
    expect(glassLevel(42.5, 85), closeTo(0.3, 1e-9));
    expect(glassLevel(120, 85), 1);
    expect(glassLevel(50, 0), 0.5);
    expect(glassLevel(100, 100), 0.6);
    for (var p = 1; p <= 100; p++) {
      expect(
          glassLevel(p.toDouble(), 85), greaterThan(glassLevel(p - 1.0, 85)));
    }
  });

  testWidgets('a pressed card leans, then rests exactly flat', (t) async {
    var taps = 0;
    await t.pumpWidget(app(Tilt(
        child: GestureDetector(
            onTap: () => taps++,
            child: Container(width: 200, height: 100, color: Brand.pink)))));
    expect(leanOf(t), Matrix4.identity());

    final g = await t.startGesture(
        t.getTopLeft(find.byType(Container)) + const Offset(190, 90));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final m = leanOf(t);
    expect(m, isNot(Matrix4.identity()));
    // Pressed bottom right: that corner goes away from the viewer.
    expect(m.entry(3, 0), greaterThan(0));
    expect(m.entry(3, 1), greaterThan(0));

    await g.up();
    await t.pumpAndSettle();
    expect(leanOf(t), Matrix4.identity());
    expect(taps, 1);
  });

  testWidgets('a finger scrolling past lets the card go', (t) async {
    await t.pumpWidget(app(
        Tilt(child: Container(width: 200, height: 100, color: Brand.pink))));
    final g = await t.startGesture(
        t.getCenter(find.byType(Container)) + const Offset(80, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(leanOf(t), isNot(Matrix4.identity()));
    await g.moveBy(const Offset(0, 40));
    await t.pumpAndSettle();
    expect(leanOf(t), Matrix4.identity());
    await g.up();
  });

  testWidgets('with less motion asked for, nothing moves', (t) async {
    await t.pumpWidget(app(
        const Column(mainAxisSize: MainAxisSize.min, children: [
          Tilt(child: SizedBox(width: 100, height: 100)),
          LemonGlass(percent: 90, min: 85),
          Crony(play: true),
          TabTurn(index: 0, child: SizedBox(width: 10, height: 10)),
        ]),
        still: true));
    await t.pump();
    expect(
        find.descendant(
            of: find.byType(Tilt), matching: find.byType(Transform)),
        findsNothing);
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.tap(find.byType(Crony));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the glass pours and then stands still', (t) async {
    await t.pumpWidget(app(const LemonGlass(percent: 90, min: 85)));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the glass sloshes when its card is pressed', (t) async {
    await t.pumpWidget(app(const Tilt(
        child: ColoredBox(
            color: Brand.pink,
            child: SizedBox(
                width: 200,
                height: 100,
                child: Center(child: LemonGlass(percent: 90, min: 85)))))));
    await t.pumpAndSettle();
    final g = await t
        .startGesture(t.getTopLeft(find.byType(Tilt)) + const Offset(190, 50));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isTrue);
    await g.up();
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Crony spins on a tap only where it may play', (t) async {
    await t.pumpWidget(app(const Crony(size: 100)));
    await t.pumpAndSettle();
    await t.tap(find.byType(Crony));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);

    await t.pumpWidget(app(const Crony(size: 100, play: true)));
    await t.pumpAndSettle();
    await t.tap(find.byType(Crony));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Crony turns under a finger and comes back', (t) async {
    await t.pumpWidget(app(const Crony(size: 100, play: true)));
    await t.pumpAndSettle();
    await t.drag(find.byType(Crony), const Offset(60, 0));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Crony nods when its mood changes', (t) async {
    await t.pumpWidget(app(const Crony(mood: Mood.happy)));
    await t.pumpAndSettle();
    await t.pumpWidget(app(const Crony(mood: Mood.worried)));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tab comes in from the side it sits on', (t) async {
    Matrix4 turn() => t
        .widget<Transform>(find.descendant(
            of: find.byType(TabTurn), matching: find.byType(Transform)))
        .transform;
    Widget tab(int i) => app(TabTurn(index: i, child: Text('tab $i')));
    await t.pumpWidget(tab(0));
    await t.pumpAndSettle();
    await t.pumpWidget(tab(2));
    await t.pump(const Duration(milliseconds: 60));
    expect(turn().getTranslation().x, greaterThan(0));
    await t.pumpAndSettle();
    expect(turn(), Matrix4.identity());
    await t.pumpWidget(tab(1));
    await t.pump(const Duration(milliseconds: 60));
    expect(turn().getTranslation().x, lessThan(0));
    await t.pumpAndSettle();
    expect(find.text('tab 1'), findsOneWidget);
  });

  testWidgets('a pushed screen slides over and back', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: Text('first'))));
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('second'))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getTopLeft(find.text('second')).dx, greaterThan(0));
    expect(find.text('first'), findsOneWidget);
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('second')).dx, 0);
    nav.pop();
    await t.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(t.getTopLeft(find.text('first')).dx, 0);
  });

  testWidgets('a bar with no amount keeps flowing, then fills and rests',
      (t) async {
    await t.pumpWidget(app(const SizedBox(width: 200, child: LiquidBar())));
    await t.pump(const Duration(seconds: 5));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpWidget(
        app(const SizedBox(width: 200, child: LiquidBar(value: 0.4))));
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a loading glass fills over and over', (t) async {
    await t.pumpWidget(app(const LemonGlass.loading()));
    await t.pump(const Duration(seconds: 6));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpWidget(app(const LemonGlass.loading(), still: true));
    await t.pump();
  });

  testWidgets('the glass follows a new figure and settles', (t) async {
    await t.pumpWidget(app(const LemonGlass(percent: 90, min: 85)));
    await t.pumpAndSettle();
    await t.pumpWidget(app(const LemonGlass(percent: 82, min: 85)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the drink in a card moves when the page is scrolled', (t) async {
    await t.pumpWidget(app(ListView(children: [
      const Sticker(child: SizedBox(height: 120, child: Text('next class'))),
      for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('row $i')),
    ])));
    await t.pumpAndSettle();
    expect(find.text('next class'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, -40));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a card stands up as its screen arrives, then lies flat',
      (t) async {
    Matrix4 stand() => t
        .widget<Transform>(find
            .descendant(
                of: find.byType(TiltCard), matching: find.byType(Transform))
            .first)
        .transform;
    await t.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: Text('first'))));
    t.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute(
        builder: (_) => const Scaffold(
            body: TiltCard(child: SizedBox(height: 80, child: Text('card'))))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(stand(), isNot(Matrix4.identity()));
    await t.pumpAndSettle();
    expect(stand(), Matrix4.identity());
    expect(find.text('card'), findsOneWidget);
  });

  testWidgets('the line under the top bar shows once the page has moved',
      (t) async {
    await t.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
            appBar: AppBar(title: const Text('t'), bottom: const LiquidEdge()),
            body: ListView(children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ]))));
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.drag(find.byType(ListView), const Offset(0, -200));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the tube says what it holds, whatever the course length',
      (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(app(const SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Straw(attended: 24, missed: 5, pending: 1, total: 40, min: 85),
          // A stale length shorter than the classes already held.
          Straw(attended: 9, missed: 3, total: 10, min: 85, bad: true),
          Straw(attended: 0, missed: 0, total: 0, min: 85),
          Drops(9),
        ]))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(
        find.bySemanticsLabel(
            '24 attended, 5 missed, 1 not marked yet, 10 to come'),
        findsOneWidget);
    expect(find.bySemanticsLabel('9 attended, 3 missed, 0 to come'),
        findsOneWidget);
    expect(find.bySemanticsLabel('0 attended, 0 missed, 0 to come'),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(Drops), matching: find.byType(Container)),
        findsNWidgets(6));
    semantics.dispose();
  });
}
