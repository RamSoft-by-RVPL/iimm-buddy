// Tells the student when a class in the coming week moves, is cancelled,
// changes room or is added. After every refresh the app compares the coming
// classes with the ones it saw last time.

import 'dart:convert';

import 'site.dart';

class Seen {
  Seen(this.date, this.start, this.end, this.course, this.room, this.sheet);
  final DateTime date;
  final String start;
  final String end;
  final String course;
  final String room;

  /// Known only from the mailed sheet: its room is a guess.
  final bool sheet;

  DateTime get at {
    final p = start.split(':');
    return DateTime(date.year, date.month, date.day, int.tryParse(p.first) ?? 0,
        p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  String get key => '${date.year}-${date.month}-${date.day} $start $course';

  Map<String, dynamic> toJson() => {
        'd': date.toIso8601String().substring(0, 10),
        's': start,
        'e': end,
        'c': course,
        'r': room,
        if (sheet) 'x': 1,
      };

  static Seen fromJson(Map j) => Seen(DateTime.parse('${j['d']}'), '${j['s']}',
      '${j['e']}', '${j['c']}', '${j['r']}', j['x'] == 1);

  static Seen of(ClassSlot s) =>
      Seen(s.date, s.start, s.end, s.course, s.room, s.fromSheet);
}

/// How far ahead changes are announced.
const changeDays = 7;

/// The classes of the coming week, as saved between refreshes.
List<Seen> comingClasses(List<ClassSlot> next, DateTime now) {
  final until = DateTime(now.year, now.month, now.day + changeDays + 1);
  return [
    for (final s in next)
      if (s.startsAt.isAfter(now) && s.startsAt.isBefore(until)) Seen.of(s)
  ];
}

String encodeSeen(List<Seen> l) => jsonEncode([for (final s in l) s.toJson()]);

List<Seen>? decodeSeen(String? raw) {
  if (raw == null) return null;
  try {
    return [for (final j in jsonDecode(raw) as List) Seen.fromJson(j as Map)];
  } catch (_) {
    return null;
  }
}

class ClassChange {
  ClassChange(this.key, this.title, this.body);

  /// The same change gets the same key, so it is listed once.
  final String key;
  final String title;
  final String body;
}

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
String _when(Seen s) =>
    '${_days[s.date.weekday - 1]} ${s.date.day} ${_months[s.date.month - 1]}, '
    '${s.start}';
String _room(String r) =>
    r.isEmpty ? '' : (RegExp(r'^\d').hasMatch(r) ? 'Room $r' : r);

/// What changed between [before] and [after], for classes still to come
/// that both lists cover. More than [most] changes at once (a new term, a
/// new week's sheet with many changes) come back as one summary.
List<ClassChange> classChanges(
    List<Seen> before, List<Seen> after, DateTime now,
    {int most = 6}) {
  // Nothing to compare with, or a failed reading: say nothing.
  if (before.isEmpty || after.isEmpty) return [];
  // Only days the old list already covered: a later day is news, not a change.
  final last = before.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
  bool inWindow(Seen s) => s.at.isAfter(now) && !s.date.isAfter(last);
  final was = [
    for (final s in before)
      if (inWindow(s)) s
  ];
  final fresh = [
    for (final s in after)
      if (inWindow(s)) s
  ];

  final out = <ClassChange>[];
  final afterByKey = {for (final s in fresh) s.key: s};
  // A slot taken in both lists, by a sheet class on either side: the portal
  // putting up a class the sheet already had (often under another name), not
  // a cancellation plus an extra class.
  String slot(Seen s) =>
      '${s.date.year}-${s.date.month}-${s.date.day} ${s.start}';
  final freshSlots = {for (final s in fresh) slot(s): s};
  final gone = <Seen>[];
  for (final s in was) {
    final same = afterByKey.remove(s.key);
    if (same == null) {
      final there = freshSlots[slot(s)];
      if (there != null && (s.sheet || there.sheet)) {
        afterByKey.remove(there.key);
        continue;
      }
      gone.add(s);
    } else if (same.room != s.room &&
        same.room.isNotEmpty &&
        !s.sheet &&
        !same.sheet) {
      out.add(ClassChange(
          'room:${s.key}:${same.room}',
          'Room changed: ${s.course}',
          '${_when(s)}. Now in ${_room(same.room)}, not ${_room(s.room)}.'));
    }
  }
  final added = afterByKey.values.toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  gone.sort((a, b) => a.at.compareTo(b.at));
  for (final g in gone) {
    if (g.sheet && !added.any((a) => a.course == g.course)) {
      // Only on the mailed sheet: the portal never had it, so it is not
      // "cancelled" (only a class the portal listed and dropped is).
      continue;
    }
    // The nearest new class of the same course is where it moved to.
    Seen? to;
    for (final a in added) {
      if (a.course != g.course) continue;
      if (to == null ||
          a.at.difference(g.at).abs() < to.at.difference(g.at).abs()) {
        to = a;
      }
    }
    if (to != null) {
      added.remove(to);
      final room =
          to.room.isNotEmpty && !to.sheet ? ' · ${_room(to.room)}' : '';
      out.add(ClassChange('moved:${g.key}:${to.key}',
          'Class moved: ${g.course}', '${_when(g)} is now ${_when(to)}$room.'));
    } else {
      out.add(ClassChange('cancelled:${g.key}', 'Class cancelled: ${g.course}',
          '${_when(g)} is off the timetable.'));
    }
  }
  for (final a in added) {
    final room = a.room.isNotEmpty && !a.sheet ? ' · ${_room(a.room)}' : '';
    out.add(ClassChange(
        'added:${a.key}', 'Extra class: ${a.course}', '${_when(a)}$room.'));
  }
  if (out.length > most) {
    return [
      ClassChange(
          'many:${now.millisecondsSinceEpoch ~/ 60000}',
          'Timetable changed',
          '${out.length} classes in the coming week moved, were added or '
              'were cancelled. Open the timetable to see them.')
    ];
  }
  return out;
}
