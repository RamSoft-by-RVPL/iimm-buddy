import 'dart:convert';

import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/site.dart';
import 'package:flutter_test/flutter_test.dart';

// Same shape as api/student-dashboard.php?action=summary (made-up values).
Map<String, dynamic> session(String date, String status,
        {bool upcoming = false}) =>
    {
      'schedule_id': 1,
      'date': date,
      'day': 'x',
      'time_slot': '14:00 PM to 15:30 PM',
      'start_time': '14:00:00',
      'end_time': '15:30:00',
      'room_number': '404',
      'faculty_name': 'Prof. A',
      'status': status,
      'remarks': '',
      'is_countable': !upcoming,
      'is_upcoming': upcoming,
    };

String body() => jsonEncode({
      'status': 'success',
      'success': true,
      'message': 'Student dashboard retrieved',
      'data': {
        'student': {'roll_number': '123', 'name': 'TEST STUDENT'},
        'modules': [
          {
            'module_id': 6,
            'start_date': '2026-09-21',
            'end_date': '2027-01-17',
            'courses': [
              {
                'course_id': 239,
                'course_name': 'Data Visualization',
                'hours': 45,
                'credits': '3.0',
                'faculty_names': 'Prof. A, Prof. B',
                'counts': {
                  'total_sessions': 5,
                  'attended': 3,
                  'present': 3,
                  'late': 0,
                  'absent': 1,
                  'not_marked': 1,
                  'upcoming': 2
                },
                'sessions': [
                  session('2026-09-23', 'Present'),
                  session('2026-10-28', 'Present'), // Wed
                  session('2026-11-04', 'Absent'), // Wed
                  session('2026-11-11', 'Present'), // Wed
                  session('2026-11-13', 'Not Marked'), // Fri
                  session('2026-11-18', 'Not Marked', upcoming: true), // Wed
                  session('2026-11-20', 'Not Marked', upcoming: true), // Fri
                ],
                'percentage': 60,
                'risk': 'risk'
              },
              {
                'course_id': 263,
                'course_name': 'Algorithms',
                'hours': 22,
                'counts': {'total_sessions': 6, 'attended': 6, 'not_marked': 0},
                'sessions': [
                  for (final d in ['01', '06', '08', '13', '20', '27'])
                    session('2026-10-$d', 'Present')
                ],
              },
            ]
          }
        ]
      }
    });

void main() {
  test('parses the dashboard summary', () {
    final s = parseSummary(body(), DateTime(2026, 11, 16), {});
    expect(s.studentName, 'TEST STUDENT');
    expect(s.courses.length, 2);

    final c = s.courses[0];
    expect(c.id, '239');
    expect(c.held, 5);
    expect(c.attended, 3);
    expect(c.pending, 1);
    expect(c.total, 30); // 45 hours of 90-minute classes
    expect(c.upcoming, [DateTime(2026, 11, 18), DateTime(2026, 11, 20)]);
    expect(c.absences, [DateTime(2026, 11, 4)]);
    expect(c.horizon, DateTime(2026, 11, 20));
    expect(c.ends, DateTime(2027, 1, 17));
    // Last four weeks: Wed x4 -> 1 a week, Fri x2 -> 1 a week (rounded up).
    expect(c.weekly, {DateTime.wednesday: 1, DateTime.friday: 1});

    final a = s.courses[1];
    expect(a.total, 15); // 22 hours -> 14.67 -> 15
    expect(a.weekly, isEmpty); // one class in four weeks: treated as over
    expect(a.upcoming, isEmpty);

    expect(s.held, 11);
    expect(s.attended, 9);
  });

  test('a hand-set course length wins', () {
    final s = parseSummary(body(), DateTime(2026, 11, 16), {'239': 20});
    expect(s.courses[0].total, 20);
    expect(leaveLeft(s.courses[0], 85), 3 - 2);
  });

  test('error answers throw', () {
    expect(
        () => parseSummary(
            '{"status":"error","success":false,"message":"Unauthorized access","data":[]}',
            DateTime(2026, 11, 16), {}),
        throwsException);
  });

  test('theory and lab halves become one course', () {
    Map<String, dynamic> course(
            int id, String name, num hours, int held, int att) =>
        {
          'course_id': id,
          'course_name': name,
          'hours': hours,
          'counts': {'total_sessions': held, 'attended': att, 'not_marked': 0},
          'sessions': [session('2026-11-13', 'Present')],
        };
    final b = jsonEncode({
      'success': true,
      'data': {
        'student': {},
        'modules': [
          {
            'end_date': '2027-01-17',
            'courses': [
              course(261, 'Programming Fundamentals (Python) Lab', 37, 12, 11),
              course(
                  260, 'Programming Fundamentals (Python) Theory', 30, 14, 13),
              course(
                  259,
                  'Statistics, Probability and Data Science Foundations (Lab)',
                  38,
                  16,
                  14),
              course(
                  258,
                  'Statistics, Probability and Data Science Foundations (Theory)',
                  30,
                  11,
                  10),
              course(241, 'Linear Algebra and Calculus', 45, 18, 15),
            ]
          }
        ]
      }
    });
    final s = parseSummary(b, DateTime(2026, 11, 16), {});
    expect(s.courses.map((c) => c.name).toList(), [
      'Programming Fundamentals (Python)',
      'Statistics, Probability and Data Science Foundations',
      'Linear Algebra and Calculus',
    ]);
    final pf = s.courses[0];
    expect(pf.parts.map((p) => p.label).toList(), ['Theory', 'Lab']);
    expect(pf.parts.map((p) => p.total).toList(), [20, 25]); // 30 h and 37.5 h
    expect(pf.total, 45); // 67.5 hours
    expect(pf.held, 26);
    expect(pf.attended, 24);
    expect(s.courses[1].parts.map((p) => p.total).toList(),
        [20, 25]); // site says 38 h
    expect(s.courses[2].parts, isEmpty);
    expect(s.courses[2].total, 30);
    expect(s.held, 71); // nothing counted twice
  });
}
