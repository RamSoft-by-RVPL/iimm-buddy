// The demo: a sample student, for people without an IIM Mumbai account
// (the Google Play reviewer, or a student showing the app to a friend).
//
// It is switched on from the sign-in screen. The attendance site and Moodle
// are then never contacted: their answers come from here, built around today
// so the next class is always ahead. Sign out to leave it.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// True while the demo is on. Read once at start (and in background checks)
/// from the saved setting, so the network layer needs no preferences.
bool demoMode = false;

const demoNote = 'Not in the demo. Sign in with your IIM Mumbai account '
    'to open it.';

bool isDemo(SharedPreferences prefs) => prefs.getBool('demo') == true;

/// Settings the demo fills in that the attendance site does not send.
const _seeded = ['totals', 'exams_pub', 'acal'];

Future<void> startDemo(SharedPreferences prefs) async {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  String iso(int add) =>
      d.add(Duration(days: add)).toIso8601String().substring(0, 10);
  await prefs.setBool('demo', true);
  await prefs.setString('totals',
      jsonEncode({'1': 40, '2': 46, '3': 46, '4': 40, '5': 42, '6': 34}));
  await prefs.setString(
      'exams_pub',
      jsonEncode({
        'exams': [
          {
            'c': _courses[2].$2,
            'd': iso(12),
            's': '10:00',
            'e': '13:00',
            'r': '101'
          },
          {
            'c': _courses[0].$2,
            'd': iso(14),
            's': '14:00',
            'e': '17:00',
            'r': 'Auditorium',
            'n': 'Bring your ID card'
          },
          {
            'c': _courses[4].$2,
            'd': iso(16),
            's': '10:00',
            'e': '13:00',
            'r': '204'
          },
        ]
      }));
  await prefs.setString(
      'acal',
      jsonEncode([
        {
          'title': 'Mid-term break',
          'from': iso(4),
          'to': iso(6),
          'kind': 'break',
          'group': 'Term 1'
        },
        {
          'title': 'End-term exams',
          'from': iso(12),
          'to': iso(18),
          'kind': 'exam',
          'group': 'Term 1'
        },
        {
          'title': 'Term 2 begins',
          'from': iso(30),
          'to': iso(30),
          'kind': 'info',
          'group': 'Term 2'
        },
      ]));
  demoMode = true;
}

Future<void> stopDemo(SharedPreferences prefs) async {
  if (!isDemo(prefs)) return;
  for (final k in _seeded) {
    await prefs.remove(k);
  }
  await prefs.remove('demo');
  demoMode = false;
}

/// (id, name, classes held, attended, which ones were missed, classes ahead
/// as (days from today, start, end)).
const _courses = [
  (
    1,
    'Product and Brand Management',
    30,
    24,
    [3, 9, 14, 19, 23, 27],
    [(1, '09:00', '10:15'), (3, '09:00', '10:15')]
  ),
  (
    2,
    'Linear Algebra and Calculus',
    40,
    35,
    [6, 13, 22, 30, 37],
    [(2, '11:00', '12:15')]
  ),
  (
    3,
    'Statistics and Probability for Data Science',
    33,
    29,
    [5, 13, 21, 28],
    [(0, '', ''), (2, '14:00', '15:15')]
  ),
  (
    4,
    'Programming Fundamentals with Python',
    29,
    25,
    [4, 11, 17, 25],
    [(1, '14:00', '15:15')]
  ),
  (
    5,
    'Advanced Data Structures and Algorithms',
    30,
    27,
    [8, 16, 26],
    [(4, '11:00', '12:15')]
  ),
  (
    6,
    'Data Visualisation and Storytelling',
    28,
    26,
    [10, 20],
    [(3, '16:00', '17:15')]
  ),
];

/// The attendance site's summary for the sample student.
String demoSummary(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  String day(int add) =>
      today.add(Duration(days: add)).toIso8601String().substring(0, 10);
  String two(int n) => n.toString().padLeft(2, '0');
  // One class later today, whatever the time.
  final h = (now.hour + 1).clamp(0, 22);
  final laterToday = ('${two(h)}:30', '${two(h + 1)}:45');

  Map<String, dynamic> course(
      (int, String, int, int, List<int>, List<(int, String, String)>) c) {
    final (id, name, held, attended, missed, ahead) = c;
    return {
      'course_id': id,
      'course_name': name,
      'hours': 45,
      'counts': {'total_sessions': held, 'attended': attended, 'not_marked': 0},
      'sessions': [
        for (var i = 0; i < held; i++)
          {
            'schedule_id': id * 1000 + i,
            'date': day(-held * 2 + i * 2),
            'start_time': '10:30:00',
            'end_time': '11:45:00',
            'room_number': '204',
            'status': missed.contains(i) ? 'Absent' : 'Present',
            'is_upcoming': false,
          },
        for (final (i, (add, from, to)) in ahead.indexed)
          {
            'schedule_id': id * 1000 + 900 + i,
            'date': day(add),
            'start_time': '${from.isEmpty ? laterToday.$1 : from}:00',
            'end_time': '${to.isEmpty ? laterToday.$2 : to}:00',
            'room_number': '204',
            'status': 'Not Marked',
            'is_upcoming': true,
          },
      ],
    };
  }

  return jsonEncode({
    'success': true,
    'data': {
      'student': {'name': 'ARJUN SHAH', 'roll_number': 'DEMO'},
      'modules': [
        {
          'end_date': day(40),
          'courses': [for (final c in _courses) course(c)],
        }
      ],
    },
  });
}

/// Moodle's answers for the sample student, by web service method.
dynamic demoAjax(String method, Map<String, dynamic> args, DateTime now) {
  int at(Duration d) => now.add(d).millisecondsSinceEpoch ~/ 1000;
  switch (method) {
    case 'core_course_get_enrolled_courses_by_timeline_classification':
      return {
        'courses': [
          for (final c in _courses) {'id': 10 + c.$1, 'fullname': c.$2}
        ]
      };
    case 'core_courseformat_get_state':
      final id = args['courseid'] as int;
      final name = _courses
          .firstWhere((c) => 10 + c.$1 == id, orElse: () => _courses.first)
          .$2;
      String url(String mod, int n) =>
          'https://moodle.iimmumbai.ac.in/mod/$mod/view.php?id=${id * 100 + n}';
      return jsonEncode({
        'section': [
          {
            'title': 'General',
            'cmlist': ['${id * 100 + 1}', '${id * 100 + 2}']
          },
          {
            'title': 'Week 6',
            'cmlist': ['${id * 100 + 3}', '${id * 100 + 4}', '${id * 100 + 5}']
          },
        ],
        'cm': [
          {
            'id': '${id * 100 + 1}',
            'name': '$name: course outline',
            'module': 'resource',
            'url': url('resource', 1)
          },
          {
            'id': '${id * 100 + 2}',
            'name': 'Announcements',
            'module': 'forum',
            'url': url('forum', 2)
          },
          {
            'id': '${id * 100 + 3}',
            'name': 'Week 6 slides',
            'module': 'resource',
            'url': url('resource', 3)
          },
          {
            'id': '${id * 100 + 4}',
            'name': 'Readings',
            'module': 'folder',
            'url': url('folder', 4)
          },
          {
            'id': '${id * 100 + 5}',
            'name': 'Assignment 2',
            'module': 'assign',
            'url': url('assign', 5)
          },
        ],
      });
    case 'core_calendar_get_action_events_by_timesort':
      return {
        'events': [
          {
            'id': 1,
            'name': 'Hands-on 3 is due',
            'timesort': at(const Duration(hours: 20)),
            'course': {'fullname': _courses[5].$2},
            'url': 'https://moodle.iimmumbai.ac.in/mod/assign/view.php?id=1605',
            'action': {'name': 'Add submission'},
          },
          {
            'id': 2,
            'name': 'Case memo is due',
            'timesort': at(const Duration(days: 5)),
            'course': {'fullname': _courses[0].$2},
            'url': 'https://moodle.iimmumbai.ac.in/mod/assign/view.php?id=1105',
            'action': {'name': 'Add submission'},
          },
        ]
      };
    case 'core_session_touch':
      return null;
  }
  throw Exception(demoNote);
}
