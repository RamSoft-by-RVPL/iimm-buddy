import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'crony_ui.dart';
import 'leave.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';
import 'glass.dart';

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
                SheetHead(s.course,
                    subtitle: '${fmtDate(s.date)}, ${s.start} to ${s.end}',
                    trailing: DateBlock(s.date)),
                const FieldLabel('Why you missed it'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in leaveKinds.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: kind == e.key,
                      onSelected: (on) => set(() => kind = on ? e.key : null),
                    ),
                ]),
                const SizedBox(height: 16),
                const FieldLabel('Note'),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Fever, doctor\'s letter given on 12 Nov'),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDispute(context, snap, s, store.fixEmail);
                    },
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('I was present'),
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
    final tone = Tone.of(context);
    final log = store.leaves;
    final rows = absences(snap);
    final noted = rows.where((s) => log.containsKey(s.id)).length;
    final helped = [
      for (final c in snap.courses)
        if (notedFor(c, snap, log) > 0) c
    ];
    final months = <String, List<ClassSlot>>{};
    for (final s in rows) {
      months.putIfAbsent(monthTitle(s.date), () => []).add(s);
    }
    final muted = t.colorScheme.onSurfaceVariant;

    Widget stat(String n, String label, Color? c) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n,
                style: TextStyle(
                    fontFamily: 'Schoolbell',
                    fontSize: 37,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: c)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, color: muted)),
          ]),
        );

    Widget row(ClassSlot s) {
      final l = log[s.id];
      return InkWell(
        onTap: () => edit(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            DateBlock(s.date, color: l == null ? muted : tone.good),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.course,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.15)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          '${fmtDate(s.date).split(' ').first}, ${s.start}',
                          if ((l?.note ?? '').isNotEmpty) l!.note,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: muted)),
                  ]),
            ),
            const SizedBox(width: 10),
            l == null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: t.colorScheme.primary.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(99)),
                    child: Text('Add reason',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.colorScheme.primary)),
                  )
                : Pill(l.label, color: tone.good),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: screenBar('Absences and leave',
          subtitle: rows.isEmpty ? null : 'Your own record of why',
          actions: [
            IconButton(
              tooltip: 'Share the list',
              onPressed: rows.isEmpty
                  ? null
                  : () => Share.share(leaveReport(snap, log),
                      subject: 'Absences of ${snap.studentName}'),
              icon: const Icon(Icons.share_outlined),
            ),
          ]),
      body: rows.isEmpty
          ? const Center(
              child: EmptyNote(
                  icon: Icons.event_available_outlined,
                  title: 'No absences so far.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                  Rise(
                    index: 0,
                    child: TiltCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                stat(
                                    '${rows.length}',
                                    rows.length == 1 ? 'absence' : 'absences',
                                    null),
                                stat('$noted', 'with a reason noted',
                                    noted > 0 ? tone.good : muted),
                              ]),
                              const SizedBox(height: 14),
                              Text(
                                  'Tap one to note why you missed it. This is '
                                  'your own record: it does not change anything '
                                  'on the college site.',
                                  style: TextStyle(
                                      fontSize: 13, height: 1.4, color: muted)),
                            ]),
                      ),
                    ),
                  ),
                  if (helped.isNotEmpty) ...[
                    const SectionTitle(
                        'If the college counts these as present'),
                    GroupCard(children: [
                      for (final c in helped)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(codeOf(c.name, store.shortNames),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${fmtPct(c.percent)} now, '
                                        'with ${notedFor(c, snap, log)} excused',
                                        style: TextStyle(
                                            fontSize: 13, color: muted)),
                                  ]),
                            ),
                            Text(
                                fmtPct(percentIfExcused(
                                    c, notedFor(c, snap, log))),
                                style: TextStyle(
                                    fontFamily: 'Schoolbell',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0,
                                    color: tone.good)),
                          ]),
                        ),
                    ]),
                  ],
                  for (final m in months.entries) ...[
                    SectionTitle(m.key,
                        trailing: Text('${m.value.length}',
                            style: TextStyle(fontSize: 13, color: muted))),
                    GroupCard(children: [for (final s in m.value) row(s)]),
                  ],
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
      'Crony is made by a student and published by Ramya Ventures Private '
          'Limited. It is not an official app of IIM Mumbai. Your attendance '
          'and Moodle data stay on your phone. Ramya Ventures runs a small '
          'server for the shared class timetable and for a diagnostic log, '
          'described below. There are no ads.'
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
          'in. The app also asks a small server run by Ramya Ventures '
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
      'Unless you switch it off in Settings, the app sends Ramya '
          'Ventures\' server a short log of what it did (refreshed, failed with an '
          'error, set reminders), together with your name, roll number, '
          'batch, phone model, Android version and app version. It is used '
          'to fix problems and to count how many people use the app. It '
          'never contains attendance figures, Moodle content, your password '
          'or your sign-in. Log entries are deleted after 30 days.'
    ),
    (
      'Meal ratings',
      'When you rate a mess meal, the app sends the server the meal, your '
          'rating and the random id of this copy of the app, so that each '
          'phone counts once. Other students see only the count and the '
          'average. Ratings are deleted after four months.'
    ),
    (
      'Free time shared with friends',
      'This is off until you switch it on. While it is on, the app sends '
          'the server your first name and the times you are in class for '
          'the next two weeks, and nothing else: no course names, no rooms '
          'and no attendance. Anyone you give your code to can see those '
          'times. Switching it off, or signing out, deletes them from the '
          'server at once, and the code stops working.'
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
    (
      'Questions',
      'Write to ramyaventurespvtltd@gmail.com about your data or to have '
          'your diagnostic log deleted sooner.'
    ),
  ];

  static const _icons = [
    Icons.favorite_outline,
    Icons.lock_outline,
    Icons.visibility_outlined,
    Icons.smartphone_outlined,
    Icons.cloud_upload_outlined,
    Icons.notifications_none,
    Icons.monitor_heart_outlined,
    Icons.verified_user_outlined,
    Icons.delete_outline,
    Icons.mail_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (head0, body0) = sections.first;
    return Scaffold(
      appBar: screenBar('Privacy', subtitle: 'What Crony does with your data'),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Rise(
              index: 0,
              child: Sticker(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(head0.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: Brand.onPink)),
                      const SizedBox(height: 8),
                      Text(body0,
                          style: const TextStyle(
                              fontSize: 15.5,
                              height: 1.45,
                              color: Brand.onPink)),
                    ]),
              ),
            ),
            const SizedBox(height: 8),
            for (final (i, (head, body)) in sections.indexed.skip(1))
              Rise(
                index: i,
                child: TiltCard(
                  margin: const EdgeInsets.only(top: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 18, 18),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconTile(_icons[i]),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(head,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2)),
                                  const SizedBox(height: 6),
                                  Text(body,
                                      style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: t.colorScheme.onSurface
                                              .withOpacity(0.82))),
                                ]),
                          ),
                        ]),
                  ),
                ),
              ),
          ]),
    );
  }
}
