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
      {this.fromSheet = false});
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

  bool get unmarked => !upcoming && !fromSheet && status == 'Not Marked';
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
          if (s.upcoming) s
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
    final all = [...sessions, ...extra]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.start.compareTo(b.start);
      });
    // The holiday planner must count these classes too, and the sheet tells
    // us the timetable up to its last day.
    final lastDay =
        sheet.map((c) => c.date).reduce((a, b) => a.isAfter(b) ? a : b);
    List<DateTime> of(String id) => [
          for (final s in extra)
            if (s.upcoming && s.courseId == id) s.date
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

  int get held => courses.fold(0, (a, c) => a + c.held);
  int get attended => courses.fold(0, (a, c) => a + c.attended);
  double get percent => held == 0 ? 100 : attended * 100 / held;
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
            s['is_upcoming'] == true);
        // A class later today counts as coming up even if the site has
        // stopped calling it upcoming: it still needs its reminder.
        next.add(!slot.upcoming &&
                slot.status == 'Not Marked' &&
                slot.startsAt.isAfter(now)
            ? ClassSlot(slot.id, slot.date, slot.start, slot.end, slot.room,
                slot.course, slot.courseId, slot.status, true)
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
      final snap =
          parseSummary(raw, at, totals).withSheet(sheetClasses, DateTime.now());
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
    await prefs.setString('summary', body);
    await prefs.setString('syncedAt', now.toIso8601String());
    calendar; // tells the planner which days are off
    final full = snap.withSheet(sheetClasses, now);
    setPlannerShares(full.courses);
    return full;
  }
}
