// The academic calendar the admin publishes: exams, holidays, breaks and
// term dates for the batch. The app shows them in the timetable and month
// view, reminds the student, and stops counting classes on days off.

import 'dart:convert';

import 'notify.dart';

class TermEvent {
  TermEvent(this.title, this.from, this.to, this.kind, this.group);
  final String title;
  final DateTime from;
  final DateTime to;

  /// "exam", "holiday", "break" or "info".
  final String kind;
  final String group;

  bool get oneDay => from == to;

  /// No regular classes on these days.
  bool get dayOff => kind == 'holiday' || kind == 'break' || kind == 'exam';

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  String get label => switch (kind) {
        'exam' => 'Exam',
        'holiday' => 'Holiday',
        'break' => 'Break',
        _ => 'Term date',
      };
}

List<TermEvent> decodeCalendar(String? raw) {
  try {
    return [
      for (final e in jsonDecode(raw ?? '[]') as List)
        TermEvent('${e['title']}', DateTime.parse('${e['from']}'),
            DateTime.parse('${e['to']}'), '${e['kind']}', '${e['group'] ?? ''}')
    ]..sort((a, b) => a.from.compareTo(b.from));
  } catch (_) {
    return [];
  }
}

/// A day as one number (20261124), for quick look-ups.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Every day with no regular classes.
Set<int> offDays(List<TermEvent> events) {
  final out = <int>{};
  for (final e in events.where((e) => e.dayOff)) {
    var d = e.from;
    for (var n = 0; n < 200 && !d.isAfter(e.to); n++) {
      out.add(dayKey(d));
      d = DateTime(d.year, d.month, d.day + 1);
    }
  }
  return out;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "24 Nov" or "20 Dec to 3 Jan".
String spanText(TermEvent e) =>
    e.oneDay ? _day(e.from) : '${_day(e.from)} to ${_day(e.to)}';

/// The evening before a day off, and a week and a day before exams start.
List<Reminder> calendarReminders(List<TermEvent> events) {
  final out = <Reminder>[];
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    final eve = DateTime(e.from.year, e.from.month, e.from.day - 1, 19);
    if (e.kind == 'holiday') {
      out.add(Reminder(970000 + i * 3, eve, 'No classes tomorrow',
          '${e.title}${e.oneDay ? '' : ', until ${_day(e.to)}'}.',
          open: 'timetable'));
    } else if (e.kind == 'break') {
      out.add(Reminder(970000 + i * 3, eve, '${e.title} starts tomorrow',
          'No classes ${e.oneDay ? 'tomorrow' : 'until ${_day(e.to)}'}.',
          open: 'timetable'));
    } else if (e.kind == 'exam') {
      out.add(Reminder(
          970000 + i * 3,
          DateTime(e.from.year, e.from.month, e.from.day - 7, 9),
          '${e.title} in a week',
          'From ${spanText(e)}.',
          open: 'timetable'));
      out.add(Reminder(
          970001 + i * 3, eve, '${e.title} starts tomorrow', spanText(e),
          open: 'timetable'));
    }
  }
  return out;
}
