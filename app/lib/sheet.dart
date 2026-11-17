// Reads the weekly timetable the programme office mails as an Excel sheet.
//
// The attendance site lists some classes only after they are over (the HPE
// ones), so the sheet is the fuller timetable. The sheet is a grid: one row
// per day, one column per time slot, each cell "Course" then the teacher.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'planner.dart';
import 'site.dart';

class SheetClass {
  SheetClass(this.date, this.start, this.end, this.course, this.faculty);
  final DateTime date;
  final String start; // "14:00"
  final String end;
  final String course;
  final String faculty;

  Map<String, dynamic> toJson() => {
        'd': '${date.year}-${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        's': start,
        'e': end,
        'c': course,
        'f': faculty,
      };

  static SheetClass fromJson(Map<String, dynamic> j) => SheetClass(
      DateTime.parse('${j['d']}'),
      '${j['s']}',
      '${j['e']}',
      '${j['c']}',
      '${j['f'] ?? ''}');
}

String encodeSheet(List<SheetClass> l) =>
    jsonEncode([for (final c in l) c.toJson()]);

List<SheetClass> decodeSheet(String? raw) {
  try {
    return [
      for (final j in jsonDecode(raw ?? '[]') as List)
        SheetClass.fromJson((j as Map).cast<String, dynamic>())
    ];
  } catch (_) {
    return [];
  }
}

String _text(String xml) => xml
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('_x000D_', '');

int _column(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// The first sheet of an .xlsx file as rows of (column number: text).
List<Map<int, String>> readXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? file(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  final shared = <String>[
    for (final m in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true)
        .allMatches(file('xl/sharedStrings.xml') ?? ''))
      _text(RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(m.group(1)!)
          .map((t) => t.group(1)!)
          .join())
  ];
  final names = [
    for (final f in zip.files)
      if (f.name.startsWith('xl/worksheets/sheet')) f.name
  ]..sort();
  if (names.isEmpty) throw const FormatException('No sheet in this file');
  final rows = <Map<int, String>>[];
  for (final r in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true)
      .allMatches(file(names.first)!)) {
    final row = <int, String>{};
    for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
        .allMatches(r.group(1)!)) {
      final attrs = c.group(1)!;
      final body = c.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
      if (ref == null) continue;
      final type = RegExp(r'\bt="(\w+)"').firstMatch(attrs)?.group(1);
      final v =
          RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
      String value;
      if (type == 's') {
        final i = int.tryParse(v ?? '');
        value = i != null && i < shared.length ? shared[i] : '';
      } else if (type == 'inlineStr') {
        value = _text(RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
            .allMatches(body)
            .map((t) => t.group(1)!)
            .join());
      } else {
        value = _text(v ?? '');
      }
      if (value.trim().isNotEmpty) row[_column(ref)] = value.trim();
    }
    if (row.isNotEmpty) rows.add(row);
  }
  return rows;
}

final _slot = RegExp(
    r'^\s*(\d{1,2})[:.](\d{2})\s*(?:to|-|–|—)\s*(\d{1,2})[:.](\d{2})\s*$',
    caseSensitive: false);
const _monthNames = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec'
];

DateTime? _date(String s) {
  final n = double.tryParse(s);
  if (n != null) {
    // Excel counts days from 30 Dec 1899.
    if (n < 30000 || n > 80000) return null;
    return DateTime(1899, 12, 30 + n.floor());
  }
  var m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})').firstMatch(s);
  if (m != null) {
    return DateTime(
        int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{4})').firstMatch(s);
  if (m != null) {
    final month = _monthNames.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month > 0) {
      return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(1)!));
    }
  }
  return null;
}

final _notClass =
    RegExp(r'^(lunch|break|tea|holiday|no class|-+)\b', caseSensitive: false);

/// Classes in a timetable grid. Throws when the sheet is not a timetable.
List<SheetClass> parseTimetable(List<Map<int, String>> rows) {
  String hm(String h, String m) => '${h.padLeft(2, '0')}:$m';
  Map<int, (String, String)>? slots;
  final out = <SheetClass>[];
  for (final row in rows) {
    final found = <int, (String, String)>{
      for (final e in row.entries)
        if (_slot.firstMatch(e.value) case final m?)
          e.key: (hm(m.group(1)!, m.group(2)!), hm(m.group(3)!, m.group(4)!))
    };
    if (found.length >= 2) {
      slots = found;
      continue;
    }
    if (slots == null) continue;
    DateTime? day;
    for (final e in row.entries) {
      if (!slots.containsKey(e.key)) day ??= _date(e.value);
    }
    if (day == null) continue;
    for (final e in slots.entries) {
      final cell = row[e.key];
      if (cell == null || _notClass.hasMatch(cell.trim())) continue;
      var lines = cell
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length == 1) {
        // "Course Prof. Name" typed on one line.
        final i = lines.first.indexOf(RegExp(r'\s(Prof|Dr)\b'));
        if (i > 0) {
          lines = [
            lines.first.substring(0, i),
            lines.first.substring(i).trim()
          ];
        }
      }
      out.add(SheetClass(
          day, e.value.$1, e.value.$2, lines.first, lines.skip(1).join(', ')));
    }
  }
  if (slots == null) {
    throw const FormatException('This sheet does not look like a timetable');
  }
  return out;
}

const _filler = {'principles', 'of', 'and', 'the', 'to', 'in', 'for', 'lab'};

Set<String> _words(String s) => {
      for (final w in s
          .toLowerCase()
          .replaceAll('&', ' and ')
          .replaceAll(RegExp(r'[^a-z ]'), ' ')
          .split(' '))
        if (w.length > 1 && !_filler.contains(w))
          w.length > 5 ? w.substring(0, 5) : w
    };

/// The site course a sheet name means, tolerating the office's spelling
/// ("Algorithm Design & Data Structure", "Statistic ... Foundationns").
Course? matchCourse(String sheetName, List<Course> courses) {
  final want = _words(sheetName);
  if (want.isEmpty) return null;
  Course? best;
  var bestScore = 0.0;
  for (final c in courses) {
    final have = _words(c.name);
    final hit = want.intersection(have).length;
    final score = hit / want.length + hit / (have.length + 1) / 10;
    if (hit / want.length >= 0.6 && score > bestScore) {
      best = c;
      bestScore = score;
    }
  }
  return best;
}

/// Sheet classes that the attendance site does not list, as timetable slots.
List<ClassSlot> extraSlots(
    Snapshot snap, List<SheetClass> sheet, DateTime now) {
  final listed = {
    for (final s in snap.sessions)
      '${s.date.year}-${s.date.month}-${s.date.day} ${s.start}'
  };
  // The sheet has no room column: use the room most classes are in.
  final rooms = <String, int>{};
  for (final s in snap.sessions) {
    if (s.room.isNotEmpty) rooms[s.room] = (rooms[s.room] ?? 0) + 1;
  }
  final room = rooms.isEmpty
      ? ''
      : (rooms.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
  final out = <ClassSlot>[];
  for (final c in sheet) {
    final key = '${c.date.year}-${c.date.month}-${c.date.day} ${c.start}';
    if (listed.contains(key)) continue;
    final course = matchCourse(c.course, snap.courses);
    var id = '';
    if (course != null) {
      id = course.id;
      if (course.parts.isNotEmpty) {
        final hint = '${c.course} ${c.faculty}'.toLowerCase();
        final part = course.parts.where(
            (p) => p.label.isNotEmpty && hint.contains(p.label.toLowerCase()));
        id = (part.isEmpty ? course.parts.first : part.first).id;
      }
    }
    final e = c.end.split(':');
    final ends = DateTime(c.date.year, c.date.month, c.date.day,
        int.parse(e.first), int.parse(e.last));
    out.add(ClassSlot(
        -(c.date.millisecondsSinceEpoch ~/ 60000 +
            int.parse(c.start.replaceAll(':', ''))),
        c.date,
        c.start,
        c.end,
        room,
        course?.name ?? c.course,
        id,
        'Not Marked',
        ends.isAfter(now),
        fromSheet: true));
  }
  return out;
}

/// Keeps older sheet classes and replaces everything from the new sheet's
/// first day onwards (each mail says "from this date onwards").
List<SheetClass> mergeSheets(
    List<SheetClass> old, List<SheetClass> fresh, DateTime now) {
  if (fresh.isEmpty) return old;
  final first =
      fresh.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
  final keepFrom = now.subtract(const Duration(days: 45));
  return [
    for (final c in old)
      if (c.date.isBefore(first) && c.date.isAfter(keepFrom)) c,
    ...fresh,
  ];
}
