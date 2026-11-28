// Runs of days and weeks with every class attended.

import 'site.dart';

class Streak {
  const Streak({this.days = 0, this.best = 0, this.weeks = 0, this.since});

  /// Class days in a row, up to the latest marked one, with no absence.
  final int days;

  /// The longest such run so far.
  final int best;

  /// Weeks in a row, up to this one, with no absence.
  final int weeks;

  /// The first day of the current run.
  final DateTime? since;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _week(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

/// Counts from classes the attendance site has marked. A class not marked
/// yet neither adds to a run nor breaks it; a day off is skipped.
Streak streakOf(Iterable<ClassSlot> sessions) {
  final absent = <DateTime, bool>{};
  for (final s in sessions) {
    if (s.upcoming || s.cancelled || s.fromSheet) continue;
    if (s.status != 'Present' && s.status != 'Absent') continue;
    final d = _day(s.date);
    absent[d] = (absent[d] ?? false) || s.status == 'Absent';
  }
  final days = absent.keys.toList()..sort();
  var run = 0, best = 0;
  DateTime? since;
  for (final d in days) {
    if (absent[d]!) {
      run = 0;
      since = null;
    } else {
      if (run == 0) since = d;
      run++;
      if (run > best) best = run;
    }
  }
  final weekBad = <DateTime, bool>{};
  for (final d in days) {
    weekBad[_week(d)] = (weekBad[_week(d)] ?? false) || absent[d]!;
  }
  var weeks = 0;
  for (final w in weekBad.keys.toList()..sort()) {
    weeks = weekBad[w]! ? 0 : weeks + 1;
  }
  return Streak(days: run, best: best, weeks: weeks, since: since);
}

/// Runs worth a cheer.
const milestones = [3, 5, 10, 15, 20, 30, 40, 50, 75, 100];

/// The milestone to cheer now: the highest one reached that is above the
/// last one cheered. Null when there is nothing new.
int? milestoneReached(int days, int cheered) {
  int? hit;
  for (final m in milestones) {
    if (m <= days && m > cheered) hit = m;
  }
  return hit;
}

/// What "last cheered" should be once a run has broken, so the same
/// milestones are cheered again the next time round.
int cheeredAfter(int days, int cheered) {
  if (days >= cheered) return cheered;
  var keep = 0;
  for (final m in milestones) {
    if (m <= days) keep = m;
  }
  return keep;
}

/// The next milestone above [days], or null past the last one.
int? nextMilestone(int days) {
  for (final m in milestones) {
    if (m > days) return m;
  }
  return null;
}
