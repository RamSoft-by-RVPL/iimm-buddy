// Work done after every refresh and by the periodic background check:
// reminders, alerts, the home screen widget and automatic downloads.

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'acal.dart';
import 'backend.dart';
import 'changes.dart';
import 'exams.dart';
import 'log.dart';
import 'menu.dart';
import 'moodle.dart';
import 'net.dart';
import 'notify.dart';
import 'planner.dart';
import 'my_reminders.dart';
import 'week_summary.dart';
import 'sheet.dart';
import 'site.dart';
import 'update.dart';

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
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String shortDate(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _checkTask = 'check';
const _wifiTask = 'wifi';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await runChecks(prefs, onWifi: task == _wifiTask);
    } catch (_) {}
    return true;
  });
}

/// Starts the periodic background checks (safe to call on every launch).
Future<void> registerBackground() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _checkTask,
    _checkTask,
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(minutes: 5),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
  // Runs only on Wi-Fi (an unmetered network): used for automatic downloads.
  await Workmanager().registerPeriodicTask(
    _wifiTask,
    _wifiTask,
    frequency: const Duration(hours: 2),
    initialDelay: const Duration(minutes: 20),
    constraints: Constraints(networkType: NetworkType.unmetered),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Runs one background check right away (same path as the periodic one).
Future<void> runBackgroundNow({Duration delay = Duration.zero}) =>
    Workmanager().registerOneOffTask(
        'now-${DateTime.now().millisecondsSinceEpoch}', _checkTask,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected));

/// One background pass: attendance, then Moodle. Each part fails quietly.
Future<void> runChecks(SharedPreferences prefs, {bool onWifi = false}) async {
  final store = Store(prefs);
  await prefs.setString('bg_last', DateTime.now().toIso8601String());
  logEvent(prefs, 'bg_check', onWifi ? 'on wifi' : '');
  try {
    final old = store.cached;
    var snap = await store.sync((p) => siteApi(p));
    snap = await withSharedTimetable(store, snap, alert: true);
    await afterSync(store, old, snap, alert: true);
    logEvent(prefs, 'bg_sync_ok', '${snap.next.length} classes ahead');
  } on NotSignedIn {
    logEvent(prefs, 'bg_need_login', 'attendance');
  } catch (e) {
    logEvent(prefs, 'bg_sync_fail', errorLine(e));
  }
  try {
    await checkMoodle(store, Moodle(prefs),
        alert: true, download: onWifi && store.autoDownload);
    logEvent(prefs, 'bg_moodle_ok');
  } on NotSignedIn {
    logEvent(prefs, 'bg_need_login', 'moodle');
  } catch (e) {
    logEvent(prefs, 'bg_moodle_fail', errorLine(e));
  }
  // Say once when a newer version of the app is out.
  final u = await checkUpdate(prefs);
  if (u != null && prefs.getInt('upd_told') != u.build) {
    await prefs.setInt('upd_told', u.build);
    await notify(5, 'Crony ${u.version} is ready',
        u.notes.isEmpty ? 'Open the app and press Update.' : u.notes, 'news',
        key: 'update:${u.build}');
  }
  await flushLogs(prefs);
}

/// Fetches the batch timetable from the server. When there is a newer one it
/// is merged into the schedule (and announced when [alert] is set).
Future<Snapshot> withSharedTimetable(Store store, Snapshot snap,
    {required bool alert}) async {
  // Messages sent from the admin page: shown as notifications.
  try {
    for (final n in await pullNotices(store.prefs)) {
      await notify(900000 + n.id % 90000, n.title, n.body, 'news',
          key: 'notice:${n.id}');
      logEvent(store.prefs, 'notice_got', '#${n.id}');
    }
  } catch (_) {
    // No connection: they come with the next check.
  }
  // Whether the admin made this phone a CR or a secretary.
  try {
    await pullRole(store.prefs);
  } catch (_) {}
  // The academic calendar (exams, holidays, breaks).
  var calendarChanged = false;
  try {
    calendarChanged = await pullCalendar(store.prefs);
    if (calendarChanged) {
      final n = store.calendar.length;
      logEvent(store.prefs, 'calendar_new', '$n events');
      if (alert && n > 0) {
        await notify(
            6,
            'Academic calendar updated',
            '$n dates (exams, holidays and breaks) are in your timetable.',
            'classes',
            open: 'timetable');
      }
    }
  } catch (_) {
    // No connection: it comes with the next check.
  }
  // The mess menu (shown on the home screen, no notification).
  try {
    await pullMenu(store.prefs);
  } catch (_) {}
  // The exam timetable: said once when the student's papers are in it.
  try {
    if (await pullExams(store.prefs)) {
      final mine = store.publishedExamsFor(snap.courses);
      logEvent(store.prefs, 'exams_new', '${mine.length} papers');
      final coming = mine.where((e) => e.at.isAfter(DateTime.now())).toList();
      if (alert && coming.isNotEmpty) {
        await notify(
            7,
            'Exam timetable is out',
            '${coming.length} ${coming.length == 1 ? 'paper' : 'papers'} of '
                'your courses, from ${shortDate(coming.first.at)}. Reminders '
                'are set.',
            'classes',
            open: 'home');
      }
    }
  } catch (_) {}
  // Classes the admin called off: the change check says "Class cancelled".
  var cancelledChanged = false;
  try {
    if (await pullCancelled(store.prefs)) {
      cancelledChanged = true;
      logEvent(store.prefs, 'cancelled_new', '${store.cancelled.length}');
    }
  } catch (_) {}
  // Classes the CR added or moved: shown and announced like any change.
  try {
    if (await pullExtra(store.prefs)) {
      cancelledChanged = true;
      logEvent(store.prefs, 'extra_new', '${store.extraClasses.length}');
    }
  } catch (_) {}
  // Teachers' email addresses.
  try {
    await pullFaculty(store.prefs);
  } catch (_) {}
  // Polls, so the home screen can show them without waiting.
  try {
    await pullPolls(store.prefs);
  } catch (_) {}
  List<SheetClass>? fresh;
  try {
    fresh = await pullTimetable(store.prefs);
  } catch (e) {
    // No connection: keep what the phone has.
    logEvent(store.prefs, 'timetable_fail', errorLine(e));
  }
  if (fresh == null) {
    // Days off or cancelled classes changed: hand back a fresh reading.
    return calendarChanged || cancelledChanged ? (store.cached ?? snap) : snap;
  }
  logEvent(store.prefs, 'timetable_new', '${fresh.length} classes');
  if (alert) {
    final first =
        fresh.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
    await notify(
        4,
        'Timetable updated',
        '${fresh.length} classes from ${shortDate(first)} are in your '
            'schedule, with reminders.',
        'classes',
        open: 'timetable');
  }
  return store.cached ?? snap;
}

/// Class reminders for the published timetable.
List<Reminder> classReminders(List<ClassSlot> next, int lead,
        {String Function(ClassSlot)? name}) =>
    [
      for (final s in next)
        Reminder(
          100000 + s.id % 800000,
          s.startsAt.subtract(Duration(minutes: lead)),
          'Class in $lead ${lead == 1 ? 'min' : 'mins'}',
          '${name?.call(s) ?? s.course}'
              '${s.room.isEmpty ? '' : ' · Room ${s.room}'}'
              ' · ${s.start} to ${s.end}',
          open: 'timetable',
        )
    ];

/// What changed for the worse between two refreshes: (title, body) pairs.
List<(String, String)> attendanceAlerts(
    Snapshot old, Snapshot snap, int minPct) {
  final out = <(String, String)>[];
  final before = {for (final s in old.sessions) s.id: s.status};
  for (final s in snap.sessions) {
    if (s.status == 'Absent' &&
        before.containsKey(s.id) &&
        before[s.id] != 'Absent') {
      final c = snap.courseOf(s);
      out.add((
        'Marked absent: ${c?.name ?? s.course}',
        '${shortDate(s.date)}, ${s.start}. '
            '${c == null ? '' : statusText(c, minPct)}'
      ));
    }
  }
  final was = {for (final c in old.courses) c.id: c};
  for (final c in snap.courses) {
    final o = was[c.id];
    if (o != null &&
        meets(o.attended, o.held, minPct) &&
        !meets(c.attended, c.held, minPct)) {
      out.add((
        '${c.name} is below $minPct%',
        '${c.percent.toStringAsFixed(1)}% now. ${statusText(c, minPct)}'
      ));
    }
  }
  return out;
}

/// What the home screen widget shows.
class WidgetData {
  WidgetData(this.percent, this.state, this.course, this.when, this.startsAt);

  /// "91.3%".
  final String percent;

  /// "All courses fine" or "2 below 85%".
  final String state;

  /// The next class ("DSA"), or a line saying there is none.
  final String course;

  /// "Tue 09:00 · Room 404".
  final String when;

  /// Start of the next class in milliseconds, 0 when there is none.
  final int startsAt;
}

WidgetData widgetData(Snapshot snap, int minPct, DateTime now,
    {String Function(ClassSlot)? name}) {
  final next = snap.next.where((s) => s.startsAt.isAfter(now)).toList();
  final n = next.isEmpty ? null : next.first;
  final below = snap.courses
      .where((c) => c.held > 0 && !meets(c.attended, c.held, minPct))
      .length;
  return WidgetData(
    '${snap.percent.toStringAsFixed(1)}%',
    below == 0 ? 'All courses above $minPct%' : '$below below $minPct%',
    n == null ? 'No class scheduled' : (name?.call(n) ?? n.course),
    n == null
        ? ''
        : '${shortDate(n.date)} ${n.start}'
            '${n.room.isEmpty ? '' : ' · Room ${n.room}'}',
    n == null ? 0 : n.startsAt.millisecondsSinceEpoch,
  );
}

/// Run after every attendance refresh, in the app or in the background.
Future<void> afterSync(Store store, Snapshot? old, Snapshot snap,
    {required bool alert}) async {
  final prefs = store.prefs;
  try {
    await scheduleReminders(
        prefs,
        'rem_class',
        'classes',
        store.remindClasses
            ? classReminders(snap.next, store.leadMinutes,
                name: (x) => store.shortFor(snap, x))
            : const []);
    final set =
        '${store.remindClasses ? snap.next.length : 0} class reminders, '
        '${snap.next.where((x) => x.fromSheet).length} from the sheet';
    if (prefs.getString('log_rem') != set) {
      await prefs.setString('log_rem', set);
      logEvent(prefs, 'reminders_set', set);
    }
  } catch (_) {}
  try {
    final w = widgetData(snap, store.minPct, DateTime.now(),
        name: (x) => store.shortFor(snap, x));
    await prefs.setString('w_pct', w.percent);
    await prefs.setString('w_state', w.state);
    await prefs.setString('w_course', w.course);
    await prefs.setString('w_when', w.when);
    // Text, because the widget reads it natively and Flutter stores numbers
    // in a form that differs between versions.
    await prefs.setString('w_at', '${w.startsAt}');
    await refreshWidget();
  } catch (_) {}
  try {
    await scheduleReminders(
        prefs, 'rem_exam', 'classes', examReminders(store.exams));
    await scheduleReminders(prefs, 'rem_pexam', 'classes',
        publishedExamReminders(store.publishedExamsFor(snap.courses)));
  } catch (_) {}
  try {
    await announceClassChanges(store, snap);
  } catch (_) {}
  try {
    await scheduleMyReminders(store); // keeps repeating ones rolling
  } catch (_) {}
  try {
    await scheduleWeekSummary(store, snap,
        deadlines: Moodle(prefs).cachedDeadlines ?? const []);
  } catch (_) {}
  try {
    await scheduleDishAlerts(store);
  } catch (_) {}
  try {
    await scheduleReminders(
        prefs, 'rem_acal', 'classes', calendarReminders(store.calendar));
  } catch (_) {}
  try {
    await syncCalendar(store, snap: snap);
  } catch (_) {}
  if (alert && old != null && store.warnAttendance) {
    var id = 300000;
    for (final (title, body) in attendanceAlerts(old, snap, store.minPct)) {
      await notify(id++, title, body, 'attendance');
    }
  }
}

/// Reminders before meals that have one of the student's favourite dishes.
Future<void> scheduleDishAlerts(Store store) => scheduleReminders(
    store.prefs,
    'rem_dish',
    'news',
    store.dishAlerts ? dishReminders(store.menu, store.favDishes) : const []);

/// Compares the coming week's classes with the last refresh and says what
/// moved, was cancelled, changed room or was added.
Future<void> announceClassChanges(Store store, Snapshot snap) async {
  final prefs = store.prefs;
  final now = DateTime.now();
  final coming = comingClasses(snap.next, now);
  final before = decodeSeen(prefs.getString('seen_classes'));
  await prefs.setString('seen_classes', encodeSeen(coming));
  // A new app version may read the same timetable differently (a fix can
  // bring back classes the old one hid): the first look after an update
  // only notes the classes, it does not announce changes.
  final updated = prefs.getInt('seen_build') != appBuild;
  await prefs.setInt('seen_build', appBuild);
  if (before == null || updated || !store.warnChanges) return;
  var id = 310000;
  for (final c in classChanges(before, coming, now)) {
    await notify(id++, c.title, c.body, 'classes',
        open: 'timetable', key: 'change:${c.key}');
    logEvent(prefs, 'class_change', c.title);
  }
}

/// Calendar entries for coming classes and open deadlines.
List<CalEvent> calendarEvents(
        List<ClassSlot> classes, List<Deadline> deadlines, DateTime now) =>
    [
      for (final s in classes)
        if (!s.cancelled && (s.upcoming || s.startsAt.isAfter(now)))
          CalEvent(
              s.course,
              s.startsAt,
              DateTime(
                  s.date.year,
                  s.date.month,
                  s.date.day,
                  int.tryParse(s.end.split(':').first) ?? 0,
                  int.tryParse(s.end.split(':').last) ?? 0),
              s.room.isEmpty ? '' : 'Room ${s.room}',
              ''),
      for (final d in deadlines)
        if (d.due.isAfter(now))
          CalEvent('Due: ${d.name}',
              d.due.subtract(const Duration(minutes: 30)), d.due, '', d.course),
    ];

/// Writes classes and deadlines into the phone calendar when that is on.
/// Either list may be left out: the saved one is used.
Future<void> syncCalendar(Store store,
    {Snapshot? snap, List<Deadline>? deadlines}) async {
  if (!store.calendarSync) return;
  final s = snap ?? store.cached;
  if (s == null) return;
  final d = deadlines ?? Moodle(store.prefs).cachedDeadlines ?? const [];
  final now = DateTime.now();
  await writeCalendar([
    for (final e in [
      ...calendarEvents(s.sessions, d, now),
      for (final x in store.exams)
        if (x.at.isAfter(now))
          CalEvent('${x.kind}: ${x.title}', x.at,
              x.at.add(const Duration(hours: 2)), '', x.course),
      for (final x in store.calendar)
        if (!x.to.isBefore(DateTime(now.year, now.month, now.day)))
          CalEvent(x.title, x.from,
              DateTime(x.to.year, x.to.month, x.to.day, 23, 59), '', x.label),
    ])
      [
        e.title,
        e.start.millisecondsSinceEpoch,
        e.end.millisecondsSinceEpoch,
        e.place,
        e.note
      ]
  ]);
}

class CalEvent {
  CalEvent(this.title, this.start, this.end, this.place, this.note);
  final String title;
  final DateTime start;
  final DateTime end;
  final String place;
  final String note;
}

/// "in 2 days", "tomorrow", "in 3 hours".
String dueIn(int hours) => hours == 24
    ? 'tomorrow'
    : hours % 24 == 0
        ? 'in ${hours ~/ 24} days'
        : 'in $hours ${hours == 1 ? 'hour' : 'hours'}';

/// Reminders for open assignments, one for each chosen time before the
/// deadline ([hours] before it, for example 48, 24 and 3).
List<Reminder> deadlineReminders(List<Deadline> list, List<int> hours) => [
      for (final d in list)
        for (final h in hours)
          Reminder(
              500000 + (d.id % 20000) * 8 + dueChoices.indexOf(h).clamp(0, 7),
              d.due.subtract(Duration(hours: h)),
              'Due ${dueIn(h)}: ${d.name}',
              '${d.course}. Due ${shortDate(d.due)}, ${clock(d.due)}.',
              open: 'moodle'),
    ];

/// New items of a course compared with what the user was last told about.
List<MoodleItem> newItems(Set<int>? told, List<MoodleSection> sections) => [
      if (told != null)
        for (final s in sections)
          for (final i in s.items)
            if (!told.contains(i.id)) i
    ];

String listNames(List<String> names) => names.length <= 3
    ? names.join(', ')
    : '${names.take(3).join(', ')} and ${names.length - 3} more';

/// Looks for new Moodle items and deadlines; keeps the Moodle session alive.
Future<void> checkMoodle(Store store, Moodle m,
    {required bool alert, bool download = false}) async {
  final prefs = store.prefs;
  await m.touch();
  final courses = await m.courses();
  final work = <MoodleItem>[];
  for (final c in courses) {
    try {
      final told = m.notified(c.id);
      final secs = await m.sections(c.id);
      final fresh = newItems(told, secs);
      work.addAll([
        for (final s in secs)
          for (final i in s.items)
            if (i.module == 'assign') i
      ]);
      if (alert && store.notifyMoodle && fresh.isNotEmpty) {
        await notify(200000 + c.id % 90000, 'New on Moodle: ${c.name}',
            listNames([for (final i in fresh) i.name]), 'moodle',
            open: 'course:${c.id}');
      }
      await m.markNotified(c.id, secs);
      if (fresh.isNotEmpty) {
        logEvent(prefs, 'moodle_new', '${fresh.length} in ${c.name}');
      }
      if (download) await m.downloadAll(c.id, secs, (_, __) {});
    } on NotSignedIn {
      rethrow;
    } catch (_) {}
  }

  // Submission status of every assignment.
  try {
    await m.refreshAssigns(work);
  } on NotSignedIn {
    rethrow;
  } catch (_) {}

  final known = prefs.getStringList('m_dl_ids')?.toSet();
  final done = m.assigns;
  // Moodle drops submitted work from this list; the status check is a second
  // guard so reminders stop as soon as the app knows it is submitted.
  final list = [
    for (final d in await m.deadlines())
      if (!(done[linkId(d.url)]?.submitted ?? false)) d
  ];
  await prefs.setStringList('m_dl_ids', [for (final d in list) '${d.id}']);
  if (alert && store.notifyMoodle && known != null) {
    for (final d in list.where((d) => !known.contains('${d.id}'))) {
      await notify(400000 + d.id % 90000, 'New deadline: ${d.name}',
          '${d.course}. Due ${shortDate(d.due)}, ${clock(d.due)}.', 'moodle',
          open: 'moodle');
    }
  }
  try {
    await syncCalendar(store, deadlines: list);
  } catch (_) {}
  await scheduleReminders(prefs, 'rem_due', 'moodle',
      store.notifyMoodle ? deadlineReminders(list, store.dueHours) : const []);
}
