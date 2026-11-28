// Free time, friends' codes, attendance streaks, meal ratings, and the two
// moving parts that came with them.

import 'dart:convert';

import 'package:attendance_planner/backend.dart';
import 'package:attendance_planner/free.dart';
import 'package:attendance_planner/free_ui.dart';
import 'package:attendance_planner/glass.dart';
import 'package:attendance_planner/menu.dart';
import 'package:attendance_planner/menu_ui.dart';
import 'package:attendance_planner/ratings.dart';
import 'package:attendance_planner/site.dart';
import 'package:attendance_planner/streak.dart';
import 'package:attendance_planner/streak_ui.dart';
import 'package:attendance_planner/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final day = DateTime(2026, 11, 24); // a Tuesday
DateTime at(int h, int m, [int plus = 0]) =>
    DateTime(2026, 11, 24 + plus, h, m);

ClassSlot slot(int id, String start, String end,
        {int plus = 0,
        String status = 'Not Marked',
        bool upcoming = true,
        bool cancelled = false,
        bool fromSheet = false}) =>
    ClassSlot(id, DateTime(2026, 11, 24 + plus), start, end, '404', 'Course',
        'c1', status, upcoming,
        cancelled: cancelled, fromSheet: fromSheet);

Widget app(Widget child, {bool still = false}) => MaterialApp(
    theme: appTheme(Brightness.light),
    home: Builder(
        builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(body: child))));

void main() {
  group('free time', () {
    final classes = [
      slot(1, '09:00', '10:30'),
      slot(2, '10:40', '12:10'), // a ten-minute walk: one stretch with 1
      slot(3, '14:00', '15:30'),
      slot(4, '16:00', '17:00', cancelled: true),
      slot(5, '09:00', '10:30', plus: 1),
    ];
    final busy = busyOf(classes, at(8, 0));

    test('back-to-back classes are one stretch, a cancelled one is none', () {
      expect(busy.length, 3);
      expect(busy[0].from, at(9, 0));
      expect(busy[0].to, at(12, 10));
      expect(busy[1].from, at(14, 0));
      expect(busy[2].from, at(9, 0, 1));
      expect(busyOf(classes, at(8, 0), days: 1).length, 2);
    });

    test('before, during, between and after classes', () {
      var f = freeAt(busy, at(8, 15));
      expect(f.inClass, isFalse);
      expect(f.until, at(9, 0));
      expect(
          freeWords(f, at(8, 15)), ('Free till 09:00', '45 min to yourself'));

      f = freeAt(busy, at(9, 0));
      expect(f.inClass, isTrue);
      expect(f.until, at(12, 10));
      expect(f.then, at(14, 0));
      expect(freeWords(f, at(9, 0)),
          ('In class till 12:10', 'Then free till 14:00, 1 h 50 min'));

      f = freeAt(busy, at(12, 10));
      expect(f.inClass, isFalse, reason: 'free the minute the class ends');
      expect(freeWords(f, at(12, 10)),
          ('Free till 14:00', '1 h 50 min to yourself'));

      f = freeAt(busy, at(14, 30));
      expect(freeWords(f, at(14, 30)),
          ('In class till 15:30', 'Then you are done for the day'));

      f = freeAt(busy, at(15, 30));
      expect(f.done, isTrue);
      expect(freeWords(f, at(15, 30)),
          ('Done for the day', 'No more classes today'));

      f = freeAt(const [], at(11, 0));
      expect(f.classesToday, isFalse);
      expect(freeWords(f, at(11, 0)).$1, 'No classes today');
    });

    test('spans read naturally', () {
      expect(span(const Duration(seconds: 20)), '1 min');
      expect(span(const Duration(minutes: 59)), '59 min');
      expect(span(const Duration(minutes: 60)), '1 h');
      expect(span(const Duration(minutes: 135)), '2 h 15 min');
    });
  });

  group('friends', () {
    final mine = busyOf(
        [slot(1, '09:00', '10:30'), slot(2, '14:00', '15:30')], at(8, 0));
    Friend friend(List<List<String>> blocks, {DateTime? updated}) => Friend(
        'ABCD2345',
        'Meera',
        [
          for (final b in blocks)
            Busy(DateTime.parse('2026-11-24 ${b[0]}'),
                DateTime.parse('2026-11-24 ${b[1]}'))
        ],
        updated ?? at(7, 0));

    test('what is said about a friend depends on both timetables', () {
      final f = friend([
        ['11:00', '12:00'],
        ['13:00', '14:30']
      ]);
      expect(friendWords(f, mine, at(11, 30)), ('In class till 12:00', false));
      // Both free at 12:15: she till 13:00, I till 14:00.
      expect(
          friendWords(f, mine, at(12, 15)), ('Free with you till 13:00', true));
      // I am in class at 09:30, she is free till 11:00.
      expect(friendWords(f, mine, at(9, 30)), ('Free till 11:00', false));
      expect(friendWords(f, mine, at(16, 0)),
          ('Free with you for the rest of the day', true));
      expect(friendWords(friend([]), mine, at(9, 30)),
          ('Free for the rest of the day', false));
    });

    test('a timetable four days old says nothing about now', () {
      final f = friend([
        ['11:00', '12:00']
      ], updated: at(7, 0, -4));
      expect(friendWords(f, mine, at(11, 30)).$1,
          'No timetable from their phone lately');
      expect(friendWords(f, mine, at(11, 30)).$2, isFalse);
    });

    test('codes: what can be one, and how it is shown', () {
      expect(cleanCode('abcd-ef23'), 'ABCDEF23');
      expect(cleanCode(' ABCD EF23 '), 'ABCDEF23');
      expect(cleanCode('ABCDEF2'), isNull);
      expect(cleanCode('ABCDEF234'), isNull);
      expect(cleanCode('ABCDEF10'), isNull, reason: '1 and 0 are never used');
      expect(cleanCode('ABCDEFIO'), isNull, reason: 'I and O are never used');
      expect(showCode('ABCDEF23'), 'ABCD-EF23');
    });

    test('only a first name and time blocks leave the phone', () {
      final sent = jsonDecode(sharePayload(
          '0123456789abcdef',
          'Arjun Kumar Shah',
          busyOf([slot(1, '09:00', '10:30')], at(8, 0)))) as Map;
      expect(sent.keys.toSet(), {'action', 'user', 'name', 'busy'});
      expect(sent['name'], 'Arjun');
      expect(sent['busy'], [
        {'d': '2026-11-24', 's': '09:00', 'e': '10:30'}
      ]);
      expect(jsonEncode(sent).contains('Course'), isFalse);
      expect(jsonEncode(sent).contains('404'), isFalse);
    });

    test('the server\'s answer is read; a broken one gives no friends', () {
      final got = decodeFriends(jsonEncode({
        'friends': [
          {
            'code': 'ABCD2345',
            'name': 'Meera',
            'updated': '2026-11-24T01:30:00.000Z',
            'busy': [
              {'d': '2026-11-24', 's': '10:40', 'e': '12:10'},
              {'d': '2026-11-24', 's': '09:00', 'e': '10:30'},
              {'d': 'x', 's': '09:00', 'e': '10:30'},
            ]
          },
          {'code': 'EFGH6789', 'name': '', 'updated': 'x', 'busy': []},
        ]
      }));
      expect(got.length, 2);
      expect(got[0].busy.length, 1,
          reason: 'sorted and joined, bad row dropped');
      expect(got[0].busy.single.from, at(9, 0));
      expect(got[0].busy.single.to, at(12, 10));
      expect(got[1].name, 'A friend');
      expect(got[1].stale(at(9, 0)), isTrue);
      expect(decodeFriends('not json'), isEmpty);
      expect(decodeFriends(null), isEmpty);
    });

    test('a friend who stopped sharing drops out of the list', () async {
      SharedPreferences.setMockInitialValues({
        'friend_codes': ['ABCD2345', 'EFGH6789'],
        'friends': jsonEncode({
          'friends': [
            {
              'code': 'EFGH6789',
              'name': 'Kabir',
              'updated': '2026-11-24T01:30:00.000Z',
              'busy': []
            }
          ]
        })
      });
      final prefs = await SharedPreferences.getInstance();
      expect([for (final f in friendsOf(prefs)) f.name], ['Kabir']);
      await removeFriend(prefs, 'EFGH6789');
      expect(friendsOf(prefs), isEmpty);
      expect(friendCodes(prefs), ['ABCD2345']);
    });
  });

  group('streaks', () {
    // Days from Mon 16 Nov: P = all present, A = one absence, - = no class.
    List<ClassSlot> days(String marks) => [
          for (final (i, m) in marks.split('').indexed)
            if (m != '-') ...[
              ClassSlot(i * 2, DateTime(2026, 11, 16 + i), '09:00', '10:30',
                  '404', 'Course', 'c1', 'Present', false),
              ClassSlot(
                  i * 2 + 1,
                  DateTime(2026, 11, 16 + i),
                  '11:00',
                  '12:30',
                  '404',
                  'Course',
                  'c1',
                  m == 'A' ? 'Absent' : 'Present',
                  false),
            ]
        ];

    test('counts class days in a row and remembers the best run', () {
      var s = streakOf(days('PPPPP--PP'));
      expect((s.days, s.best, s.weeks), (7, 7, 2));
      expect(s.since, DateTime(2026, 11, 16));

      s = streakOf(days('PPPAP--PP'));
      expect((s.days, s.best, s.weeks), (3, 3, 1));
      expect(s.since, DateTime(2026, 11, 20));

      s = streakOf(days('PPPPP--PA'));
      expect((s.days, s.best, s.weeks), (0, 6, 0));
      expect(s.since, isNull);

      expect(streakOf(const []).days, 0);
    });

    test('unmarked, cancelled, sheet-only and coming classes do not count', () {
      final s = streakOf([
        ...days('PP'),
        ClassSlot(90, DateTime(2026, 11, 18), '09:00', '10:30', '404', 'Course',
            'c1', 'Not Marked', false),
        ClassSlot(91, DateTime(2026, 11, 19), '09:00', '10:30', '404', 'Course',
            'c1', 'Absent', false,
            cancelled: true),
        ClassSlot(92, DateTime(2026, 11, 20), '09:00', '10:30', '404', 'Course',
            'c1', 'Absent', false,
            fromSheet: true),
        ClassSlot(93, DateTime(2026, 11, 21), '09:00', '10:30', '404', 'Course',
            'c1', 'Absent', true),
      ]);
      expect(s.days, 2);
    });

    test('each milestone is cheered once, and again after a break', () {
      expect(milestoneReached(2, 0), isNull);
      expect(milestoneReached(3, 0), 3);
      expect(milestoneReached(4, 3), isNull);
      expect(milestoneReached(12, 0), 10, reason: 'only the highest one');
      expect(milestoneReached(12, 10), isNull);
      expect(cheeredAfter(12, 10), 10);
      expect(cheeredAfter(0, 10), 0);
      expect(cheeredAfter(4, 10), 3);
      expect(milestoneReached(5, cheeredAfter(4, 10)), 5);
      expect(nextMilestone(7), 10);
      expect(nextMilestone(100), isNull);
    });

    testWidgets('the chip shows from the second day and opens the sheet',
        (t) async {
      await t.pumpWidget(app(const Center(child: StreakChip(Streak(days: 1)))));
      expect(find.byType(LemonSlice), findsNothing);

      await t.pumpWidget(app(Center(
          child: StreakChip(Streak(
              days: 6, best: 9, weeks: 2, since: DateTime(2026, 11, 17))))));
      expect(find.text('6 days'), findsOneWidget);
      await t.tap(find.text('6 days'));
      await t.pumpAndSettle();
      expect(find.text('6 days in a row'), findsOneWidget);
      expect(find.text('9 days'), findsOneWidget);
      expect(find.text('At 10 days, 4 to go'), findsOneWidget);
    });

    testWidgets('the cheer plays once, then stops', (t) async {
      await t.pumpWidget(app(const SizedBox.expand(child: LemonBurst())));
      await t.pump();
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('the cheer stands still when the phone asks for less motion',
        (t) async {
      await t.pumpWidget(
          app(const SizedBox.expand(child: LemonBurst()), still: true));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('meal ratings', () {
    final menu = [
      MenuDay(DateTime(2026, 11, 23), [
        Meal('Breakfast', ['Poha']),
        Meal('Lunch', ['Rajma']),
        Meal('Dinner', ['Paneer'])
      ]),
      MenuDay(day, [
        Meal('Breakfast', ['Idli']),
        Meal('Lunch', ['Chole']),
        Meal('Dinner', ['Biryani'])
      ]),
    ];
    String raw(List<List<Object?>> rows) => jsonEncode({
          'ratings': [
            for (final r in rows)
              {'d': r[0], 'meal': r[1], 'n': r[2], 'avg': r[3], 'mine': r[4]}
          ]
        });

    test('a meal can be rated once it is being served, until the next night',
        () {
      expect(canRate(menu[1], 1, at(12, 0)), isFalse, reason: 'lunch at 12:10');
      expect(canRate(menu[1], 1, at(12, 10)), isTrue);
      expect(canRate(menu[1], 2, at(16, 0)), isFalse);
      expect(canRate(menu[0], 2, at(9, 0)), isTrue, reason: 'yesterday');
      expect(canRate(menu[0], 2, at(9, 0, 1)), isFalse, reason: 'two days on');
    });

    test('the home screen asks about the latest meal served today', () {
      expect(mealToRate(menu, at(7, 0)), isNull);
      var ask = mealToRate(menu, at(13, 0))!;
      expect(ask.$1.meals[ask.$2].name, 'Lunch');
      ask = mealToRate(menu, at(21, 0))!;
      expect(ask.$1.meals[ask.$2].name, 'Dinner');
      expect(mealToRate(menu, at(13, 0, 5)), isNull,
          reason: 'no menu that day');
    });

    test('best and worst need enough ratings and a difference', () {
      final all = decodeRatings(raw([
        ['2026-11-23', 'Lunch', 5, 2.8, null],
        ['2026-11-23', 'Dinner', 6, 1.4, 1],
        ['2026-11-24', 'Breakfast', 2, 1.0, null],
        ['2026-11-24', 'Lunch', 3, 2.0, null],
      ]));
      final (best, worst) = bestAndWorst(all)!;
      expect((best.meal, worst.meal), ('Lunch', 'Dinner'));
      expect(tasteLine(best, worst),
          'Best this week: Mon lunch. Worst: Mon dinner.');
      expect(bestAndWorst(all.take(1).toList()), isNull);
      expect(
          bestAndWorst(decodeRatings(raw([
            ['2026-11-23', 'Lunch', 5, 2.0, null],
            ['2026-11-23', 'Dinner', 5, 2.0, null],
          ]))),
          isNull);
      expect(scoreWord(1.4), 'Poor');
      expect(scoreWord(2.0), 'Okay');
      expect(scoreWord(2.5), 'Good');
      expect(decodeRatings('nope'), isEmpty);
    });

    testWidgets('the row asks, then shows what everyone said', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = Store(prefs);
      await t.pumpWidget(app(RateRow(store: store, day: day, meal: 'Lunch')));
      expect(find.text('How was lunch?'), findsOneWidget);
      expect(find.bySemanticsLabel('Good'), findsOneWidget);

      await prefs.setString(
          'ratings',
          raw([
            ['2026-11-24', 'Lunch', 12, 2.6, 3]
          ]));
      await t.pumpWidget(app(
          RateRow(store: store, day: day, meal: 'Lunch', key: UniqueKey())));
      expect(find.text('Good · 12 rated'), findsOneWidget);
    });
  });

  group('moving parts', () {
    testWidgets('pulling the page down far enough refreshes it once',
        (t) async {
      var refreshed = 0;
      await t.pumpWidget(app(GlassRefresh(
        onRefresh: () async => refreshed++,
        child: ListView(children: [
          for (var i = 0; i < 40; i++) SizedBox(height: 50, child: Text('$i'))
        ]),
      )));
      await t.drag(find.text('1'), const Offset(0, 40));
      await t.pumpAndSettle();
      expect(refreshed, 0, reason: 'a short pull is not a refresh');

      await t.drag(find.text('1'), const Offset(0, 200));
      await t.pump();
      await t.pumpAndSettle();
      expect(refreshed, 1);
      expect(t.hasRunningAnimations, isFalse);
      expect(find.byType(LemonGlass), findsNothing,
          reason: 'the glass is gone');

      await t.drag(find.text('1'), const Offset(0, -300));
      await t.pumpAndSettle();
      await t.drag(find.text('9'), const Offset(0, 200));
      await t.pumpAndSettle();
      expect(refreshed, 1, reason: 'scrolling back up is not a pull');
    });

    testWidgets('a pressed button sinks and comes back; the tap still lands',
        (t) async {
      var taps = 0;
      await t.pumpWidget(app(Center(
          child:
              FilledButton(onPressed: () => taps++, child: const Text('Go')))));
      Matrix4 sunk() => t
          .widget<Transform>(find
              .ancestor(of: find.text('Go'), matching: find.byType(Transform))
              .first)
          .transform;
      expect(sunk(), Matrix4.identity());
      final g = await t.startGesture(t.getCenter(find.text('Go')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(sunk().getTranslation().y, greaterThan(0));
      await g.up();
      await t.pumpAndSettle();
      expect(sunk(), Matrix4.identity());
      expect(taps, 1);
    });
  });

  group('through the screens, against a stand-in server', () {
    tearDown(() => apiStandIn = null);

    testWidgets('one tap rates a meal; a second tap changes the rating',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sent = <Map>[];
      apiStandIn = (method, url, body) async {
        final b = jsonDecode(body!) as Map;
        sent.add(b);
        return (
          200,
          jsonEncode({
            'ratings': [
              {
                'd': '2026-11-24',
                'meal': b['meal'],
                'n': 5,
                'avg': b['score'],
                'mine': b['score']
              }
            ]
          })
        );
      };
      var rated = 0;
      await t.pumpWidget(app(StatefulBuilder(
          builder: (context, set) => RateRow(
              store: Store(prefs),
              day: day,
              meal: 'Lunch',
              onRated: () => set(() => rated++)))));
      await t.tap(find.bySemanticsLabel('Good'));
      await t.pumpAndSettle();
      expect(sent.single['action'], 'rate');
      expect(sent.single['d'], '2026-11-24');
      expect(sent.single['score'], 3);
      expect(
          RegExp(r'^[0-9a-f]{16}$').hasMatch('${sent.single['user']}'), isTrue);
      expect(find.text('Good · 5 rated'), findsOneWidget);
      expect(rated, 1);

      await t.tap(find.bySemanticsLabel('Poor'));
      await t.pumpAndSettle();
      expect(sent.last['score'], 1);
      expect(find.text('Poor · 5 rated'), findsOneWidget);
    });

    testWidgets('a refused rating says why and changes nothing', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      apiStandIn = (method, url, body) async =>
          (400, jsonEncode({'error': 'That meal is not on the menu.'}));
      await t.pumpWidget(
          app(RateRow(store: Store(prefs), day: day, meal: 'Lunch')));
      await t.tap(find.bySemanticsLabel('Okay'));
      await t.pumpAndSettle();
      expect(find.text('That meal is not on the menu.'), findsOneWidget);
      expect(find.text('How was lunch?'), findsOneWidget);
      expect(prefs.getString('ratings'), isNull);
    });

    testWidgets('get a code, add a friend, stop sharing', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final log = <String>[];
      apiStandIn = (method, url, body) async {
        final b = body == null ? {} : jsonDecode(body) as Map;
        log.add('$method ${url.path} ${b['action'] ?? url.query}');
        if (method == 'POST' && b['action'] == 'share') {
          return (200, jsonEncode({'ok': true, 'code': 'KM7XQ2RD'}));
        }
        if (method == 'POST') return (200, jsonEncode({'ok': true}));
        return (
          200,
          jsonEncode({
            'friends': [
              if (url.queryParameters['codes']!.contains('ABCD2345'))
                {
                  'code': 'ABCD2345',
                  'name': 'Meera',
                  'updated': DateTime.now().toUtc().toIso8601String(),
                  'busy': []
                }
            ]
          })
        );
      };
      final snap = Snapshot(
          studentName: 'Arjun Shah',
          roll: '1',
          courses: const [],
          syncedAt: DateTime.now());
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: appTheme(Brightness.light),
          home: FriendsScreen(store: Store(prefs), snap: snap)));
      await t.pumpAndSettle();
      expect(find.text('Get my code'), findsOneWidget);
      expect(log, isEmpty, reason: 'nothing is sent before sharing is on');

      await t.tap(find.text('Get my code'));
      await t.pumpAndSettle();
      expect(find.text('KM7X-Q2RD'), findsOneWidget);
      expect(myCode(prefs), 'KM7XQ2RD');

      await t.enterText(find.byType(TextField), 'nonsense');
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(find.textContaining('8 letters and digits'), findsOneWidget);
      expect(friendCodes(prefs), isEmpty);

      await t.enterText(find.byType(TextField), 'zzzz-zzzz');
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(find.text('No one is sharing with that code right now.'),
          findsOneWidget);
      expect(friendCodes(prefs), isEmpty);

      await t.enterText(find.byType(TextField), 'abcd-2345');
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(find.text('Meera'), findsOneWidget);
      expect(
          find.text('Free with you for the rest of the day'), findsOneWidget);
      expect(friendCodes(prefs), ['ABCD2345']);

      await t.tap(find.byTooltip('Remove Meera'));
      await t.pumpAndSettle();
      expect(find.text('Meera'), findsNothing);

      await t.tap(find.text('Stop sharing'));
      await t.pumpAndSettle();
      expect(myCode(prefs), isNull);
      expect(log.last, 'POST /api/free stop');
      expect(find.text('Get my code'), findsOneWidget);
    });

    test('a changed timetable is sent again; an unchanged one is not',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var posts = 0;
      apiStandIn = (method, url, body) async {
        if (method == 'POST') posts++;
        return (200, jsonEncode({'ok': true, 'code': 'KM7XQ2RD'}));
      };
      final today = DateTime.now();
      Snapshot snap(String end) => Snapshot(
          studentName: 'Arjun Shah',
          roll: '1',
          courses: const [],
          syncedAt: today,
          sessions: [
            ClassSlot(1, DateTime(today.year, today.month, today.day), '09:00',
                end, '404', 'Course', 'c1', 'Not Marked', true)
          ]);
      await syncFree(prefs, snap('10:30'));
      expect(posts, 0, reason: 'sharing is off');
      await shareFree(prefs, snap('10:30'));
      expect(posts, 1);
      await syncFree(prefs, snap('10:30'));
      expect(posts, 1);
      await syncFree(prefs, snap('11:00'));
      expect(posts, 2);
    });
  });

  testWidgets('the free card names friends who are free now', (t) async {
    final now = DateTime.now();
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'friend_codes': ['ABCD2345'],
      'friends': jsonEncode({
        'friends': [
          {
            'code': 'ABCD2345',
            'name': 'Meera',
            'updated': now.toUtc().toIso8601String(),
            'busy': [
              {
                'd': d(now.add(const Duration(days: 1))),
                's': '09:00',
                'e': '10:00'
              }
            ]
          }
        ]
      })
    });
    final store = Store(await SharedPreferences.getInstance());
    final snap = Snapshot(
        studentName: 'Arjun Shah', roll: '1', courses: const [], syncedAt: now);
    await t.pumpWidget(app(ListView(children: [
      FreeCard(store: store, snap: snap),
    ])));
    expect(find.text('No classes today'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Free with you for the rest of the day'), findsOneWidget);
  });
}
