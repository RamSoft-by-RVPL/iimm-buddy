import 'dart:convert';

import 'package:attendance_planner/changes.dart';
import 'package:attendance_planner/exams.dart';
import 'package:attendance_planner/menu.dart';
import 'package:attendance_planner/planner.dart';
import 'package:flutter_test/flutter_test.dart';

Seen c(int day, String start, String course,
        {String room = '201', bool sheet = false}) =>
    Seen(DateTime(2026, 11, day), start, '', course, room, sheet);

void main() {
  // Tue 17 Nov 2026, 08:00.
  final now = DateTime(2026, 11, 17, 8);
  final week = [
    c(17, '10:00', 'Marketing'),
    c(17, '14:00', 'Statistics'),
    c(18, '10:00', 'Finance'),
    c(19, '10:00', 'Marketing'),
    c(20, '14:00', 'Economics'),
  ];

  test('class changes: moved, cancelled, room, added', () {
    final after = [
      c(17, '10:00', 'Marketing', room: '305'), // room changed
      c(17, '14:00', 'Statistics'),
      c(18, '15:00', 'Finance'), // moved within the day
      // Marketing on the 19th cancelled
      c(20, '14:00', 'Economics'),
      c(20, '16:00', 'Law'), // extra class
    ];
    final got = classChanges(week, after, now);
    expect(got.map((x) => x.title), [
      'Room changed: Marketing',
      'Class moved: Finance',
      'Class cancelled: Marketing',
      'Extra class: Law',
    ]);
    expect(got[0].body, 'Tue 17 Nov, 10:00. Now in Room 305, not Room 201.');
    expect(
        got[1].body, 'Wed 18 Nov, 10:00 is now Wed 18 Nov, 15:00 · Room 201.');
    expect(got[2].body, 'Thu 19 Nov, 10:00 is off the timetable.');
    // Keys stay the same, so one change is listed once.
    expect(classChanges(week, after, now).map((x) => x.key),
        got.map((x) => x.key));
  });

  test('class changes: nothing said when nothing really changed', () {
    // Same classes.
    expect(classChanges(week, week, now), isEmpty);
    // First run, or a failed reading with no classes.
    expect(classChanges([], week, now), isEmpty);
    expect(classChanges(week, [], now), isEmpty);
    // A later week arriving is news, not a change.
    expect(
        classChanges(week, [...week, c(24, '10:00', 'Finance')], now), isEmpty);
    // A class from the sheet only had a guessed room.
    final guessed = [c(19, '10:00', 'Marketing', room: '201', sheet: true)];
    final real = [c(19, '10:00', 'Marketing', room: '404')];
    expect(classChanges(guessed, real, now), isEmpty);
    // Classes already over do not count.
    final later = DateTime(2026, 11, 18, 12);
    expect(
        classChanges(week, week.where((s) => s.date.day != 17).toList(), later),
        isEmpty);
  });

  test('class changes: the portal filling in the sheet\'s week is no news', () {
    // Mon 23 Nov 2026: the week came from the mailed sheet; that morning the
    // portal put up some of it, under its own course names, and not the rest.
    final mon = DateTime(2026, 11, 23, 9);
    Seen s(int day, String start, String course) =>
        c(day, start, course, room: '404', sheet: true);
    final sheet = [
      s(23, '10:40', 'Algorithms'),
      s(23, '14:00', 'Algorithms'),
      s(25, '09:00', 'Linear Algebra'),
      s(25, '14:00', 'Algorithms'),
      s(26, '14:00', 'Algorithms'),
    ];
    final portal = [
      c(23, '10:40', 'Algorithms Theory'),
      c(23, '14:00', 'Algorithms Lab'),
      c(25, '09:00', 'Linear Algebra'),
      // 25th and 26th at 14:00: not on the portal (yet), gone from the list.
    ];
    expect(classChanges(sheet, portal, mon), isEmpty);
    // Once on the portal and then dropped: that is a cancellation.
    expect(classChanges(portal, portal.sublist(0, 2), mon).single.title,
        'Class cancelled: Linear Algebra');
  });

  test('class changes: many at once become one summary', () {
    final moved = [for (final s in week) c(s.date.day, '18:00', s.course)];
    final got = classChanges(week, moved, now, most: 3);
    expect(got.single.title, 'Timetable changed');
    expect(got.single.body, startsWith('5 classes in the coming week'));
  });

  test('class changes survive saving between refreshes', () {
    final back = decodeSeen(encodeSeen(week))!;
    expect(classChanges(week, back, now), isEmpty);
    expect(decodeSeen(null), isNull);
    expect(decodeSeen('not json'), isNull);
  });

  test('mess menu: days and the meal to show', () {
    final raw = jsonEncode({
      'updated': '2026-11-16T10:00:00Z',
      'weeks': [
        {
          'week': '2026-11-16',
          'days': [
            for (final d in ['2026-11-17', '2026-11-18'])
              {
                'd': d,
                'meals': [
                  {
                    'n': 'Breakfast',
                    'items': ['Poha', 'Tea']
                  },
                  {
                    'n': 'Lunch',
                    'items': ['Dal Fry', 'Rice']
                  },
                  {
                    'n': 'Snacks',
                    'items': ['Samosa']
                  },
                  {
                    'n': 'Dinner',
                    'items': ['Paneer']
                  },
                ]
              }
          ]
        }
      ]
    });
    final days = decodeMenu(raw);
    expect(days.length, 2);
    expect(days.first.date, DateTime(2026, 11, 17));
    String at(int h, int m) {
      final x = nextMeal(days, DateTime(2026, 11, 17, h, m));
      return x == null ? 'none' : '${x.$1.date.day} ${x.$2.name}';
    }

    expect(at(7, 0), '17 Breakfast');
    expect(at(11, 0), '17 Lunch');
    expect(at(16, 0), '17 Snacks');
    expect(at(19, 0), '17 Dinner');
    expect(at(22, 30), '18 Breakfast'); // after dinner: tomorrow
    expect(nextMeal(days, DateTime(2026, 11, 18, 23)), isNull); // no 19th
    // Before the menu starts, the card leads to its first day.
    expect(nextMeal(days, DateTime(2026, 11, 14, 12)), isNull);
    expect(firstMenuDay(days, DateTime(2026, 11, 14, 12))?.date,
        DateTime(2026, 11, 17));
    expect(firstMenuDay(days, DateTime(2026, 11, 19, 8)), isNull);
    expect(decodeMenu('oops'), isEmpty);
  });

  test('exam timetable: only my courses, with reminders', () {
    final courses = [
      Course(id: '1', name: 'Marketing Management', held: 10, attended: 9),
      Course(id: '2', name: 'Statistics for Business', held: 10, attended: 9),
    ];
    final raw = jsonEncode({
      'exams': [
        {
          'd': '2026-12-08',
          's': '10:00',
          'e': '13:00',
          'c': 'Marketing Management',
          'r': '101',
          'n': 'Section A'
        },
        {'d': '2026-12-09', 's': '14:00', 'e': '', 'c': 'Corporate Law'},
        {
          'd': '2026-12-07',
          's': '10:00',
          'e': '12:00',
          'c': 'Statistics for Business',
          'r': 'Hall 2'
        },
      ]
    });
    final mine = publishedExams(raw, courses);
    expect(mine.map((e) => e.course),
        ['Statistics for Business', 'Marketing Management']);
    expect(mine.every((e) => e.published), isTrue);
    expect(examWhere(mine[0]), '10:00 to 12:00 · Hall 2');
    expect(examWhere(mine[1]), '10:00 to 13:00 · Room 101');
    expect(mine[1].note, 'Section A');
    final r = publishedExamReminders(mine);
    expect(r.length, 4);
    expect(r[0].at, DateTime(2026, 12, 6, 19));
    expect(r[0].title, 'Exam tomorrow: Statistics for Business');
    expect(r[1].at, DateTime(2026, 12, 7, 9));
    expect(r.map((x) => x.id).toSet().length, 4);
    // Own exams keep their own numbers and are not saved with these.
    expect(publishedExams('bad', courses), isEmpty);
  });

  test('favourite dishes: matching despite spelling, and meal reminders', () {
    expect(isFavourite('Paneer Kolhapuri', ['Paneer']), isTrue);
    expect(isFavourite('Chicken Dum Biriyani', ['Biryani']), isTrue);
    expect(isFavourite('Paneer Dum Biryani', ['chicken biryani']), isFalse);
    expect(isFavourite('Veg Kolhapuri', ['Ice Cream']), isFalse);
    expect(isFavourite('Ice Cream', ['ice-cream']), isTrue);
    expect(isFavourite('Ice Cream', ['Ice Cream']), isTrue);
    expect(isFavourite('Egg Masala', ['Egg']), isTrue);
    expect(isFavourite('Eggless Cake', ['Egg']), isFalse);
    expect(isFavourite('Dal Fry', ['Dal Makhani']), isFalse);
    expect(isFavourite('Anything', []), isFalse);

    final days = [
      MenuDay(DateTime(2026, 11, 23), [
        Meal('Breakfast', ['Poha', 'Tea']),
        Meal('Lunch', ['Rajma Masala', 'Ice Cream']),
        Meal('Dinner', ['Paneer Kolhapuri', 'Butter Paneer', 'Rice']),
      ]),
      MenuDay(DateTime(2026, 11, 24), [
        Meal('Snacks', ['Samosa']),
      ]),
    ];
    final r = dishReminders(days, ['Paneer', 'Ice Cream']);
    expect(r.map((x) => x.title),
        ['Ice Cream at lunch today', 'Paneer Kolhapuri at dinner tonight']);
    expect(r[0].at, DateTime(2026, 11, 23, 12));
    expect(r[0].body, 'One of your favourites is on the menu.');
    expect(r[1].at, DateTime(2026, 11, 23, 19, 15));
    expect(r[1].body, 'Paneer Kolhapuri and Butter Paneer are on the menu.');
    expect(r[1].open, 'menu');
    expect(r.map((x) => x.id).toSet().length, 2);
    expect(dishReminders(days, []), isEmpty);
  });
}
