// The Sunday evening summary: next week's classes, holidays, exams and
// deadlines, and the courses close to the minimum. Worked out from what
// the phone already has and scheduled again after every refresh, so it
// goes out with the latest data.

import 'acal.dart';
import 'exams.dart';
import 'moodle.dart' show Deadline;
import 'notify.dart';
import 'planner.dart';
import 'site.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

String _d(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// The coming Sunday at 7 PM (today, if it is Sunday before 7 PM).
DateTime nextSummaryTime(DateTime now) {
  var d = DateTime(now.year, now.month, now.day + (7 - now.weekday) % 7, 19);
  if (!d.isAfter(now)) d = DateTime(d.year, d.month, d.day + 7, 19);
  return d;
}

bool _within(DateTime d, DateTime from, DateTime to) =>
    !d.isBefore(from) && d.isBefore(to);

/// The summary for the week after [at] (a Sunday evening).
Reminder weekSummary({
  required DateTime at,
  required Snapshot snap,
  required int minPct,
  List<TermEvent> calendar = const [],
  List<Exam> exams = const [],
  List<Deadline> deadlines = const [],
  String Function(String course)? short,
}) {
  final from = DateTime(at.year, at.month, at.day + 1); // Monday
  final to = DateTime(from.year, from.month, from.day + 7);
  String name(String c) => short?.call(c) ?? c;
  final lines = <String>[];

  // Classes, day by day.
  final perDay = <int, int>{};
  for (final s in snap.sessions) {
    if (s.cancelled || !_within(s.date, from, to)) continue;
    perDay[s.date.weekday] = (perDay[s.date.weekday] ?? 0) + 1;
  }
  final total = perDay.values.fold(0, (a, b) => a + b);
  if (total == 0) {
    lines.add('Classes: the timetable for the week is not out yet.');
  } else {
    final days = [
      for (var w = 1; w <= 7; w++)
        if (perDay[w] != null) '${_days[w - 1]} ${perDay[w]}'
    ];
    lines
        .add('$total ${total == 1 ? 'class' : 'classes'}: ${days.join(', ')}.');
  }

  // Holidays, breaks and other dates.
  for (final e in calendar) {
    if (e.to.isBefore(from) || !e.from.isBefore(to)) continue;
    final kind = switch (e.kind) {
      'holiday' => 'Holiday',
      'break' => 'Break',
      'exam' => 'Exams',
      _ => 'Date',
    };
    lines.add(
        '$kind ${e.oneDay ? _d(e.from) : '${_d(e.from)} to ${_d(e.to)}'}: ${e.title}.');
  }

  // Exams and quizzes.
  final soon = [
    for (final x in exams)
      if (_within(x.at, from, to)) x
  ]..sort((a, b) => a.at.compareTo(b.at));
  for (final x in soon.take(4)) {
    lines.add('${x.kind.isEmpty ? 'Exam' : x.kind} ${_d(x.at)}: ${x.title}.');
  }

  // Deadlines.
  final due = [
    for (final x in deadlines)
      if (_within(x.due, from, to)) x
  ]..sort((a, b) => a.due.compareTo(b.due));
  if (due.isNotEmpty) {
    final shown = [
      for (final x in due.take(3)) '${x.name} (${_days[x.due.weekday - 1]})'
    ];
    lines.add('Due: ${shown.join(', ')}'
        '${due.length > 3 ? ' and ${due.length - 3} more' : ''}.');
  }

  // Courses to watch.
  for (final c in snap.courses) {
    if (c.held == 0) continue;
    final pct = c.attended * 100 / c.held;
    if (pct < minPct) {
      final need = classesToRecover(c, minPct);
      lines.add('${name(c.name)} is at ${pct.toStringAsFixed(1)}%: '
          'attend ${need == 1 ? 'the next class' : 'all of the next $need'}.');
    } else if (leaveLeft(c, minPct) == 0) {
      lines.add('${name(c.name)}: no leave left, don\'t skip.');
    }
  }

  return Reminder(5100, at, 'Your week ahead', lines.join('\n'), open: 'home');
}

/// Schedules the next summary, or takes it away when switched off.
Future<void> scheduleWeekSummary(Store store, Snapshot snap,
    {List<Deadline> deadlines = const []}) {
  final on = store.prefs.getBool('week_summary') ?? true;
  return scheduleReminders(store.prefs, 'rem_week', 'summary', [
    if (on)
      weekSummary(
        at: nextSummaryTime(DateTime.now()),
        snap: snap,
        minPct: store.minPct,
        calendar: store.calendar,
        exams: [...store.exams, ...store.publishedExamsFor(snap.courses)],
        deadlines: deadlines,
        short: (c) => store.shortNames[c] ?? c,
      )
  ]);
}
