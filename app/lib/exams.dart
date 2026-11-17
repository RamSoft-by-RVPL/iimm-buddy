// Exams and quizzes: the ones the student adds (kept on the phone and in
// its backup) and the papers of their courses from the exam timetable the
// admin publishes. Both get a countdown and reminders.

import 'dart:convert';

import 'notify.dart';
import 'planner.dart';
import 'sheet.dart';

const examKinds = ['Exam', 'Quiz', 'Other'];

class Exam {
  Exam(this.id, this.title, this.course, this.at, this.kind,
      {this.room = '', this.ends, this.note = '', this.published = false});

  /// Made from the time it was added; also numbers its reminders.
  final int id;
  final String title;
  final String course;
  final DateTime at;
  final String kind;

  /// Only for papers from the published exam timetable.
  final String room;
  final DateTime? ends;
  final String note;
  final bool published;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'c': course,
        'a': at.toIso8601String(),
        'k': kind,
      };

  static Exam fromJson(Map<String, dynamic> j) => Exam(j['id'] as int,
      '${j['t']}', '${j['c'] ?? ''}', DateTime.parse('${j['a']}'), '${j['k']}');
}

List<Exam> decodeExams(String? raw) {
  try {
    return [
      for (final j in jsonDecode(raw ?? '[]') as List)
        Exam.fromJson((j as Map).cast<String, dynamic>())
    ]..sort((a, b) => a.at.compareTo(b.at));
  } catch (_) {
    return [];
  }
}

String encodeExams(List<Exam> l) => jsonEncode([for (final e in l) e.toJson()]);

/// "Today", "Tomorrow", "in 12 days", "3 days ago".
String countdown(DateTime at, DateTime now) {
  final days = DateTime(at.year, at.month, at.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days == 0) {
    final gap = at.difference(now);
    if (gap.isNegative) return 'Today';
    if (gap.inMinutes < 60) {
      return 'in ${gap.inMinutes < 1 ? 1 : gap.inMinutes} min';
    }
    return 'in ${gap.inHours} h';
  }
  if (days == 1) return 'Tomorrow';
  if (days > 1) return 'in $days days';
  return days == -1 ? 'Yesterday' : '${-days} days ago';
}

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A week before, the evening before, and two hours before.
List<Reminder> examReminders(List<Exam> exams) => [
      for (final e in exams) ...[
        Reminder(
            950000 + (e.id % 10000) * 4,
            DateTime(e.at.year, e.at.month, e.at.day - 7, 9),
            '${e.kind} in a week: ${e.title}',
            '${e.course.isEmpty ? '' : '${e.course}. '}At ${_time(e.at)}.',
            open: 'home'),
        Reminder(
            950001 + (e.id % 10000) * 4,
            DateTime(e.at.year, e.at.month, e.at.day - 1, 19),
            '${e.kind} tomorrow: ${e.title}',
            '${e.course.isEmpty ? '' : '${e.course}. '}At ${_time(e.at)}.',
            open: 'home'),
        Reminder(
            950002 + (e.id % 10000) * 4,
            e.at.subtract(const Duration(hours: 2)),
            '${e.kind} in 2 hours: ${e.title}',
            '${e.course.isEmpty ? '' : '${e.course}. '}At ${_time(e.at)}.',
            open: 'home'),
      ]
    ];

/// The papers of the student's own courses in the published exam timetable
/// ([raw] is the server's answer), soonest first.
List<Exam> publishedExams(String? raw, List<Course> courses) {
  final out = <Exam>[];
  try {
    for (final x in (jsonDecode(raw ?? '{}') as Map)['exams'] as List) {
      final course = matchCourse('${x['c']}', courses);
      if (course == null) continue;
      final d = '${x['d']}'.split('-').map(int.parse).toList();
      DateTime at(String hm) {
        final t = hm.split(':').map(int.parse).toList();
        return DateTime(d[0], d[1], d[2], t[0], t[1]);
      }

      final e = '${x['e'] ?? ''}';
      out.add(Exam('${x['d']} ${x['s']} ${course.name}'.hashCode & 0x3fffffff,
          course.name, course.name, at('${x['s']}'), 'Exam',
          room: '${x['r'] ?? ''}',
          ends: e.isEmpty ? null : at(e),
          note: '${x['n'] ?? ''}',
          published: true));
    }
  } catch (_) {
    return [];
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

/// "10:00 to 13:00 · Room 101".
String examWhere(Exam e) => [
      e.ends == null ? _time(e.at) : '${_time(e.at)} to ${_time(e.ends!)}',
      if (e.room.isNotEmpty)
        RegExp(r'^\d').hasMatch(e.room) ? 'Room ${e.room}' : e.room,
    ].join(' · ');

/// The evening before and an hour before each published paper.
List<Reminder> publishedExamReminders(List<Exam> exams) => [
      for (var i = 0; i < exams.length && i < 4000; i++) ...[
        Reminder(
            930000 + i * 2,
            DateTime(
                exams[i].at.year, exams[i].at.month, exams[i].at.day - 1, 19),
            'Exam tomorrow: ${exams[i].course}',
            examWhere(exams[i]),
            open: 'home'),
        Reminder(930001 + i * 2, exams[i].at.subtract(const Duration(hours: 1)),
            'Exam in 1 hour: ${exams[i].course}', examWhere(exams[i]),
            open: 'home'),
      ]
    ];
