import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:attendance_planner/absence.dart';
import 'package:attendance_planner/acal.dart';
import 'package:attendance_planner/attendance_ui.dart';
import 'package:attendance_planner/file_view.dart';
import 'package:attendance_planner/health.dart';
import 'package:attendance_planner/leave.dart';
import 'package:attendance_planner/log.dart';
import 'package:attendance_planner/notes_index.dart';
import 'package:attendance_planner/notify.dart';

import 'package:attendance_planner/backend.dart';
import 'package:attendance_planner/exams.dart';
import 'package:attendance_planner/background.dart';
import 'package:attendance_planner/moodle.dart';
import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/push.dart';
import 'package:attendance_planner/sheet.dart';
import 'package:attendance_planner/update.dart';
import 'package:attendance_planner/site.dart';
import 'package:attendance_planner/ui_common.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> ses(int id, String date, String status,
        {bool upcoming = false, String start = '14:00:00'}) =>
    {
      'schedule_id': id,
      'date': date,
      'start_time': start,
      'end_time': '15:30:00',
      'room_number': '404',
      'status': status,
      'is_upcoming': upcoming,
    };

String body(List<Map<String, dynamic>> sessions, int held, int attended) =>
    jsonEncode({
      'success': true,
      'data': {
        'student': {'name': 'T', 'roll_number': '1'},
        'modules': [
          {
            'end_date': '2027-01-17',
            'courses': [
              {
                'course_id': 241,
                'course_name': 'Linear Algebra and Calculus',
                'hours': 45,
                'counts': {
                  'total_sessions': held,
                  'attended': attended,
                  'not_marked': 0
                },
                'sessions': sessions,
              }
            ]
          }
        ]
      }
    });

void main() {
  v11();
  v12();
  v13();
  v14();
  v15();
  v16();
  v17();
  v18();
  v19();
  v20();
  v21();
  v22();
  v23();
  v24();
  v25();
  v26();
  v27();
  v28();
  final now = DateTime(2026, 11, 16, 10);

  test('class reminders and the widget use the published timetable', () {
    final s = parseSummary(
        body([
          ses(1, '2026-11-10', 'Present'),
          ses(7, '2026-11-18', 'Not Marked', upcoming: true),
          ses(8, '2026-11-18', 'Not Marked', upcoming: true, start: '09:00:00'),
        ], 1, 1),
        now,
        {});
    expect(s.next.map((x) => x.id).toList(), [8, 7]); // soonest first
    final r = classReminders(s.next, 15);
    expect(r.length, 2);
    expect(r[0].at, DateTime(2026, 11, 18, 8, 45));
    expect(r[0].title, 'Class in 15 mins');
    expect(r[1].at, DateTime(2026, 11, 18, 13, 45));

    final w = widgetData(s, 85, now, name: (_) => 'LAC');
    expect(w.percent, '100.0%');
    expect(w.state, 'All courses above 85%');
    expect(w.course, 'LAC');
    expect(w.when, 'Wed 18 Nov 09:00 · Room 404');
    expect(w.startsAt, DateTime(2026, 11, 18, 9).millisecondsSinceEpoch);
    expect(classReminders(s.next, 5, name: (_) => 'LAC').first.body,
        startsWith('LAC · Room 404'));
    expect(classReminders(s.next, 5).first.open, 'timetable');
  });

  test('alerts for a new absence and for dropping below the minimum', () {
    final old = parseSummary(
        body([
          for (var i = 1; i <= 17; i++) ses(i, '2026-10-01', 'Present'),
          ses(18, '2026-11-13', 'Not Marked'),
          ses(19, '2026-11-14', 'Not Marked'),
          ses(20, '2026-11-15', 'Not Marked'),
        ], 20, 17),
        now,
        {});
    // Nothing changed: no alerts.
    expect(attendanceAlerts(old, old, 85), isEmpty);

    final neu = parseSummary(
        body([
          for (var i = 1; i <= 17; i++) ses(i, '2026-10-01', 'Present'),
          ses(18, '2026-11-13', 'Absent'),
          ses(19, '2026-11-14', 'Not Marked'),
          ses(20, '2026-11-15', 'Not Marked'),
          ses(21, '2026-11-16', 'Absent'), // not seen before: no absence alert
        ], 21, 17),
        now,
        {});
    final alerts = attendanceAlerts(old, neu, 85);
    expect(alerts.map((a) => a.$1).toList(), [
      'Marked absent: Linear Algebra and Calculus',
      'Linear Algebra and Calculus is below 85%',
    ]);
    expect(alerts[0].$2, startsWith('Fri 13 Nov, 14:00.'));
  });

  test('new Moodle items since the last check', () {
    final secs = [
      MoodleSection('A', [
        MoodleItem(1, 'Old', 'resource', 'u', true),
        MoodleItem(2, 'Slides week 7', 'resource', 'u', true),
      ])
    ];
    expect(newItems(null, secs), isEmpty); // first check: nothing is "new"
    expect(newItems({1}, secs).map((i) => i.name).toList(), ['Slides week 7']);
    expect(newItems({1, 2}, secs), isEmpty);
    expect(listNames(['a', 'b', 'c', 'd', 'e']), 'a, b, c and 2 more');
  });

  test('skipping one class', () {
    // 17/18 of 30: budget 4, used 1.
    final ok = Course(id: 'a', name: 'a', held: 18, attended: 17, total: 30);
    expect(canSkip(ok, 85), true);
    expect(skipLine(ok, 85),
        'Goes from 94.4% to 89.5%. 2 classes of leave left after.');
    // 14/18 of 30: budget 4, all used.
    final no = Course(id: 'a', name: 'a', held: 18, attended: 14, total: 30);
    expect(canSkip(no, 85), false);
    expect(skipLine(no, 85), contains('out of reach'));
  });

  test('break suggestions are safe, long enough and do not overlap', () {
    final today = DateTime(2026, 11, 16); // Monday
    // One class every weekday, 30 in the course, 2 absences of leave left.
    final c = Course(
        id: 'a',
        name: 'a',
        held: 10,
        attended: 8,
        total: 30,
        weekly: {for (var d = 1; d <= 5; d++) d: 1});
    final ideas = suggestBreaks([c], today, 85);
    expect(ideas, isNotEmpty);
    for (final i in ideas) {
      expect(i.days, greaterThanOrEqualTo(3));
      expect(
          i.missed, inInclusiveRange(1, 2)); // never more than the leave left
      expect(
          breaksCourse(holidayImpact(c, today, i.from, i.to, 85), 85), false);
    }
    // Best use of two absences: Fri to Mon... i.e. a break around a weekend.
    expect(ideas.first.days, greaterThanOrEqualTo(4));
    for (var x = 0; x < ideas.length; x++) {
      for (var y = x + 1; y < ideas.length; y++) {
        expect(ideas[y].from.isAfter(ideas[x].to), true);
      }
    }
    // No leave at all: nothing to suggest.
    final none = Course(
        id: 'a',
        name: 'a',
        held: 20,
        attended: 16,
        total: 30,
        weekly: {for (var d = 1; d <= 5; d++) d: 1});
    expect(suggestBreaks([none], today, 85), isEmpty);
  });
}

// ---- added with version 1.1
void v11() {
  test('assignment page: status, marks and due date', () {
    final now = DateTime(2026, 11, 16);
    final open = parseAssign(
        '<div data-region="activity-dates"><div><strong>Due:</strong> '
        'Wednesday, 18 November 2026, 11:59 PM</div></div>'
        '<td class="cell c1 lastcol">No submissions have been made yet</td>'
        '<td class="submissionnotgraded cell c1 lastcol">Not graded</td>',
        now);
    expect(open.status, 'none');
    expect(open.graded, false);
    expect(open.due, DateTime(2026, 11, 18, 23, 59));
    expect(open.label(now), 'Not submitted');
    expect(open.label(DateTime(2026, 11, 19)), 'Not submitted, overdue');

    final done = parseAssign(
        '<strong>Due:</strong> Friday, 9 October 2026, 12:05 AM'
        '<td class="submissionstatussubmitted cell c1 lastcol">Submitted</td>'
        '<td class="submissiongraded cell c1 lastcol">Graded</td>',
        now);
    expect(done.submitted, true);
    expect(done.graded, true);
    expect(done.due, DateTime(2026, 10, 9, 0, 5));
    expect(AssignInfo.fromJson(done.toJson()).label(now), 'Submitted');
    expect(linkId('https://x/mod/assign/view.php?id=4182'), 4182);
  });

  test('correction email names the class and the student', () {
    final snap = parseSummary(
        body([ses(7, '2026-11-09', 'Absent'), ses(8, '2026-11-10', 'Present')],
            2, 1),
        DateTime(2026, 11, 16),
        {});
    final absent = snap.sessions.firstWhere((s) => s.id == 7);
    expect(canDispute(absent), true);
    expect(canDispute(snap.sessions.firstWhere((s) => s.id == 8)), false);
    final m = absenceEmail(snap, absent);
    expect(m.subject,
        'Attendance correction: Linear Algebra and Calculus, 9 November');
    expect(m.body, contains('marked as absent'));
    expect(m.body, contains('Date: Monday, 9 November 2026'));
    expect(m.body, contains('Time: 14:00 to 15:30'));
    expect(m.body, contains('Roll number: 1'));
  });
}

void v12() {
  test('trend and where the course ends up', () {
    expect(runningPercent([true, false, true, true]), [100, 50, 200 / 3, 75]);
    final c = Course(id: '1', name: 'X', held: 20, attended: 18, total: 30);
    final p = projection(c)!;
    expect(p.$1, 27 * 100 / 30);
    expect(p.$2, 28 * 100 / 30);
    expect(
        projection(Course(id: '1', name: 'X', held: 20, attended: 18)), isNull);
  });

  test('calendar gets coming classes and open deadlines only', () {
    final now = DateTime(2026, 11, 16, 12);
    final snap = parseSummary(
        body([
          ses(1, '2026-11-10', 'Present'),
          ses(2, '2026-11-17', 'Not Marked', upcoming: true)
        ], 1, 1),
        now,
        {});
    final ev = calendarEvents(
        snap.sessions,
        [
          Deadline(1, 'Old', DateTime(2026, 11, 1), 'C', '', ''),
          Deadline(2, 'Essay', DateTime(2026, 11, 20, 23, 59), 'C', '', ''),
        ],
        now);
    expect(
        ev.map((e) => e.title), ['Linear Algebra and Calculus', 'Due: Essay']);
    expect(ev.first.start, DateTime(2026, 11, 17, 14));
    expect(ev.first.end, DateTime(2026, 11, 17, 15, 30));
    expect(ev.first.place, 'Room 404');
  });
}

void v13() {
  test('leave log: reasons, what excusing does, and the shared list', () {
    final snap = parseSummary(
        body([
          ses(7, '2026-11-09', 'Absent'),
          ses(8, '2026-11-10', 'Present'),
          ses(9, '2026-11-11', 'Absent'),
        ], 3, 1),
        DateTime(2026, 11, 16),
        {});
    expect(absences(snap).map((s) => s.id), [9, 7]);
    final log = parseLeaves(encodeLeaves({7: Leave('medical', 'Fever')}));
    expect(log[7]!.label, 'Medical');
    expect(log[7]!.note, 'Fever');
    final c = snap.courses.single;
    expect(notedFor(c, snap, log), 1);
    expect(percentIfExcused(c, 1), closeTo(200 / 3, 1e-9));
    final text = leaveReport(snap, log);
    expect(text, contains('2 in all, 1 with a reason noted'));
    expect(
        text,
        contains('09-11-2026  14:00  Linear Algebra and Calculus  -  '
            'Medical (Fever)'));
    expect(
        text,
        contains('11-11-2026  14:00  Linear Algebra and Calculus  -  '
            'no reason noted'));
    expect(parseLeaves('broken'), isEmpty);
  });
}

void v14() {
  test('reminder check names each blocked phone setting', () {
    expect(problemsFrom(NotifyState(true, true, 5), true, 'google'), isEmpty);
    final all = problemsFrom(NotifyState(false, false, 0), false, 'xiaomi');
    expect(all.length, 3);
    expect(all.last.how, contains('Autostart'));
    expect(problemsFrom(NotifyState(true, true, 0), false, 'google').single.how,
        isNot(contains('Autostart')));
    expect(makerTip('samsung'), contains('Sleeping apps'));
    expect(makerTip('google'), isNull);
  });
}

void v15() {
  test('class reminder reads like "Class in 5 mins" with the course', () {
    final r = classReminders([
      ClassSlot(42, DateTime(2026, 11, 17), '09:00', '10:30', '404',
          'Data Structures', '9', 'Not Marked', true)
    ], 5)
        .single;
    expect(r.title, 'Class in 5 mins');
    expect(r.body, 'Data Structures · Room 404 · 09:00 to 10:30');
    expect(r.at, DateTime(2026, 11, 17, 8, 55));
  });
}

void v16() {
  test('a class later today still gets a reminder', () {
    // The site may stop flagging today's classes as upcoming.
    final snap = parseSummary(
        body([
          ses(1, '2026-11-16', 'Present', start: '09:00:00'),
          ses(2, '2026-11-16', 'Not Marked', start: '14:00:00'),
          ses(3, '2026-11-13', 'Not Marked', start: '14:00:00'),
        ], 2, 1),
        DateTime(2026, 11, 16, 12),
        {});
    expect(snap.next.map((s) => s.id), [2]);
    expect(
        classReminders(snap.next, 5).single.at, DateTime(2026, 11, 16, 13, 55));
    expect(snap.sessions.firstWhere((s) => s.id == 3).unmarked, true);
  });
}

void v17() {
  test('the mailed timetable sheet is read and fills the gaps', () {
    final sheet = parseTimetable(
        readXlsx(File('test/fixtures/timetable.xlsx').readAsBytesSync()));
    expect(sheet.length, 18);
    final mon = sheet.where((c) => c.date == DateTime(2026, 11, 16)).toList();
    expect(mon.map((c) => c.start), ['09:00', '10:40', '14:00', '15:40']);
    expect(mon[2].course, 'Algorithm Design & Data Structure');
    expect(mon[2].faculty, 'HPE');
    expect(mon[2].end, '15:30');
    final fri = sheet.where((c) => c.date == DateTime(2026, 11, 20)).last;
    expect(fri.course, 'Data Visualization and Storytelling');
    expect(fri.faculty, 'Prof.K.Menon');
    expect(decodeSheet(encodeSheet(sheet)).length, 18);

    final courses = [
      Course(
          id: '1',
          name: 'Statistics, Probability and Data Science Foundations',
          held: 0,
          attended: 0),
      Course(
          id: '2',
          name: 'Principles of Algorithm Design and Data Structures',
          held: 0,
          attended: 0),
      Course(
          id: '3',
          name: 'Data Visualization and Storytelling',
          held: 0,
          attended: 0),
      Course(
          id: '4',
          name: 'Programming Fundamentals (Python)',
          held: 0,
          attended: 0),
      Course(
          id: '5',
          name: 'Principles of Business and Management',
          held: 0,
          attended: 0),
    ];
    expect(matchCourse('Algorithm Design & Data Structure', courses)!.id, '2');
    expect(
        matchCourse('Statistic, Probability and Data Science Foundationns',
                courses)!
            .id,
        '1');
    expect(matchCourse('Programming Fundamentals (Python)', courses)!.id, '4');
    expect(
        matchCourse('Data Visualization and Storytelling', courses)!.id, '3');
    expect(matchCourse('Yoga', courses), isNull);
  });

  test('sheet classes the site lacks are added and get reminders', () {
    final now = DateTime(2026, 11, 16, 12, 30);
    final snap = parseSummary(
        body([ses(1, '2026-11-16', 'Present', start: '09:00:00')], 1, 1),
        now, {});
    final merged = snap.withSheet([
      SheetClass(
          DateTime(2026, 11, 16), '09:00', '10:30', 'Linear Algebra', ''),
      SheetClass(DateTime(2026, 11, 16), '14:00', '15:30',
          'Linear Algebra & Calculus', 'HPE'),
      SheetClass(DateTime(2026, 11, 13), '14:00', '15:30', 'Algo & DS', 'HPE'),
    ], now);
    expect(merged.sessions.length, 3); // the 09:00 one is already on the site
    final extra = merged.next.single;
    expect(extra.fromSheet, true);
    expect(extra.start, '14:00');
    expect(extra.room, '404');
    expect(classReminders(merged.next, 5).single.at,
        DateTime(2026, 11, 16, 13, 55));
    final past = merged.sessions.first;
    expect(past.fromSheet && !past.upcoming && !past.unmarked, true);
    expect(canDispute(past), false);
    expect(merged.held, snap.held); // attendance numbers do not change
    // The holiday planner counts the sheet's classes, and knows the
    // timetable up to the sheet's last day.
    final c = merged.courses.single;
    expect(c.upcoming, [DateTime(2026, 11, 16)]);
    expect(c.horizon, DateTime(2026, 11, 16));
    expect(snap.courses.single.upcoming, isEmpty);

    final kept = mergeSheets([
      SheetClass(DateTime(2026, 11, 10), '09:00', '10:30', 'Old', ''),
      SheetClass(DateTime(2026, 11, 17), '09:00', '10:30', 'Replaced', ''),
    ], [
      SheetClass(DateTime(2026, 11, 16), '09:00', '10:30', 'New', '')
    ], now);
    expect(kept.map((c) => c.course), ['Old', 'New']);
  });
}

void v18() {
  test('batch name for the shared timetable comes from the site data', () {
    String raw(Object? code, Object? year) => jsonEncode({
          'data': {
            'modules': [
              {'programme_code': code, 'batch_year': year}
            ]
          }
        });
    expect(batchKey(raw('BS', '2026-2030')), 'bs-2026-2030');
    expect(batchKey(raw('B.S. (DSBM)', 2026)), 'b-s-dsbm-2026');
    expect(batchKey(raw(null, null)), isNull);
    expect(batchKey(null), isNull);
    expect(batchKey('not json'), isNull);
  });
}

void v19() {
  test('version in the app matches pubspec.yaml', () {
    expect(File('pubspec.yaml').readAsStringSync(),
        contains('version: $appVersion+$appBuild'));
  });

  test('errors in the log are one line without link details', () {
    expect(
        errorLine(Exception(
            'Failed  https://x.y/login?token=abc123&u=me\n  retry later')),
        'Failed https://x.y/login retry later');
  });

  test('health problems have short names for the log', () {
    expect(
        problemsFrom(NotifyState(false, false, 0), false, 'vivo')
            .map((p) => p.code),
        ['notifications off', 'exact alarms off', 'battery restricted']);
  });
}

void v20() {
  test('assignment reminders start two days before, then as chosen', () {
    final due = DateTime(2026, 11, 20, 23, 59);
    final r = deadlineReminders(
        [Deadline(7, 'Essay', due, 'Business', '', '')], [48, 24, 3]);
    expect(r.map((x) => x.at), [
      DateTime(2026, 11, 18, 23, 59),
      DateTime(2026, 11, 19, 23, 59),
      DateTime(2026, 11, 20, 20, 59),
    ]);
    expect(r.map((x) => x.title), [
      'Due in 2 days: Essay',
      'Due tomorrow: Essay',
      'Due in 3 hours: Essay'
    ]);
    expect(r.map((x) => x.id).toSet().length, 3);
    expect(dueIn(1), 'in 1 hour');
    expect(dueSummary([48, 24, 3]), '2 days, 1 day and 3 hours before');
    expect(dueSummary([48]), '2 days before');
  });
}

void v21() {
  test('messages from the admin: only new ones are shown, oldest first', () {
    final all = decodeNotices(jsonEncode({
      'notices': [
        {'id': 9, 'title': 'C', 'body': '', 'created': '2026-11-16T10:00:00Z'},
        {'id': 7, 'title': 'A', 'body': 'x', 'created': '2026-11-15T10:00:00Z'},
        {'id': 8, 'title': 'B', 'body': '', 'created': '2026-11-15T11:00:00Z'},
      ]
    }));
    expect(all.length, 3);
    final now = DateTime.utc(2026, 11, 16, 10, 30);
    // New install or just updated: only what was sent in the last hour.
    expect(newNotices(all, null, now).map((n) => n.title), ['C']);
    expect(newNotices(all, {7}, now).map((n) => n.title), ['B', 'C']);
    expect(newNotices(all, {7, 8, 9}, now), isEmpty);
    // A message written earlier but sent later (lower id) is still shown.
    expect(newNotices(all, {8, 9}, now).map((n) => n.title), ['A']);
    expect(decodeNotices('broken'), isEmpty);
  });

  test('which files open inside the app', () {
    expect(fileKind('/a/b/Lecture 3.PDF'), 'pdf');
    expect(fileKind('/a/chart.jpeg'), 'picture');
    expect(fileKind('/a/slides.pptx'), 'other');
    expect(fileKind('/a/noextension'), 'other');
    expect(
        isMoodleFile(Uri.parse(
            'https://moodle.iimmumbai.ac.in/pluginfile.php/1/mod_assign/intro/a.pdf')),
        true);
    expect(
        isMoodleFile(Uri.parse(
            'https://moodle.iimmumbai.ac.in/pluginfile.php/1/mod_securepdf/content/a.pdf')),
        false);
    expect(
        isMoodleFile(Uri.parse(
            'https://moodle.iimmumbai.ac.in/mod/assign/view.php?id=1')),
        false);
  });
}

void v22() {
  test('update: only a newer build with a path and a fingerprint counts', () {
    String feed(int b, {String apk = '/IIMM-Buddy.apk', String? sha}) =>
        jsonEncode({
          'build': b,
          'version': '9.9.0',
          'notes': 'n',
          'apk': apk,
          'sha256': sha ?? 'a' * 64,
          'size': 123
        });
    expect(parseUpdate(feed(appBuild)), isNull);
    final u = parseUpdate(feed(appBuild + 1))!;
    expect(u.version, '9.9.0');
    expect(u.size, 123);
    expect(parseUpdate(feed(appBuild + 1, apk: 'https://evil.example/a.apk')),
        isNull);
    expect(parseUpdate(feed(appBuild + 1, sha: 'short')), isNull);
    expect(parseUpdate('not json'), isNull);
    expect(parseUpdate(null), isNull);
  });
}

void v23() {
  test('push topics: everyone, plus the batch once it is known', () {
    expect(pushTopics(null), ['all']);
    expect(pushTopics('bs-2026-2030'), ['all', 'batch-bs-2026-2030']);
  });
}

void v24() {
  test('home screen wording helpers', () {
    expect(firstName('ARJUN KUMAR SHAH'), 'Arjun');
    expect(firstName(''), 'there');
    expect(
        datesText([
          DateTime(2026, 11, 18),
          DateTime(2026, 11, 20),
          DateTime(2026, 11, 18)
        ]),
        'Wed 18 Nov (2 classes), Fri 20 Nov');
    final now = DateTime(2026, 11, 16, 20, 0);
    ClassSlot at(DateTime d, String start) =>
        ClassSlot(1, d, start, '23:59', '', 'X', '1', 'Not Marked', true);
    expect(untilWord(at(DateTime(2026, 11, 16), '20:25'), now), 'in 25 min');
    expect(
        untilWord(at(DateTime(2026, 11, 16), '22:30'), now), 'in 2 h 30 min');
    expect(untilWord(at(DateTime(2026, 11, 17), '09:00'), now), 'in 13 h');
    expect(untilWord(at(DateTime(2026, 11, 19), '09:00'), now), 'in 2 days');
    expect(untilWord(at(DateTime(2026, 11, 16), '19:00'), now), 'Now');
    expect(dayWord(DateTime(2026, 11, 17), now), 'Tomorrow');
    final c = Course(id: '1', name: 'X', held: 20, attended: 18, total: 30);
    expect(statusShort(c, 85), 'Can miss 2');
    expect(
        statusShort(
            Course(id: '1', name: 'X', held: 20, attended: 16, total: 30), 85),
        'Below 85%');
  });
}

void v25() {
  test('exams: countdown, order and reminders', () {
    final now = DateTime(2026, 11, 16, 20);
    expect(countdown(DateTime(2026, 11, 28, 10), now), 'in 12 days');
    expect(countdown(DateTime(2026, 11, 17, 9), now), 'Tomorrow');
    expect(countdown(DateTime(2026, 11, 16, 22, 30), now), 'in 2 h');
    expect(countdown(DateTime(2026, 11, 14, 9), now), '2 days ago');
    final list = decodeExams(encodeExams([
      Exam(2, 'End term', 'Stats', DateTime(2026, 12, 20, 10), 'Exam'),
      Exam(1, 'Quiz 2', '', DateTime(2026, 11, 25, 14, 30), 'Quiz'),
    ]));
    expect(list.map((e) => e.title), ['Quiz 2', 'End term']); // soonest first
    final r = examReminders([list.first]);
    expect(r.map((x) => x.at), [
      DateTime(2026, 11, 18, 9),
      DateTime(2026, 11, 24, 19),
      DateTime(2026, 11, 25, 12, 30),
    ]);
    expect(r[1].title, 'Quiz tomorrow: Quiz 2');
    expect(r[2].body, 'At 14:30.');
    expect(r.map((x) => x.id).toSet().length, 3);
    expect(decodeExams('broken'), isEmpty);
  });
}

void v26() {
  test('search inside notes: finds the page and shows words around it', () {
    final text = [
      'Introduction to probability and random variables',
      'Sampling distributions: the sample mean has its own distribution',
      'Hypothesis testing',
    ].join(pageBreak);
    final hits = findIn(text, 'SAMPLE MEAN');
    expect(hits.single.$1, 2);
    expect(hits.single.$2, contains('the sample mean has its own'));
    expect(findIn(text, 'regression'), isEmpty);
    expect(
        findIn('one page only with sampling in it', 'sampling').single.$1, 0);
    expect(canIndex('/a/b/Notes.PDF'), true);
    expect(canIndex('/a/b/slides.pptx'), true);
    expect(canIndex('/a/b/photo.jpg'), false);
  });

  test('slide and Word text are read from their files', () {
    Archive zip(Map<String, String> files) {
      final a = Archive();
      files.forEach((name, body) {
        final bytes = utf8.encode(body);
        a.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      return a;
    }

    final pptx = ZipEncoder().encode(zip({
      'ppt/slides/slide2.xml': '<p><a:t>Second &amp; last</a:t></p>',
      'ppt/slides/slide1.xml': '<p><a:t>First</a:t><a:t>slide</a:t></p>',
      'ppt/notes.xml': '<a:t>ignored</a:t>',
    }))!;
    expect(pptxText(pptx), ['First slide', 'Second & last']);
    final docx = ZipEncoder().encode(zip({
      'word/document.xml':
          '<w:p><w:t>Hello</w:t><w:t xml:space="preserve"> world</w:t></w:p>'
              '<w:p><w:t>Next line</w:t></w:p>',
    }))!;
    expect(docxText(docx), 'Hello  world\nNext line');
  });
}

void v27() {
  test('academic calendar: days off, wording and reminders', () {
    final events = decodeCalendar(jsonEncode([
      {
        'title': 'Winter Break',
        'from': '2026-12-20',
        'to': '2027-01-03',
        'kind': 'break',
        'group': 'Semester-I'
      },
      {
        'title': 'Guru Nanak Birthday',
        'from': '2026-11-24',
        'to': '2026-11-24',
        'kind': 'holiday',
        'group': 'Holidays'
      },
      {
        'title': 'End-Term Examination',
        'from': '2027-01-08',
        'to': '2027-01-14',
        'kind': 'exam',
        'group': 'Semester-I'
      },
      {
        'title': 'Classes End',
        'from': '2026-12-19',
        'to': '2026-12-19',
        'kind': 'info',
        'group': 'Semester-I'
      },
    ]));
    expect(events.first.title, 'Guru Nanak Birthday'); // soonest first
    final off = offDays(events);
    expect(off.contains(20261124), true);
    expect(off.contains(20261225), true); // inside the winter break
    expect(off.contains(20270110), true); // exam week
    expect(off.contains(20261219), false); // a term date is a working day
    expect(off.length, 1 + 15 + 7);
    expect(spanText(events[2]), '20 Dec to 3 Jan');
    expect(events.first.covers(DateTime(2026, 11, 24, 15)), true);
    final r = calendarReminders(events);
    expect(r.first.title, 'No classes tomorrow');
    expect(r.first.at, DateTime(2026, 11, 23, 19));
    expect(r.map((x) => x.title), contains('End-Term Examination in a week'));
    expect(r.map((x) => x.id).toSet().length, r.length);
    expect(decodeCalendar('broken'), isEmpty);
  });

  test('the planner does not guess classes on days off', () {
    // A course that usually meets on Tuesdays, timetable known to 20 Nov.
    final c = Course(
        id: '1',
        name: 'X',
        held: 10,
        attended: 10,
        weekly: {DateTime.tuesday: 2},
        horizon: DateTime(2026, 11, 20));
    plannerDaysOff = {};
    expect(
        classesBetween(c, DateTime(2026, 11, 23), DateTime(2026, 11, 27)), 2);
    plannerDaysOff = {20261124}; // that Tuesday is a holiday
    expect(
        classesBetween(c, DateTime(2026, 11, 23), DateTime(2026, 11, 27)), 0);
    expect(classesBetween(c, DateTime(2026, 11, 23), DateTime(2026, 12, 4)), 2);
    plannerDaysOff = {};
  });
}

void v28() {
  test('beyond the timetable: four classes a day, split by classes left', () {
    final a = Course(
        id: 'a',
        name: 'A',
        held: 10,
        attended: 10,
        total: 40,
        horizon: DateTime(2026, 11, 20));
    final b = Course(
        id: 'b',
        name: 'B',
        held: 30,
        attended: 30,
        total: 40,
        horizon: DateTime(2026, 11, 20));
    setPlannerShares([a, b]); // 30 and 10 left: 3/4 and 1/4 of each day
    plannerDaysOff = {};
    int both(DateTime f, DateTime t) =>
        classesBetween(a, f, t) + classesBetween(b, f, t);
    // Every teaching day is exactly four classes in all.
    for (var d = 16; d <= 28; d++) {
      final day = DateTime(2026, 12, d);
      expect(both(day, day), day.weekday == DateTime.sunday ? 0 : 4);
    }
    // Mon 23 to Sun 29 Nov: six teaching days, 24 classes, about 18 and 6.
    final mon = DateTime(2026, 11, 23), sun = DateTime(2026, 11, 29);
    expect(both(mon, sun), 24);
    expect(classesBetween(a, mon, sun), inInclusiveRange(17, 19));
    plannerDaysOff = {20261124}; // a holiday drops one day
    expect(both(mon, sun), 20);
    expect(classesBetween(a, mon, sun), inInclusiveRange(14, 16));
    plannerDaysOff = {};
    plannerShare = {};
  });

  test('long weekends stretch a Sunday or a holiday with one or two days', () {
    addTearDown(() {
      plannerDaysOff = {};
      plannerShare = {};
    });
    final today = DateTime(2026, 11, 16); // Monday
    // 4 classes a day beyond the timetable, 8 classes of leave left.
    final c = Course(
        id: 'a',
        name: 'A',
        held: 40,
        attended: 40,
        total: 200,
        horizon: DateTime(2026, 11, 16));
    setPlannerShares([c]);
    plannerDaysOff = {20261124, 20261125}; // Tue and Wed off
    final w = longWeekends([c], today, 85);
    expect(w, isNotEmpty);
    // A run of days off that starts in the window counts whole.
    plannerDaysOff = {
      for (var d = 20; d <= 31; d++) 20261200 + d,
      20270101,
      20270102,
      20270103
    };
    final winter = longWeekends([c], today, 85);
    expect(winter.any((i) => i.to == DateTime(2027, 1, 3)), true);
    plannerDaysOff = {20261124, 20261125};
    for (final i in w) {
      expect(i.leave, inInclusiveRange(1, 2));
      expect(i.days, greaterThanOrEqualTo(3));
      expect(i.missed, i.leave * 4); // one course: all four slots
      expect(
          breaksCourse(holidayImpact(c, today, i.from, i.to, 85), 85), false);
    }
    // Best one: Sun 22 to Wed 25 by taking Mon 23 (4 days for 1 day of leave).
    expect(
        w.any((i) =>
            i.from == DateTime(2026, 11, 22) && i.to == DateTime(2026, 11, 25)),
        true);
    for (var x = 0; x < w.length; x++) {
      for (var y = x + 1; y < w.length; y++) {
        expect(w[y].from.isAfter(w[x].to), true);
      }
    }
    // Only 3 classes of leave left (34/40 of 60): a day of leave is 4
    // classes, so nothing that misses a class is offered.
    final short = Course(
        id: 'a',
        name: 'A',
        held: 40,
        attended: 34,
        total: 60,
        horizon: DateTime(2026, 11, 16));
    setPlannerShares([short]);
    expect(
        longWeekends([short], today, 85).where((i) => i.missed > 0), isEmpty);
    plannerDaysOff = {};
    plannerShare = {};
  });
}
