import 'package:attendance_planner/acal.dart';
import 'package:attendance_planner/backend.dart';
import 'package:attendance_planner/moodle.dart' show Deadline;
import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/polls_ui.dart';
import 'package:attendance_planner/site.dart';
import 'package:attendance_planner/week_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClassSlot slot(int id, DateTime d, String start, String course, String cid,
          {bool cancelled = false}) =>
      ClassSlot(id, d, start, '${start.substring(0, 2)}:30', '404', course, cid,
          'Not Marked', true,
          cancelled: cancelled);
  Snapshot snapOf(List<ClassSlot> s, {List<Course>? courses}) => Snapshot(
      studentName: 'A',
      roll: '1',
      courses: courses ??
          [
            Course(
                id: 'pf',
                name: 'Programming Fundamentals',
                held: 10,
                attended: 9),
            Course(
                id: 'dvs',
                name: 'Data Visualization and Storytelling',
                held: 14,
                attended: 11),
          ],
      syncedAt: DateTime(2026, 11, 22),
      sessions: s);

  group('classes the CR added or moved', () {
    final mon = DateTime(2026, 11, 23);
    final now = DateTime(2026, 11, 22, 12);

    test('an added class shows, with reminders, until the site lists it', () {
      final s =
          snapOf([slot(1, mon, '09:00', 'Programming Fundamentals', 'pf')])
              .withExtra([
        ExtraClass(7, mon, '14:00', '15:30', 'Programming Fundamentals',
            room: '302', why: 'Make-up class')
      ], now);
      expect(s.sessions.length, 2);
      final added = s.sessions.last;
      expect(
          [added.start, added.room, added.why, added.courseId, added.fromSheet],
          ['14:00', '302', 'Make-up class', 'pf', true]);
      expect(s.next.length, 2);
    });

    test('not twice once the site lists it at that time', () {
      final s = snapOf([
        slot(1, mon, '09:00', 'Programming Fundamentals', 'pf'),
        slot(2, mon, '14:00', 'Programming Fundamentals', 'pf'),
      ]).withExtra(
          [ExtraClass(7, mon, '14:00', '15:30', 'Programming Fundamentals')],
          now);
      expect(s.sessions.length, 2);
    });

    test('a move: the old time cancelled, the new one added', () {
      final s = snapOf(
          [slot(1, mon, '09:00', 'Programming Fundamentals', 'pf')]).withExtra([
        ExtraClass(7, DateTime(2026, 11, 24), '11:00', '12:30',
            'Programming Fundamentals',
            why: 'Moved from Mon 23 Nov, 09:00', moved: true)
      ], now).withCancelled(
          [Cancelled(mon, '09:00', 'Programming Fundamentals', 'Moved')]);
      expect([for (final x in s.sessions) x.cancelled], [true, false]);
      expect(s.next.single.start, '11:00');
    });
  });

  group('Sunday summary', () {
    test('it goes out on Sunday at 7 PM', () {
      expect(nextSummaryTime(DateTime(2026, 11, 19, 10)),
          DateTime(2026, 11, 22, 19));
      expect(nextSummaryTime(DateTime(2026, 11, 22, 18)),
          DateTime(2026, 11, 22, 19));
      expect(nextSummaryTime(DateTime(2026, 11, 22, 20)),
          DateTime(2026, 11, 29, 19));
    });

    test('classes, a holiday, deadlines and a course to watch', () {
      final r = weekSummary(
        at: DateTime(2026, 11, 22, 19),
        snap: snapOf([
          slot(1, DateTime(2026, 11, 23), '09:00', 'Programming Fundamentals',
              'pf'),
          slot(2, DateTime(2026, 11, 23), '11:00', 'Programming Fundamentals',
              'pf'),
          slot(3, DateTime(2026, 11, 25), '09:00', 'Programming Fundamentals',
              'pf'),
          slot(4, DateTime(2026, 11, 26), '09:00', 'Programming Fundamentals',
              'pf',
              cancelled: true),
          slot(5, DateTime(2026, 11, 30), '09:00', 'Programming Fundamentals',
              'pf'),
        ]),
        minPct: 85,
        calendar: [
          TermEvent('Guru Nanak Birthday', DateTime(2026, 11, 24),
              DateTime(2026, 11, 24), 'holiday', '')
        ],
        deadlines: [
          Deadline(
              1, 'PF lab file', DateTime(2026, 11, 25, 23, 59), 'PF', '', ''),
          Deadline(2, 'Old one', DateTime(2026, 11, 20), 'PF', '', ''),
        ],
        short: (c) => c.startsWith('Data') ? 'DVS' : c,
      );
      expect(r.title, 'Your week ahead');
      expect(r.at, DateTime(2026, 11, 22, 19));
      final lines = r.body.split('\n');
      expect(lines[0], '3 classes: Mon 2, Wed 1.');
      expect(lines[1], 'Holiday Tue 24 Nov: Guru Nanak Birthday.');
      expect(lines[2], 'Due: PF lab file (Wed).');
      expect(lines[3], 'Programming Fundamentals: no leave left, don\'t skip.');
      expect(lines[4], startsWith('DVS is at 78.6%: attend all of the next'));
    });

    test('before the timetable is out', () {
      final r = weekSummary(
          at: DateTime(2026, 11, 22, 19),
          snap: snapOf([]),
          minPct: 85,
          short: (c) => c);
      expect(r.body,
          startsWith('Classes: the timetable for the week is not out yet.'));
    });
  });

  group('polls', () {
    final now = DateTime(2026, 11, 22, 12);
    test('read from the server', () {
      final p = decodePolls('{"polls":[{"id":3,"question":"Shift Friday?",'
              '"options":["Yes","No"],"votes":[5,2],"open":true,'
              '"closes":"2026-11-23T12:30:00.000Z","mine":1,"from":"CR"}]}')
          .single;
      expect([p.question, p.total, p.mine, p.from, p.open],
          ['Shift Friday?', 7, 1, 'CR', true]);
      expect(decodePolls('nope'), isEmpty);
    });

    test('closed ones stay two days, and the wording', () {
      Poll p(bool open, DateTime closes) =>
          Poll(1, 'Q', ['A', 'B'], [1, 0], open, closes);
      expect(pollsToShow([p(false, DateTime(2026, 11, 19))], now), isEmpty);
      expect(pollsToShow([p(false, DateTime(2026, 11, 21))], now).length, 1);
      expect(pollWhen(p(true, DateTime(2026, 11, 22, 18)), now),
          'Closes today, 18:00');
      expect(pollWhen(p(true, DateTime(2026, 11, 23, 9)), now),
          'Closes tomorrow, 09:00');
      expect(pollWhen(p(false, DateTime(2026, 11, 21)), now), 'Closed');
      expect(pollSummary(p(true, now)), 'A 1 · B 0');
    });
  });
}
