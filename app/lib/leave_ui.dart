import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'leave.dart';
import 'site.dart';
import 'ui_common.dart';

/// Every absence, with the reason the student notes against it.
class LeaveLogScreen extends StatefulWidget {
  const LeaveLogScreen(
      {super.key,
      required this.store,
      required this.snap,
      required this.minPct});
  final Store store;
  final Snapshot snap;
  final int minPct;

  @override
  State<LeaveLogScreen> createState() => _LeaveLogScreenState();
}

class _LeaveLogScreenState extends State<LeaveLogScreen> {
  Store get store => widget.store;
  Snapshot get snap => widget.snap;

  Future<void> edit(ClassSlot s) async {
    final log = store.leaves;
    var kind = log[s.id]?.kind;
    final note = TextEditingController(text: log[s.id]?.note ?? '');
    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.course, style: Theme.of(ctx).textTheme.titleMedium),
                Text('${fmtDate(s.date)}, ${s.start} to ${s.end}'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  for (final e in leaveKinds.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: kind == e.key,
                      onSelected: (on) => set(() => kind = on ? e.key : null),
                    ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Fever, doctor\'s letter given on 12 Nov'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDispute(context, snap, s, store.fixEmail);
                    },
                    child: const Text('I was present'),
                  ),
                  const Spacer(),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save')),
                ]),
              ]),
        ),
      ),
    );
    if (save != true) return;
    setState(() => store.setLeave(
        s.id, kind == null ? null : Leave(kind!, note.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final log = store.leaves;
    final rows = absences(snap);
    final noted = rows.where((s) => log.containsKey(s.id)).length;
    final helped = [
      for (final c in snap.courses)
        if (notedFor(c, snap, log) > 0) c
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absences and leave'),
        actions: [
          IconButton(
            tooltip: 'Share the list',
            onPressed: rows.isEmpty
                ? null
                : () => Share.share(leaveReport(snap, log),
                    subject: 'Absences of ${snap.studentName}'),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                  rows.isEmpty
                      ? 'No absences so far.'
                      : '${rows.length} ${rows.length == 1 ? 'absence' : 'absences'}, '
                          '$noted with a reason noted. Tap one to note why you '
                          'missed it. This is your own record: it does not change '
                          'anything on the college site.',
                  style: t.textTheme.bodyMedium),
            ),
            if (helped.isNotEmpty)
              Card(
                color: t.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('If the college counts these as present',
                            style: t.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final c in helped)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('${c.name}: ${fmtPct(c.percent)} now, '
                                '${fmtPct(percentIfExcused(c, notedFor(c, snap, log)))} '
                                'with ${notedFor(c, snap, log)} excused'),
                          ),
                      ]),
                ),
              ),
            for (final s in rows)
              Card(
                child: ListTile(
                  title: Text(s.course),
                  subtitle: Text('${fmtDate(s.date)}, ${s.start}'
                      '${(log[s.id]?.note ?? '').isEmpty ? '' : '\n${log[s.id]!.note}'}'),
                  trailing: log[s.id] == null
                      ? Text('Add reason',
                          style: TextStyle(color: t.colorScheme.primary))
                      : Chip(label: Text(log[s.id]!.label)),
                  onTap: () => edit(s),
                ),
              ),
          ]),
    );
  }
}

/// What the app does with the user's data, in plain words.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const sections = [
    (
      'In short',
      'IIMM Buddy is made by a student. It is not an official app of IIM '
          'Mumbai. Your attendance and Moodle data stay on your phone. The '
          'maker runs a small server for the shared class timetable and for '
          'a diagnostic log, described below. There are no ads.'
    ),
    (
      'Signing in',
      'You sign in on Microsoft\'s own page, shown inside the app. The app '
          'never sees or stores your password. After you sign in, the phone '
          'keeps the same sign-in cookies a browser would keep, so you do '
          'not have to sign in every time.'
    ),
    (
      'What the app reads',
      'Your attendance and timetable from the IIM Mumbai attendance site, '
          'and your courses, files, assignments and deadlines from the IIM '
          'Mumbai Moodle site. It reads them straight from those sites, as '
          'you, and only for your own account.'
    ),
    (
      'Where it is kept',
      'On this phone only: the last attendance data, the Moodle lists, the '
          'files you download, your settings and your leave log. If phone '
          'backup is on, Android saves the settings and the leave log (not '
          'the downloaded files and not the sign-in) to your own Google '
          'account, so they come back on a new phone.'
    ),
    (
      'What leaves the phone',
      'Requests to the two IIM Mumbai sites and to Microsoft for signing '
          'in. The app also asks a small server run by the maker of the app '
          'for the class timetable of your batch; for that it sends only the '
          'batch name (for example "bs-2026"). The same server receives the '
          'diagnostic log described below. An email or a shared picture goes out '
          'only when you press send or share yourself.'
    ),
    (
      'Instant messages',
      'So that messages and timetable changes arrive at once, the app uses '
          'Google\'s push service (Firebase Cloud Messaging), the same one '
          'most Android apps use. Google gives the app a random address for '
          'this phone; it is not linked to your name or roll number, and the '
          'messages carry no personal information.'
    ),
    (
      'Diagnostics',
      'Unless you switch it off in Settings, the app sends the maker\'s '
          'server a short log of what it did (refreshed, failed with an '
          'error, set reminders), together with your name, roll number, '
          'batch, phone model, Android version and app version. It is used '
          'to fix problems and to count how many people use the app. It '
          'never contains attendance figures, Moodle content, your password '
          'or your sign-in. Log entries are deleted after 30 days.'
    ),
    (
      'Permissions',
      'Notifications: class reminders and alerts. Calendar: only if you '
          'switch on the phone calendar option; the app writes its own '
          'calendar and does not read your other events. Internet: to reach '
          'the sites above.'
    ),
    (
      'Removing your data',
      'Sign out in Settings removes the sign-in, the saved data and the '
          'downloaded files. Uninstalling the app removes everything.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        for (final (head, body) in sections) ...[
          Text(head, style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body),
          const SizedBox(height: 18),
        ],
      ]),
    );
  }
}
