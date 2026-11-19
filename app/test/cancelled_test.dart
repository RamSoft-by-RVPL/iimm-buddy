import 'package:attendance_planner/changes.dart';
import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/sheet.dart';
import 'package:attendance_planner/site.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final d = DateTime(2026, 11, 20);
  ClassSlot slot(int id, String start, String course, String cid,
          {String status = 'Not Marked', DateTime? on, bool? upcoming}) =>
      ClassSlot(id, on ?? d, start, '${start.substring(0, 2)}:30', '404',
          course, cid, status, upcoming ?? status == 'Not Marked');
  Snapshot snapOf(List<ClassSlot> sessions) => Snapshot(
        studentName: 'A',
        roll: '1',
        courses: [
          Course(
              id: 'pf',
              name: 'Programming Fundamentals',
              held: 10,
              attended: 9,
              pending: 1,
              upcoming: [d, d]),
          Course(
              id: 'lac',
              name: 'Linear Algebra and Calculus',
              held: 10,
              attended: 9,
              upcoming: [d]),
          Course(
              id: 'pad',
              name: 'Principles of Algorithm Design',
              held: 5,
              attended: 5),
        ],
        syncedAt: d,
        sessions: sessions,
      );
  final snap = snapOf([
    slot(1, '09:00', 'Programming Fundamentals', 'pf'),
    slot(2, '10:40', 'Linear Algebra and Calculus', 'lac'),
    slot(3, '14:00', 'Programming Fundamentals', 'pf', status: 'Present'),
  ]);
  List<int> off(Snapshot s) => [
        for (final x in s.sessions)
          if (x.cancelled) x.id
      ];

  test('a cancelled class is shown as cancelled and not counted', () {
    final c = Cancelled.decode(
        '{"classes":[{"id":"1","d":"2026-11-20","s":"09:00","c":"Programming Fundamentals","why":"faculty unwell"}]}');
    final s = snap.withCancelled(c);
    expect(s.sessions.length, 3); // still on the timetable
    expect(off(s), [1]);
    expect(s.sessions.first.why, 'faculty unwell');
    expect([for (final x in s.next) x.id], [2]); // no reminder, not next
    expect(s.courses.first.upcoming.length, 1); // one class fewer to come
  });

  test('an unmarked class that was cancelled is not counted as held', () {
    final past = snapOf([
      slot(5, '09:00', 'Programming Fundamentals', 'pf', upcoming: false),
    ]);
    final s = past.withCancelled([Cancelled(d, '09:00', '')]);
    expect(s.courses.first.held, 9);
    expect(s.courses.first.pending, 0);
    expect(s.sessions.single.unmarked, isFalse);
  });

  test('empty course cancels every class at that time', () {
    expect(off(snap.withCancelled([Cancelled(d, '10:40', '')])), [2]);
  });

  test('another course at that time, another day, or a marked class stay', () {
    expect(
        off(snap.withCancelled(
            [Cancelled(d, '09:00', 'Linear Algebra and Calculus')])),
        isEmpty);
    expect(
        off(snap
            .withCancelled([Cancelled(DateTime(2026, 11, 21), '09:00', '')])),
        isEmpty);
    expect(off(snap.withCancelled([Cancelled(d, '14:00', '')])), isEmpty);
  });

  test('a bad answer cancels nothing', () {
    expect(Cancelled.decode('oops'), isEmpty);
    expect(Cancelled.decode(null), isEmpty);
  });

  test('the change check announces it as cancelled', () {
    final now = DateTime(2026, 11, 19, 12);
    final before = comingClasses(snap.next, now);
    final after = comingClasses(
        snap.withCancelled([Cancelled(d, '09:00', '')]).next, now);
    expect(classChanges(before, after, now).single.title,
        'Class cancelled: Programming Fundamentals');
  });

  group('classes that drop off the attendance site', () {
    final now = DateTime(2026, 11, 19, 12);
    final before = snapOf([
      slot(1, '09:00', 'Programming Fundamentals', 'pf'),
      slot(2, '10:40', 'Linear Algebra and Calculus', 'lac'),
    ]);

    test('a coming class that disappears is cancelled', () {
      final after =
          snapOf([slot(2, '10:40', 'Linear Algebra and Calculus', 'lac')]);
      final gone = vanishedClasses(before, after, now);
      expect([for (final g in gone) g.course], ['Programming Fundamentals']);
      // Shown again as cancelled, and the mailed sheet cannot bring it back.
      final shown = after.withGone(gone);
      expect(shown.sessions.length, 2);
      expect(shown.sessions.first.cancelled, isTrue);
      expect(shown.next.length, 1);
    });

    test('a class that moved to another time is not cancelled', () {
      final after = snapOf([
        slot(7, '15:40', 'Programming Fundamentals', 'pf'),
        slot(2, '10:40', 'Linear Algebra and Calculus', 'lac'),
      ]);
      expect(vanishedClasses(before, after, now), isEmpty);
    });

    test('past classes and an empty reading say nothing', () {
      expect(vanishedClasses(before, snapOf([]), now), isEmpty);
      final later = DateTime(2026, 11, 21);
      expect(
          vanishedClasses(before,
              snapOf([slot(2, '10:40', 'Linear Algebra', 'lac')]), later),
          isEmpty);
    });
  });

  test('a sheet class the site dropped on a day it published is cancelled', () {
    final now = DateTime(2026, 11, 19, 17);
    final d19 = DateTime(2026, 11, 19);
    final site = snapOf([
      slot(1, '09:00', 'Programming Fundamentals', 'pf',
          on: d19, upcoming: false),
      slot(2, '10:40', 'Linear Algebra and Calculus', 'lac'), // 20 Nov
    ]);
    final full = site.withSheet([
      SheetClass(d19, '09:00', '10:30', 'Programming Fundamentals', 'X'),
      SheetClass(d19, '10:40', '12:10', 'Programming Fundamentals', 'X'),
      SheetClass(d19, '14:00', '15:30', 'Linear Algebra and Calculus', 'Y'),
      SheetClass(
          d19, '15:40', '17:10', 'Principles of Algorithm Design', 'HPE'),
      SheetClass(DateTime(2026, 11, 23), '09:00', '10:30',
          'Programming Fundamentals', 'X'),
    ], now);
    String state(String day, String start) {
      final s = full.sessions
          .firstWhere((x) => x.date.day == int.parse(day) && x.start == start);
      return s.cancelled ? 'cancelled' : (s.fromSheet ? 'sheet' : 'site');
    }

    expect(state('19', '09:00'), 'site');
    expect(state('19', '10:40'), 'cancelled'); // the site dropped it
    expect(state('19', '14:00'), 'cancelled'); // listed ahead, but not then
    expect(state('19', '15:40'), 'sheet'); // reaches the site only later
    expect(state('23', '09:00'), 'sheet'); // not published on the site yet
  });
}
