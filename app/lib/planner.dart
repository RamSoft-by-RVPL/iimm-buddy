// Attendance maths. Everything is whole-number arithmetic so that a course
// sitting exactly on the limit is never pushed over by rounding.

class Course {
  Course({
    required this.id,
    required this.name,
    required this.held,
    required this.attended,
    this.total,
    this.pending = 0,
    this.faculty = '',
    this.label = '',
    this.parts = const [],
    Map<int, int>? weekly,
    List<DateTime>? upcoming,
    List<DateTime>? absences,
    this.horizon,
    this.ends,
  })  : weekly = weekly ?? {},
        upcoming = upcoming ?? [],
        absences = absences ?? [];

  final String id;
  final String name;
  final String faculty;

  /// 'Theory' or 'Lab' when this is one half of a course, else empty.
  final String label;

  /// The theory and lab halves, when this course combines them.
  final List<Course> parts;

  /// Classes conducted so far, and how many of those were attended.
  /// Classes not marked yet count as conducted but not attended, as on the site.
  final int held;
  final int attended;

  /// Conducted classes whose attendance is not marked yet.
  final int pending;

  /// Planned classes in the whole course, if known.
  int? total;

  /// Scheduled classes the site has already published (one entry per class).
  final List<DateTime> upcoming;

  /// The site's timetable is published up to this date. Later dates are
  /// estimated from [weekly].
  final DateTime? horizon;

  /// Usual classes per weekday (DateTime.monday..DateTime.sunday -> count).
  final Map<int, int> weekly;

  /// Last day of the term; nothing is estimated after it.
  final DateTime? ends;

  final List<DateTime> absences;

  /// The same course with more scheduled classes known (from the mailed
  /// timetable) and the timetable known up to [knownTo].
  Course withKnown(List<DateTime> more, DateTime? knownTo,
          {List<Course>? parts}) =>
      Course(
        id: id,
        name: name,
        held: held,
        attended: attended,
        total: total,
        pending: pending,
        faculty: faculty,
        label: label,
        parts: parts ?? this.parts,
        weekly: weekly,
        upcoming: [...upcoming, ...more]..sort(),
        absences: absences,
        horizon:
            knownTo == null || (horizon != null && horizon!.isAfter(knownTo))
                ? horizon
                : knownTo,
        ends: ends,
      );

  int get missed => held - attended;
  double get percent => held == 0 ? 100 : attended * 100 / held;

  static String _d(DateTime d) => d.toIso8601String().substring(0, 10);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'faculty': faculty,
        'held': held,
        'attended': attended,
        'pending': pending,
        'total': total,
        'weekly': weekly.map((k, v) => MapEntry('$k', v)),
        'upcoming': upcoming.map(_d).toList(),
        'absences': absences.map(_d).toList(),
        'horizon': horizon == null ? null : _d(horizon!),
        'ends': ends == null ? null : _d(ends!),
      };

  static Course fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String,
        name: j['name'] as String,
        faculty: (j['faculty'] ?? '') as String,
        held: j['held'] as int,
        attended: j['attended'] as int,
        pending: (j['pending'] ?? 0) as int,
        total: j['total'] as int?,
        weekly: ((j['weekly'] as Map?) ?? {})
            .map((k, v) => MapEntry(int.parse('$k'), v as int)),
        upcoming: [
          for (final d in (j['upcoming'] as List? ?? [])) DateTime.parse(d)
        ],
        absences: [
          for (final d in (j['absences'] as List? ?? [])) DateTime.parse(d)
        ],
        horizon: j['horizon'] == null ? null : DateTime.parse(j['horizon']),
        ends: j['ends'] == null ? null : DateTime.parse(j['ends']),
      );
}

bool meets(int attended, int held, int minPct) =>
    held == 0 || attended * 100 >= minPct * held;

/// How many more classes can be missed while staying at or above the limit.
/// Negative means the course is already short by that many absences.
///
/// With a known course length this is the budget for the whole course.
/// Without it, it is how many classes in a row can be skipped right now.
int leaveLeft(Course c, int minPct) {
  final total = c.total;
  if (total != null && total >= c.held) {
    return total * (100 - minPct) ~/ 100 - c.missed;
  }
  if (c.held == 0) return 0;
  return c.attended * 100 ~/ minPct - c.held;
}

/// Classes that must be attended in a row to get back to the limit.
int classesToRecover(Course c, int minPct) {
  final gap = minPct * c.held - 100 * c.attended;
  if (gap <= 0) return 0;
  if (minPct >= 100) return -1; // cannot recover
  return (gap + (100 - minPct) - 1) ~/ (100 - minPct);
}

/// Days with no regular classes (holidays, breaks, exam weeks), as numbers
/// like 20261124. Set from the academic calendar; classes the college has
/// actually published on such a day are still counted.
Set<int> plannerDaysOff = {};

/// Exam days from the academic calendar. They are days off for classes, but
/// no day to be away: a break is never suggested across one.
Set<int> plannerExamDays = {};

/// The last day of classes this term ("Classes End" in the academic
/// calendar). No classes are assumed after it.
DateTime? plannerClassesEnd;

/// The first exam day from [from] to [to], both included, if any.
DateTime? firstExamIn(DateTime from, DateTime to) {
  for (var d = DateTime(from.year, from.month, from.day);
      !d.isAfter(to);
      d = DateTime(d.year, d.month, d.day + 1)) {
    if (plannerExamDays.contains(_dayNo(d))) return d;
  }
  return null;
}

/// Days with at least one published class (attendance site or timetable),
/// as numbers like 20261121. A Saturday or Sunday counts as a holiday
/// unless it is in here.
Set<int> plannerClassDays = {};

int _dayNo(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// A Saturday or Sunday with no class published on it.
bool weekendOff(DateTime d) =>
    (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) &&
    !plannerClassDays.contains(_dayNo(d));

/// A normal teaching day has four classes, 09:00 to 17:10. For days beyond
/// the published timetable the app assumes a full day, Monday to Friday:
/// weekends are holidays until a class is published on one.
const classesPerDay = 4;

/// Each course's share of a teaching day, by course id (see
/// [setPlannerShares]). Empty means: fall back to the weekly pattern.
Map<String, double> plannerShare = {};

/// Where each course's share starts on the line from 0 to 1. The shares sit
/// side by side, so every class slot belongs to exactly one course.
Map<String, double> plannerStart = {};

/// Splits a teaching day between the courses by how many classes each still
/// has left, so a course near its end gets fewer of the four slots.
void setPlannerShares(List<Course> courses) {
  final leaves = [
    for (final c in courses) ...(c.parts.isEmpty ? [c] : c.parts)
  ];
  double weight(Course c) {
    final t = c.total;
    if (t != null) return (t - c.held < 0 ? 0 : t - c.held).toDouble();
    return c.weekly.values.fold<int>(0, (a, b) => a + b).toDouble();
  }

  final sum = leaves.fold<double>(0, (a, c) => a + weight(c));
  final share = <String, double>{};
  final start = <String, double>{};
  if (sum > 0) {
    var at = 0.0;
    for (var n = 0; n < leaves.length; n++) {
      final c = leaves[n];
      final w = weight(c) / sum;
      start[c.id] = at;
      // The last one runs to exactly 1 so rounding never drops a slot.
      share[c.id] = n == leaves.length - 1 ? 1 - at : w;
      at += w;
    }
    for (final c in courses.where((c) => c.parts.isNotEmpty)) {
      start[c.id] = start[c.parts.first.id] ?? 0;
      share[c.id] = c.parts.fold<double>(0, (a, p) => a + (share[p.id] ?? 0));
    }
  }
  plannerShare = share;
  plannerStart = start;
}

/// Teaching days (Monday to Friday) since Monday 1 Jan 2024.
int _teachingDay(DateTime d) {
  final n = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(2024, 1, 1))
      .inDays;
  return (n ~/ 7) * 5 + n % 7;
}

/// How many of the four slots of day [d] go to the course whose share
/// starts at [start]. The slots are spread out evenly over the days, so a
/// day always adds up to four classes across all courses and each course
/// gets its share over a few days.
int _slotsOn(DateTime d, double start, double share) {
  const step = 0.6180339887498949; // spreads the slots evenly
  final k = _teachingDay(d);
  var n = 0;
  for (var j = 0; j < classesPerDay; j++) {
    final x = ((k * classesPerDay + j) * step) % 1;
    if (x >= start && x < start + share) n++;
  }
  return n;
}

/// Classes of [c] on dates from [from] to [to], both included: published
/// classes where the timetable is out, four classes a day shared between
/// the courses after that (or the usual weekly pattern if no share is set).
int classesBetween(Course c, DateTime from, DateTime to) {
  var d = DateTime(from.year, from.month, from.day);
  var end = DateTime(to.year, to.month, to.day);
  var n = c.upcoming.where((u) => !u.isBefore(d) && !u.isAfter(end)).length;
  final h = c.horizon;
  if (c.ends != null && end.isAfter(c.ends!)) end = c.ends!;
  final last = plannerClassesEnd;
  if (last != null && end.isAfter(last) && (h == null || last.isAfter(h))) {
    end = last;
  }
  if (h != null && !d.isAfter(h)) d = DateTime(h.year, h.month, h.day + 1);
  final share = plannerShare[c.id];
  final start = plannerStart[c.id] ?? 0;
  while (!d.isAfter(end)) {
    // Past the published timetable nothing is published, so a weekend
    // is always a holiday here.
    final weekend =
        d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    if (!weekend && !plannerDaysOff.contains(_dayNo(d))) {
      if (share != null) {
        n += _slotsOn(d, start, share);
      } else {
        n += c.weekly[d.weekday] ?? 0;
      }
    }
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return n;
}

/// True if part of the range lies beyond the published timetable.
bool isEstimated(Course c, DateTime to) =>
    c.horizon == null || to.isAfter(c.horizon!);

class HolidayImpact {
  HolidayImpact({
    required this.course,
    required this.missed,
    required this.attendedAfter,
    required this.heldAfter,
    required this.safe,
    required this.recover,
    required this.leaveAfter,
  });

  final Course course;

  /// Classes missed during the holiday.
  final int missed;

  /// Position on the day you come back.
  final int attendedAfter;
  final int heldAfter;

  /// True if the course can still finish at or above the limit.
  final bool safe;

  /// Classes to attend in a row after returning, if below the limit then.
  final int recover;

  /// Leave still available after the holiday (negative = over the budget).
  final int leaveAfter;

  double get percentAfter =>
      heldAfter == 0 ? 100 : attendedAfter * 100 / heldAfter;
}

/// What happens to [c] if every class from [from] to [to] is missed and every
/// class between [today] and the holiday is attended.
HolidayImpact holidayImpact(
    Course c, DateTime today, DateTime from, DateTime to, int minPct) {
  final dayBefore = DateTime(from.year, from.month, from.day - 1);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  var before = classesBetween(c, tomorrow, dayBefore);
  var missed = classesBetween(c, from, to);

  // Never count more classes than the course has left.
  final total = c.total;
  if (total != null && total >= c.held) {
    final remaining = total - c.held;
    if (before > remaining) before = remaining;
    if (missed > remaining - before) missed = remaining - before;
  }

  final after = Course(
    id: c.id,
    name: c.name,
    held: c.held + before + missed,
    attended: c.attended + before,
    total: c.total,
  );
  final left = leaveLeft(after, minPct);
  return HolidayImpact(
    course: c,
    missed: missed,
    attendedAfter: after.attended,
    heldAfter: after.held,
    safe: left >= 0,
    recover: classesToRecover(after, minPct),
    leaveAfter: left,
  );
}

/// Joins the theory and lab halves of one course into a single course that
/// keeps the halves in [Course.parts].
Course combine(String name, List<Course> parts) {
  final weekly = <int, int>{};
  for (final p in parts) {
    p.weekly.forEach((d, n) => weekly[d] = (weekly[d] ?? 0) + n);
  }
  int sum(int Function(Course) f) => parts.fold(0, (a, p) => a + f(p));
  return Course(
    id: parts.map((p) => p.id).join('+'),
    name: name,
    // Each teacher once: theory "A" and lab "A, B" make "A, B".
    faculty: parts
        .expand((p) => p.faculty.split(','))
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toSet()
        .join(', '),
    held: sum((p) => p.held),
    attended: sum((p) => p.attended),
    pending: sum((p) => p.pending),
    total: parts.every((p) => p.total != null) ? sum((p) => p.total!) : null,
    weekly: weekly,
    upcoming: [for (final p in parts) ...p.upcoming]..sort(),
    absences: [for (final p in parts) ...p.absences]..sort(),
    horizon: parts.first.horizon,
    ends: parts.first.ends,
    parts: parts,
  );
}

String classes(int n) => n == 1 ? '1 class' : '$n classes';

/// One sentence on where a course stands against the limit.
String statusText(Course c, int minPct) {
  final left = leaveLeft(c, minPct);
  final below = !meets(c.attended, c.held, minPct);
  if (c.total != null) {
    if (left < 0) {
      return 'Over the limit by ${classes(-left)}. Cannot reach $minPct% '
          'even with full attendance.';
    }
    if (below) {
      return 'Below $minPct% now. Attend the next '
          '${classes(classesToRecover(c, minPct))}; '
          '${left == 0 ? 'no leave' : '${classes(left)} of leave'} left after that.';
    }
    return left == 0
        ? 'No leave left. Attend every class.'
        : 'Can miss ${classes(left)} more.';
  }
  if (below) {
    return 'Below $minPct%. Attend the next ${classes(classesToRecover(c, minPct))} to recover.';
  }
  return left == 0
      ? 'No leave left right now.'
      : 'Can miss ${classes(left)} in a row right now.';
}

/// True when the holiday itself pushes the course over (a course that was
/// already short is not blamed on the holiday).
bool breaksCourse(HolidayImpact i, int minPct) =>
    i.missed > 0 && !i.safe && leaveLeft(i.course, minPct) >= 0;

/// Last day a holiday starting on [from] can run to without breaking any
/// course, looking at most [cap] days ahead. Null if even one day is too many.
DateTime? safeUntil(
    List<Course> courses, DateTime today, DateTime from, int minPct,
    {int cap = 60}) {
  DateTime? last;
  for (var k = 0; k < cap; k++) {
    final to = DateTime(from.year, from.month, from.day + k);
    if (courses.any((c) =>
        breaksCourse(holidayImpact(c, today, from, to, minPct), minPct))) {
      break;
    }
    last = to;
  }
  return last;
}

class BreakIdea {
  BreakIdea(this.from, this.to, this.missed, [this.leave = 0]);
  final DateTime from;
  final DateTime to;
  final int missed;

  /// Teaching days inside the break (the days of leave it takes).
  final int leave;
  int get days => to.difference(from).inDays + 1;
}

/// True for a weekend with no class published on it, or a day off from the
/// academic calendar.
bool isDayOff(DateTime d) =>
    weekendOff(d) || plannerDaysOff.contains(_dayNo(d));

/// Long weekends: a weekend or a run of days off (holidays, breaks) made
/// longer by taking at most [maxLeave] days of leave next to it. Only breaks
/// that keep every course safe, miss a class and last three days or more.
/// Picks the ones
/// that give the most free days for the leave taken, at most [count], not
/// overlapping, in date order.
List<BreakIdea> longWeekends(List<Course> courses, DateTime today, int minPct,
    {int window = 42, int maxLeave = 2, int count = 4}) {
  DateTime day(int k) => DateTime(today.year, today.month, today.day + k);
  final tomorrow = day(1);

  // Runs of days off in the window.
  final runs = <(DateTime, DateTime)>[];
  // A run must start inside the window but may end after it (a winter
  // break that starts in the window is counted whole).
  for (var k = 1;
      k <= window || (runs.isNotEmpty && runs.last.$2 == day(k - 1));
      k++) {
    final d = day(k);
    if (!isDayOff(d)) continue;
    if (runs.isNotEmpty &&
        runs.last.$2 == DateTime(d.year, d.month, d.day - 1)) {
      runs.last = (runs.last.$1, d);
    } else {
      runs.add((d, d));
    }
  }

  final all = <BreakIdea>[];
  final seen = <String>{};
  for (final (start, end) in runs) {
    for (var a = 0; a <= maxLeave + 1; a++) {
      for (var b = 0; b <= maxLeave + 1; b++) {
        final from = DateTime(start.year, start.month, start.day - a);
        final to = DateTime(end.year, end.month, end.day + b);
        if (from.isBefore(tomorrow)) continue;
        if (!seen.add('$from$to')) continue;
        var leave = 0;
        for (var d = from;
            !d.isAfter(to);
            d = DateTime(d.year, d.month, d.day + 1)) {
          if (!isDayOff(d)) leave++;
        }
        if (leave < 1 || leave > maxLeave) continue;
        final idea = BreakIdea(from, to, 0, leave);
        if (idea.days < 3) continue;
        if (firstExamIn(from, to) != null) continue;
        final hits = [
          for (final c in courses) holidayImpact(c, today, from, to, minPct)
        ];
        if (hits.any((i) => breaksCourse(i, minPct))) continue;
        final missed = hits.fold(0, (s, i) => s + i.missed);
        // Nothing missed means the courses have ended by then; the next
        // term's classes are not known, so it is no real suggestion.
        if (missed == 0) continue;
        all.add(BreakIdea(from, to, missed, leave));
      }
    }
  }

  // Most free days first, then the least leave for them, then the fewest
  // classes missed, then the soonest.
  all.sort((x, y) {
    var d = (y.days - y.leave).compareTo(x.days - x.leave);
    if (d != 0) return d;
    d = x.leave.compareTo(y.leave);
    if (d != 0) return d;
    d = x.missed.compareTo(y.missed);
    return d != 0 ? d : x.from.compareTo(y.from);
  });
  final out = <BreakIdea>[];
  for (final i in all) {
    if (out.every((o) => i.to.isBefore(o.from) || i.from.isAfter(o.to))) {
      out.add(i);
      if (out.length == count) break;
    }
  }
  return out..sort((a, b) => a.from.compareTo(b.from));
}

/// The longest safe breaks starting in the next [window] days, longest first,
/// not overlapping each other. Only breaks that miss at least one class and
/// last at least three days are worth suggesting.
List<BreakIdea> suggestBreaks(List<Course> courses, DateTime today, int minPct,
    {int window = 45, int cap = 21, int count = 3}) {
  final all = <BreakIdea>[];
  for (var k = 1; k <= window; k++) {
    final from = DateTime(today.year, today.month, today.day + k);
    final safe = safeUntil(courses, today, from, minPct, cap: cap);
    if (safe == null) continue;
    var to = safe;
    // Back before the exams start.
    final exam = firstExamIn(from, to);
    if (exam != null) to = DateTime(exam.year, exam.month, exam.day - 1);
    if (to.isBefore(from)) continue;
    // Counted through holidayImpact so classes past the end of a course
    // are not counted.
    final missed = courses.fold(
        0, (a, c) => a + holidayImpact(c, today, from, to, minPct).missed);
    final idea = BreakIdea(from, to, missed);
    if (idea.days >= 3 && missed > 0) all.add(idea);
  }
  all.sort((a, b) {
    final d = b.days.compareTo(a.days);
    return d != 0 ? d : a.from.compareTo(b.from);
  });
  final out = <BreakIdea>[];
  for (final i in all) {
    if (out.every((o) => i.to.isBefore(o.from) || i.from.isAfter(o.to))) {
      out.add(i);
      if (out.length == count) break;
    }
  }
  return out..sort((a, b) => a.from.compareTo(b.from));
}

/// Where a course ends up: (at the current rate, attending everything from
/// now). Null when the course length is not known or nothing is left.
(double, double)? projection(Course c) {
  final total = c.total;
  if (total == null || c.held == 0 || total <= c.held) return null;
  final left = total - c.held;
  final atRate = c.attended + (left * c.attended / c.held).round();
  return (atRate * 100 / total, (c.attended + left) * 100 / total);
}

/// Attendance percentage after each class held so far, oldest first.
/// [present] has one entry per class: true when attended.
List<double> runningPercent(List<bool> present) {
  final out = <double>[];
  var got = 0;
  for (var i = 0; i < present.length; i++) {
    if (present[i]) got++;
    out.add(got * 100 / (i + 1));
  }
  return out;
}
