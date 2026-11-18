import 'package:flutter/material.dart';

import 'package:cookie_bridge/cookie_bridge.dart';

import 'absence.dart';
import 'background.dart';
import 'crony_ui.dart';
import 'planner.dart';
import 'site.dart';

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
String fmtDate(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String fmtPct(double p) => '${p.toStringAsFixed(1)}%';

const good = Color(0xFF2E7D32);
const warn = Color(0xFFB26A00);
const bad = Color(0xFFC62828);

Future<int?> askNumber(BuildContext context,
    {required String title,
    required int initial,
    required int min,
    required int max,
    String? help}) {
  final ctl = TextEditingController(text: '$initial');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(helperText: help, helperMaxLines: 3),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(ctl.text.trim());
            if (n != null && n >= min && n <= max) Navigator.pop(ctx, n);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<String?> askText(BuildContext context,
    {required String title,
    required String initial,
    String? help,
    TextInputType keyboard = TextInputType.text,
    int? maxLength}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: keyboard,
        maxLength: maxLength,
        decoration: InputDecoration(helperText: help, helperMaxLines: 4),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}

/// What missing one class does to [c], in a sentence.
String skipLine(Course c, int minPct) {
  final after = Course(
      id: c.id,
      name: c.name,
      held: c.held + 1,
      attended: c.attended,
      total: c.total);
  final left = leaveLeft(after, minPct);
  final pct = '${fmtPct(c.percent)} to ${fmtPct(after.percent)}';
  if (leaveLeft(c, minPct) < 0) {
    return 'Already over the limit ($pct). Do not skip.';
  }
  if (c.total != null) {
    return left >= 0
        ? 'Goes from $pct. ${left == 0 ? 'No leave' : '${classes(left)} of leave'} left after.'
        : 'Goes from $pct and over the limit: $minPct% is then out of reach.';
  }
  return left >= 0
      ? 'Goes from $pct, still at or above $minPct%.'
      : 'Goes from $pct, below $minPct%. '
          'You would need ${classes(classesToRecover(after, minPct))} in a row to recover.';
}

bool canSkip(Course c, int minPct) =>
    leaveLeft(
        Course(
            id: c.id,
            name: c.name,
            held: c.held + 1,
            attended: c.attended,
            total: c.total),
        minPct) >=
    0;

/// "Can I skip this class?": the course sheet with the skip simulator.
void showSkip(BuildContext context, Snapshot snap, ClassSlot s, int minPct,
    {Map<String, String> shortNames = const {}}) {
  final c = snap.courseOf(s);
  if (c == null) return;
  openCourseSheet(context,
      course: c, snap: snap, minPct: minPct, slot: s, shortNames: shortNames);
}

/// "Were you present?" for a finished class that shows absent or unmarked:
/// opens the email app with a correction request already written.
void showDispute(BuildContext context, Snapshot snap, ClassSlot s, String to) {
  final mail = absenceEmail(snap, s);
  final absent = s.status == 'Absent';
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(absent ? 'Marked absent' : 'Not marked yet'),
      content: Text('${s.course}\n${fmtDate(s.date)}, ${s.start} to ${s.end}'
          '\n\nIf you were present, the app can write the email asking for '
          'a correction. You check it and press send yourself.'
          '${to.isEmpty ? '\n\nYou will need to fill in who it goes to. '
              'You can save an address in Settings.' : '\n\nIt will be addressed to $to.'}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await composeEmail(to, mail.subject, mail.body);
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('No email app found on this phone')));
            }
          },
          child: const Text('Write email'),
        ),
      ],
    ),
  );
}

/// "2 days, 1 day and 3 hours before".
String dueSummary(List<int> hours) {
  String one(int h) => h % 24 == 0
      ? '${h ~/ 24} ${h == 24 ? 'day' : 'days'}'
      : '$h ${h == 1 ? 'hour' : 'hours'}';
  final parts = [for (final h in hours) one(h)];
  return parts.length == 1
      ? '${parts.first} before'
      : '${parts.take(parts.length - 1).join(', ')} and ${parts.last} before';
}

/// Asks when to be reminded about assignment deadlines. Returns true when
/// the choice was saved.
Future<bool> askDueTimes(BuildContext context, Store store) async {
  final chosen = {...store.dueHours};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Assignment reminders'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('You are always reminded 2 days before an '
                  'assignment is due. When else do you want a reminder? '
                  'They stop once you submit.'),
            ),
            for (final h in dueChoices)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(h == dueChoices.first
                    ? '2 days before (always)'
                    : 'Due ${dueIn(h)}'
                        .replaceFirst('Due in ', '')
                        .replaceFirst('Due tomorrow', '1 day')
                        .replaceFirst(RegExp(r'$'), ' before')),
                value: chosen.contains(h),
                onChanged: h == dueChoices.first
                    ? null
                    : (v) => set(() => v! ? chosen.add(h) : chosen.remove(h)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  store.dueHours = chosen.toList();
  return true;
}
