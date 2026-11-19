// Reads the attendance site's student dashboard API and keeps a local copy.

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'acal.dart';
import 'exams.dart';
import 'leave.dart';
import 'menu.dart';
import 'planner.dart';
import 'sheet.dart';

/// One class on the timetable, past or still to come.
class ClassSlot {
  ClassSlot(this.id, this.date, this.start, this.end, this.room, this.course,
      this.courseId, this.status, this.upcoming,
      {this.fromSheet = false,
      this.cancelled = false,
      this.why = '',
      this.faculty = ''});
  final int id;
  final DateTime date;
  final String start; // "14:00"
  final String end;
  final String room;
  final String course;
  final String courseId;

  /// "Present", "Absent" or "Not Marked".
  final String status;
  final bool upcoming;

  /// Start as a local date and time.
  DateTime get startsAt {
    final p = start.split(':');
    return DateTime(date.year, date.month, date.day, int.tryParse(p.first) ?? 0,
        p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  /// True for a class known only from the mailed timetable: the attendance
  /// site has not listed it yet, so its attendance comes later.
  final bool fromSheet;

  /// End as a local date and time.
  DateTime get endsAt {
    final p = end.split(':');
    return DateTime(date.year, date.month, date.day, int.tryParse(p.first) ?? 0,
        p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  /// Called off: by the admin, or gone from the attendance site.
  final bool cancelled;

  /// Why, when known (the admin's reason).
  final String why;

  /// Who takes it, from the attendance site or the mailed timetable.
  final String faculty;

  bool get unmarked =>
      !upcoming && !fromSheet && !cancelled && status == 'Not Marked';

  ClassSlot asCancelled(String why) =>
      ClassSlot(id, date, start, end, room, course, courseId, status, upcoming,
          fromSheet: fromSheet, cancelled: true, why: why, faculty: faculty);

  ClassSlot withFaculty(String f) =>
      ClassSlot(id, date, start, end, room, course, courseId, status, upcoming,
          fromSheet: fromSheet, cancelled: cancelled, why: why, faculty: f);

  String get slotKey => '${date.year}-${date.month}-${date.day} $start';
}

class Snapshot {
  Snapshot({
    required this.studentName,
    required this.roll,
    required this.courses,
    required this.syncedAt,
    this.sessions = const [],
  });

  final String studentName;
  final String roll;
  final List<Course> courses;
  final DateTime syncedAt;

  /// Every class on the timetable, oldest first.
  final List<ClassSlot> sessions;

  /// Published classes still to come, soonest first.
  List<ClassSlot> get next => [
        for (final s in sessions)
          if (s.upcoming && !s.cancelled) s
      ];

  /// The course (theory and lab combined) that a class belongs to.
  Course? courseOf(ClassSlot s) {
    for (final c in courses) {
      if (c.id == s.courseId || c.parts.any((p) => p.id == s.courseId)) {
        return c;
      }
    }
    return null;
  }

  /// The same data with classes from the mailed timetable added.
  Snapshot withSheet(List<SheetClass> sheet, DateTime now) {
    if (sheet.isEmpty) return this;
    final extra = extraSlots(this, sheet, now);
    // The sheet names the one teacher of each class; the site lists every
    // teacher of the course. Use the sheet's when it has the same course
    // at that time.
    final teacher = <String, SheetClass>{
      for (final c in sheet)
        if (c.faculty.isNotEmpty)
          '${c.date.year}-${c.date.month}-${c.date.day} ${c.start}': c
    };
    ClassSlot named1(ClassSlot s) {
      final c = teacher[s.slotKey];
      if (c == null) return s;
      final own = courseOf(s);
      final same = own != null && matchCourse(c.course, courses)?.id == own.id;
      return same || s.faculty.isEmpty ? s.withFaculty(c.faculty) : s;
    }

    final named = [for (final s in sessions) named1(s)];
    final all = [...named, ...extra]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.start.compareTo(b.start);
      });
    // The holiday planner must count these classes too, and the sheet tells
    // us the timetable up to its last day.
    final lastDay =
        sheet.map((c) => c.date).reduce((a, b) => a.isAfter(b) ? a : b);
    List<DateTime> of(String id) => [
          for (final s in extra)
            if (s.upcoming && !s.cancelled && s.courseId == id) s.date
        ];
    final known = [
      for (final c in courses)
        c.parts.isEmpty
            ? c.withKnown(of(c.id), lastDay)
            : c.withKnown([for (final p in c.parts) ...of(p.id)], lastDay,
                parts: [
                  for (final p in c.parts) p.withKnown(of(p.id), lastDay)
                ])
    ];
    return Snapshot(
        studentName: studentName,
        roll: roll,
        courses: known,
        syncedAt: syncedAt,
        sessions: all);
  }

  /// The same data with the classes the admin has called off marked
  /// cancelled. They stay on the timetable but no longer count: an unmarked
  /// one is taken out of the classes held, a coming one out of the classes
  /// still to come. Classes already marked present or absent stay as they
  /// are: the register is the record.
  Snapshot withCancelled(List<Cancelled> off) {
    if (off.isEmpty) return this;
    Cancelled? hit(ClassSlot s) {
      if (s.cancelled || s.status == 'Present' || s.status == 'Absent') {
        return null;
      }
      for (final x in off) {
        if (x.start != s.start || !_sameDay(x.date, s.date)) continue;
        if (x.course.isEmpty) return x;
        final named = matchCourse(x.course, courses);
        if (named != null) {
          if (courseOf(s)?.id == named.id) return x;
        } else if (s.course.toLowerCase().contains(x.course.toLowerCase()) ||
            x.course.toLowerCase().contains(s.course.toLowerCase())) {
          return x;
        }
      }
      return null;
    }

    var list = courses;
    var changed = false;
    final marked = [
      for (final s in sessions)
        if (hit(s) case final x?)
          () {
            changed = true;
            final wasHeld = !s.fromSheet && !s.upcoming;
            list = [
              for (final c in list) _lessOne(c, s.courseId, s.date, wasHeld)
            ];
            return s.asCancelled(x.why);
          }()
        else
          s
    ];
    if (!changed) return this;
    return Snapshot(
        studentName: studentName,
        roll: roll,
        courses: list,
        syncedAt: syncedAt,
        sessions: marked);
  }

  /// The same data with classes that dropped off the attendance site shown
  /// again, as cancelled. Call before [withSheet], so the mailed timetable
  /// does not bring them back as "not on portal yet".
  Snapshot withGone(List<ClassSlot> gone) {
    final taken = {for (final s in sessions) s.slotKey};
    final add = [
      for (final g in gone)
        if (!taken.contains(g.slotKey)) g.asCancelled(g.why)
    ];
    if (add.isEmpty) return this;
    return Snapshot(
        studentName: studentName,
        roll: roll,
        courses: courses,
        syncedAt: syncedAt,
        sessions: [...sessions, ...add]..sort((a, b) {
            final d = a.date.compareTo(b.date);
            return d != 0 ? d : a.start.compareTo(b.start);
          }));
  }

  int get held => courses.fold(0, (a, c) => a + c.held);
  int get attended => courses.fold(0, (a, c) => a + c.attended);
  double get percent => held == 0 ? 100 : attended * 100 / held;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// [c] with one class of [partId] on [day] no longer counted: out of the
/// classes held (an unmarked class) or out of the classes still to come.
Course _lessOne(Course c, String partId, DateTime day, bool wasHeld) {
  if (c.parts.isNotEmpty) {
    if (!c.parts.any((p) => p.id == partId)) return c;
    final parts = [for (final p in c.parts) _lessOne(p, partId, day, wasHeld)];
    return combine(c.name, parts);
  }
  if (c.id != partId) return c;
  final upcoming = [...c.upcoming];
  if (!wasHeld) {
    final i = upcoming.indexWhere((d) => _sameDay(d, day));
    if (i >= 0) upcoming.removeAt(i);
  }
  final held = wasHeld && c.held > 0 && c.pending > 0;
  return Course(
    id: c.id,
    name: c.name,
    held: held ? c.held - 1 : c.held,
    attended: c.attended,
    pending: held ? c.pending - 1 : c.pending,
    total: c.total,
    faculty: c.faculty,
    label: c.label,
    weekly: c.weekly,
    upcoming: upcoming,
    absences: c.absences,
    horizon: c.horizon,
    ends: c.ends,
  );
}

/// Classes still to come that the attendance site listed in [before] but
/// not in [after], and that did not just move to another time: those were
/// cancelled. Nothing when the new reading looks broken or a whole new
/// timetable came in.
List<ClassSlot> vanishedClasses(Snapshot before, Snapshot after, DateTime now) {
  if (after.sessions.isEmpty) return [];
  final nowKeys = {for (final s in after.sessions) s.slotKey};
  final wasKeys = {for (final s in before.sessions) s.slotKey};
  final gone = [
    for (final s in before.sessions)
      if (!s.fromSheet &&
          s.startsAt.isAfter(now) &&
          !nowKeys.contains(s.slotKey))
        s
  ];
  if (gone.isEmpty || gone.length > 12) return [];
  // New classes of the same course nearby are where a class moved to.
  final added = [
    for (final s in after.sessions)
      if (s.startsAt.isAfter(now) && !wasKeys.contains(s.slotKey)) s
  ];
  final out = <ClassSlot>[];
  for (final g in gone) {
    final i = added.indexWhere((a) =>
        a.courseId == g.courseId &&
        a.startsAt.difference(g.startsAt).inDays.abs() <= 7);
    if (i >= 0) {
      added.removeAt(i);
    } else {
      out.add(g);
    }
  }
  return out;
}

Map<String, dynamic> _slotJson(ClassSlot s) => {
      'd': s.date.toIso8601String().substring(0, 10),
      's': s.start,
      'e': s.end,
      'r': s.room,
      'c': s.course,
      'i': s.courseId,
      'f': s.faculty,
    };

ClassSlot _slotOf(Map j) => ClassSlot(
    0,
    DateTime.parse('${j['d']}'),
    '${j['s']}',
    '${j['e']}',
    '${j['r']}',
    '${j['c']}',
    '${j['i']}',
    'Not Marked',
    true,
    cancelled: true,
    why: 'Removed from the portal',
    faculty: '${j['f'] ?? ''}');

/// A class the admin has called off (from /api/cancelled).
class Cancelled {
  Cancelled(this.date, this.start, this.course, [this.why = '']);
  final DateTime date;
  final String start; // "14:00"
  final String course; // as on the timetable; '' = every class then
  final String why;

  static List<Cancelled> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final j in (jsonDecode(raw) as Map)['classes'] as List)
          Cancelled(DateTime.parse('${j['d']}'), '${j['s']}', '${j['c'] ?? ''}',
              '${j['why'] ?? ''}')
      ];
    } catch (_) {
      return [];
    }
  }
}

/// "Name Lab", "Name Theory", "Name (Lab)", "Name (Theory)".
final _half =
    RegExp(r'^(.*?)\s*\(?\b(lab|theory)\)?\s*$', caseSensitive: false);

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

int _minutes(String start, String end) {
  int m(String t) {
    final p = t.split(':');
    return p.length < 2 ? 0 : _int(p[0]) * 60 + _int(p[1]);
  }

  return m(end) - m(start);
}

/// Turns the body of `api/student-dashboard.php?action=summary` into a
/// snapshot. [totals] holds course lengths the user has set by hand.
Snapshot parseSummary(String body, DateTime now, Map<String, int> totals) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  if (root['success'] != true) {
    throw Exception(root['message'] ?? 'The site returned an error');
  }
  final data = root['data'] as Map<String, dynamic>;
  final student = (data['student'] as Map?) ?? {};

  // The timetable is published up to the latest date any course has.
  DateTime? horizon;
  final modules = (data['modules'] as List?) ?? [];
  for (final m in modules) {
    for (final c in (m['courses'] as List?) ?? []) {
      for (final s in (c['sessions'] as List?) ?? []) {
        final d = DateTime.tryParse('${s['date']}');
        if (d != null && (horizon == null || d.isAfter(horizon))) horizon = d;
      }
    }
  }

  final groups = <String, List<Course>>{}; // keeps the site's order
  final next = <ClassSlot>[];
  for (final m in modules) {
    final ends = DateTime.tryParse('${m['end_date']}');
    for (final c in (m['courses'] as List?) ?? []) {
      final counts = (c['counts'] as Map?) ?? {};
      final sessions = (c['sessions'] as List?) ?? [];
      final upcoming = <DateTime>[];
      final absences = <DateTime>[];
      final recent = <int, int>{};
      var minutes = 0;
      for (final s in sessions) {
        final d = DateTime.tryParse('${s['date']}');
        if (d == null) continue;
        String hm(dynamic t) => '$t'.length >= 5 ? '$t'.substring(0, 5) : '$t';
        final slot = ClassSlot(
            _int(s['schedule_id']),
            d,
            hm(s['start_time']),
            hm(s['end_time']),
            '${s['room_number'] ?? ''}',
            '${c['course_name']}'.trim(),
            '${c['course_id']}',
            '${s['status'] ?? ''}',
            s['is_upcoming'] == true,
            faculty: '${c['faculty_names'] ?? ''}'.trim());
        // A class later today counts as coming up even if the site has
        // stopped calling it upcoming: it still needs its reminder.
        next.add(!slot.upcoming &&
                slot.status == 'Not Marked' &&
                slot.startsAt.isAfter(now)
            ? ClassSlot(slot.id, slot.date, slot.start, slot.end, slot.room,
                slot.course, slot.courseId, slot.status, true,
                faculty: slot.faculty)
            : slot);
        if (s['is_upcoming'] == true) {
          upcoming.add(d);
        } else if (s['status'] == 'Absent') {
          absences.add(d);
        }
        final len = _minutes('${s['start_time']}', '${s['end_time']}');
        if (len > minutes) minutes = len;
        // Usual pattern: classes per weekday over the last four weeks.
        if (horizon != null && horizon.difference(d).inDays < 28) {
          recent[d.weekday] = (recent[d.weekday] ?? 0) + 1;
        }
      }
      final weekly = <int, int>{};
      recent.forEach((day, n) {
        final perWeek = (n / 4).round();
        if (perWeek > 0) weekly[day] = perWeek;
      });

      final id = '${c['course_id']}';
      final held = _int(counts['total_sessions']);
      // Course length from its hours, e.g. 45 hours of 90-minute classes = 30.
      // The site rounds hours (22.5 shows as 22, 37.5 as 37 or 38), so round.
      int? total = totals[id];
      final hours = num.tryParse('${c['hours']}');
      if (total == null && hours != null && hours > 0 && minutes > 0) {
        total = (hours * 60 / minutes).round();
        if (total < held + upcoming.length) total = null;
      }

      final fullName = '${c['course_name']}'.trim();
      final half = _half.firstMatch(fullName);
      final base = half == null ? fullName : half.group(1)!.trim();
      final label = half == null
          ? ''
          : half.group(2)!.toLowerCase() == 'lab'
              ? 'Lab'
              : 'Theory';
      (groups[base] ??= []).add(Course(
        id: id,
        name: fullName,
        label: label,
        faculty: '${c['faculty_names'] ?? ''}'.trim(),
        held: held,
        attended: _int(counts['attended']),
        pending: _int(counts['not_marked']),
        total: total,
        weekly: weekly,
        upcoming: upcoming,
        absences: absences,
        horizon: horizon,
        ends: ends,
      ));
    }
  }

  // "X Theory" and "X Lab" are one course on the curriculum: show them as one.
  final courses = <Course>[
    for (final e in groups.entries)
      if (e.value.length > 1 && e.value.every((c) => c.label.isNotEmpty))
        combine(e.key, e.value..sort((a, b) => b.label.compareTo(a.label)))
      else
        ...e.value
  ];

  return Snapshot(
    studentName: '${student['name'] ?? ''}',
    roll: '${student['roll_number'] ?? ''}',
    courses: courses,
    syncedAt: now,
    sessions: next
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.start.compareTo(b.start);
      }),
  );
}

/// Times before a deadline a reminder can be set for, in hours. The first
/// (two days) is always on.
const dueChoices = [48, 24, 12, 6, 3, 1];

class Store {
  Store(this.prefs);
  final SharedPreferences prefs;

  int get minPct => prefs.getInt('minPct') ?? 85;
  set minPct(int v) => prefs.setInt('minPct', v);

  // Settings.
  bool get remindClasses => prefs.getBool('n_class') ?? true;
  set remindClasses(bool v) => prefs.setBool('n_class', v);
  int get leadMinutes => prefs.getInt('n_lead') ?? 5;
  set leadMinutes(int v) => prefs.setInt('n_lead', v);
  bool get notifyMoodle => prefs.getBool('n_moodle') ?? true;
  set notifyMoodle(bool v) => prefs.setBool('n_moodle', v);
  bool get warnAttendance => prefs.getBool('n_att') ?? true;
  set warnAttendance(bool v) => prefs.setBool('n_att', v);
  bool get autoDownload => prefs.getBool('auto_dl') ?? false;
  set autoDownload(bool v) => prefs.setBool('auto_dl', v);
  bool get warnChanges => prefs.getBool('n_change') ?? true;
  set warnChanges(bool v) => prefs.setBool('n_change', v);

  /// Reasons the student has noted against absences, by class id.
  Map<int, Leave> get leaves => parseLeaves(prefs.getString('leave_log'));
  void setLeave(int id, Leave? l) {
    final m = leaves;
    l == null ? m.remove(id) : m[id] = l;
    prefs.setString('leave_log', encodeLeaves(m));
  }

  /// Classes that dropped off the attendance site, kept to show as cancelled.
  List<ClassSlot> get gone {
    try {
      return [
        for (final j
            in jsonDecode(prefs.getString('gone_classes') ?? '[]') as List)
          _slotOf(j as Map)
      ];
    } catch (_) {
      return [];
    }
  }

  /// Notes the classes that dropped off between the last reading and
  /// [fresh]; forgets those that came back and those long past.
  Future<void> _noteGone(String? oldRaw, Snapshot fresh, DateTime now) async {
    var list = gone;
    if (oldRaw != null) {
      try {
        final old = parseSummary(oldRaw, now, totals);
        list = [...list, ...vanishedClasses(old, fresh, now)];
      } catch (_) {}
    }
    final back = {for (final s in fresh.sessions) s.slotKey};
    final floor = now.subtract(const Duration(days: 60));
    final seen = <String>{};
    final keep = [
      for (final g in list)
        if (!back.contains(g.slotKey) &&
            g.date.isAfter(floor) &&
            seen.add('${g.slotKey} ${g.courseId}'))
          g
    ];
    await prefs.setString(
        'gone_classes', jsonEncode([for (final g in keep) _slotJson(g)]));
  }

  /// Classes the admin has cancelled, as last fetched.
  List<Cancelled> get cancelled =>
      Cancelled.decode(prefs.getString('cancelled'));

  /// Classes from the timetable sheets added so far.
  List<SheetClass> get sheetClasses => decodeSheet(prefs.getString('tt_sheet'));

  /// Adds a timetable sheet (.xlsx). Returns the classes found in it.
  /// Throws when the file is not a timetable.
  Future<List<SheetClass>> importSheet(List<int> bytes) async {
    final fresh = parseTimetable(readXlsx(Uint8List.fromList(bytes)));
    if (fresh.isEmpty) {
      throw const FormatException('No classes found in this sheet');
    }
    await prefs.setString('tt_sheet',
        encodeSheet(mergeSheets(sheetClasses, fresh, DateTime.now())));
    await prefs.setString('tt_at', DateTime.now().toIso8601String());
    return fresh;
  }

  /// Hours before a deadline at which to remind. Always includes 48.
  List<int> get dueHours {
    final saved = prefs.getStringList('due_hours');
    final chosen =
        saved == null ? [24, 3] : [for (final x in saved) int.tryParse(x) ?? 0];
    return [
      for (final h in dueChoices)
        if (h == dueChoices.first || chosen.contains(h)) h
    ];
  }

  set dueHours(List<int> v) =>
      prefs.setStringList('due_hours', [for (final h in v) '$h']);

  /// The batch's academic calendar from the server (may be empty).
  List<TermEvent> get calendar {
    final events = decodeCalendar(prefs.getString('acal'));
    plannerDaysOff = offDays(events);
    return events;
  }

  /// Exams and quizzes the student has added, soonest first.
  List<Exam> get exams => decodeExams(prefs.getString('exams'));
  set exams(List<Exam> v) => prefs.setString('exams', encodeExams(v));

  /// Papers of these courses in the batch's published exam timetable.
  List<Exam> publishedExamsFor(List<Course> courses) =>
      publishedExams(prefs.getString('exams_pub'), courses);

  /// Own exams and published papers together, soonest first.
  List<Exam> allExams(List<Course> courses) => [
        ...exams,
        ...publishedExamsFor(courses)
      ]..sort((a, b) => a.at.compareTo(b.at));

  /// The mess menu from the server, day by day.
  List<MenuDay> get menu => decodeMenu(prefs.getString('menu'));

  /// Dishes the student wants to hear about ("Paneer", "Ice Cream").
  List<String> get favDishes => prefs.getStringList('fav_dishes') ?? const [];
  set favDishes(List<String> v) => prefs.setStringList('fav_dishes', v);
  bool get dishAlerts => prefs.getBool('n_dish') ?? true;
  set dishAlerts(bool v) => prefs.setBool('n_dish', v);

  /// Short names the student has given courses ("DSA"), by full course name.
  Map<String, String> get shortNames {
    try {
      return (jsonDecode(prefs.getString('short_names') ?? '{}') as Map)
          .map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  void setShortName(String course, String short) {
    final m = shortNames;
    short.trim().isEmpty ? m.remove(course) : m[course] = short.trim();
    prefs.setString('short_names', jsonEncode(m));
  }

  /// The name to use for a class where space is tight (reminders, widget):
  /// the short name of its course when one is set, else the full name.
  String shortFor(Snapshot snap, ClassSlot s) {
    final names = shortNames;
    return names[snap.courseOf(s)?.name] ?? names[s.course] ?? s.course;
  }

  bool get calendarSync => prefs.getBool('cal_sync') ?? false;
  set calendarSync(bool v) => prefs.setBool('cal_sync', v);

  /// Where attendance correction emails go (may be empty).
  String get fixEmail => prefs.getString('fix_email') ?? '';
  set fixEmail(String v) => prefs.setString('fix_email', v.trim());

  Map<String, int> get totals {
    final raw = prefs.getString('totals');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', v as int));
  }

  void setTotal(String courseId, int? total) {
    final t = totals;
    if (total == null) {
      t.remove(courseId);
    } else {
      t[courseId] = total;
    }
    prefs.setString('totals', jsonEncode(t));
  }

  Snapshot? get cached {
    final raw = prefs.getString('summary');
    final at = DateTime.tryParse(prefs.getString('syncedAt') ?? '');
    if (raw == null || at == null) return null;
    try {
      calendar; // tells the planner which days are off
      final snap = parseSummary(raw, at, totals)
          .withGone(gone)
          .withSheet(sheetClasses, DateTime.now())
          .withCancelled(cancelled);
      setPlannerShares(snap.courses);
      return snap;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await prefs.remove('summary');
    await prefs.remove('syncedAt');
  }

  /// Fetches fresh data from the site (through [fetch]) and saves it.
  Future<Snapshot> sync(Future<String> Function(String path) fetch) async {
    final body = await fetch('api/student-dashboard.php?action=summary');
    final now = DateTime.now();
    final snap = parseSummary(body, now, totals);
    await _noteGone(prefs.getString('summary'), snap, now);
    await prefs.setString('summary', body);
    await prefs.setString('syncedAt', now.toIso8601String());
    calendar; // tells the planner which days are off
    final full = snap
        .withGone(gone)
        .withSheet(sheetClasses, now)
        .withCancelled(cancelled);
    setPlannerShares(full.courses);
    return full;
  }
}
