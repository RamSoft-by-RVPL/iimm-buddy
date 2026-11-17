// The leave log: the student's own note of why a class was missed.
// Kept on the phone (and in the phone's Google backup); the college's
// attendance site knows nothing about it.

import 'dart:convert';

import 'planner.dart';
import 'site.dart';

const leaveKinds = {
  'medical': 'Medical',
  'approved': 'Approved leave',
  'other': 'Other reason',
};

class Leave {
  Leave(this.kind, [this.note = '']);
  final String kind;
  final String note;

  String get label => leaveKinds[kind] ?? kind;
}

Map<int, Leave> parseLeaves(String? raw) {
  try {
    return {
      for (final e in (jsonDecode(raw ?? '{}') as Map).entries)
        int.parse('${e.key}'): Leave('${e.value['k']}', '${e.value['n'] ?? ''}')
    };
  } catch (_) {
    return {};
  }
}

String encodeLeaves(Map<int, Leave> m) => jsonEncode({
      for (final e in m.entries)
        '${e.key}': {'k': e.value.kind, 'n': e.value.note}
    });

/// Classes marked absent, newest first.
List<ClassSlot> absences(Snapshot snap) => [
      for (final s in snap.sessions)
        if (!s.upcoming && s.status == 'Absent') s
    ]..sort((a, b) => b.startsAt.compareTo(a.startsAt));

/// How many absences of [c] (or of its halves) have a reason noted.
int notedFor(Course c, Snapshot snap, Map<int, Leave> log) => absences(snap)
    .where((s) => log.containsKey(s.id) && snap.courseOf(s)?.id == c.id)
    .length;

/// The percentage if [noted] absences were counted as present.
double percentIfExcused(Course c, int noted) =>
    c.held == 0 ? 100 : (c.attended + noted) * 100 / c.held;

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.year}';

/// The log as plain text, for sharing or keeping a copy.
String leaveReport(Snapshot snap, Map<int, Leave> log) {
  final rows = absences(snap);
  final out = <String>[
    'Absences of ${snap.studentName} (${snap.roll})',
    '${rows.length} in all, ${rows.where((s) => log.containsKey(s.id)).length} '
        'with a reason noted',
    '',
  ];
  for (final s in rows.reversed) {
    final l = log[s.id];
    out.add('${_date(s.date)}  ${s.start}  ${s.course}  -  '
        '${l == null ? 'no reason noted' : l.label}'
        '${l == null || l.note.isEmpty ? '' : ' (${l.note})'}');
  }
  return out.join('\n');
}
