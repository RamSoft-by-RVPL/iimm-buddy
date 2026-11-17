// Exams and quizzes the student adds, with a countdown and reminders.
// Kept on the phone (and in the phone's backup).

import 'dart:convert';

import 'notify.dart';

const examKinds = ['Exam', 'Quiz', 'Other'];

class Exam {
  Exam(this.id, this.title, this.course, this.at, this.kind);

  /// Made from the time it was added; also numbers its reminders.
  final int id;
  final String title;
  final String course;
  final DateTime at;
  final String kind;

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
