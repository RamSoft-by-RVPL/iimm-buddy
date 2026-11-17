import 'package:flutter/material.dart';

import 'acal.dart';
import 'exams.dart';
import 'notify.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

/// Add or change one exam or quiz. Returns true when something was saved.
Future<bool> editExam(BuildContext context, Store store, Snapshot snap,
    {Exam? exam}) async {
  final title = TextEditingController(text: exam?.title ?? '');
  var kind = exam?.kind ?? examKinds.first;
  var course = exam?.course ?? '';
  final start = DateTime.now().add(const Duration(days: 7));
  var at = exam?.at ?? DateTime(start.year, start.month, start.day, 10);
  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam == null ? 'Add an exam or quiz' : 'Change',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 14),
                Wrap(spacing: 8, children: [
                  for (final k in examKinds)
                    ChoiceChip(
                        label: Text(k),
                        selected: kind == k,
                        onSelected: (_) => set(() => kind = k)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'What is it?',
                      hintText: 'Mid-term, Quiz 2, Viva'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value:
                      snap.courses.any((c) => c.name == course) ? course : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Course'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('No particular course')),
                    for (final c in snap.courses)
                      DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => course = v ?? ''),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(fmtDate(at)),
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: at,
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 1)),
                            lastDate:
                                DateTime.now().add(const Duration(days: 400)));
                        if (d != null) {
                          set(() => at = DateTime(
                              d.year, d.month, d.day, at.hour, at.minute));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(hm(at)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(at));
                        if (t != null) {
                          set(() => at = DateTime(
                              at.year, at.month, at.day, t.hour, t.minute));
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                    'You get a reminder a week before, the evening before '
                    'and two hours before.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 14),
                Row(children: [
                  if (exam != null)
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                        child: Text('Remove',
                            style: TextStyle(color: Tone.of(ctx).bad))),
                  const Spacer(),
                  FilledButton(
                      onPressed: () {
                        if (title.text.trim().isEmpty) return;
                        Navigator.pop(ctx, 'save');
                      },
                      child: const Text('Save')),
                ]),
              ]),
        ),
      ),
    ),
  );
  if (result == null) return false;
  final all = [
    for (final e in store.exams)
      if (e.id != exam?.id) e
  ];
  if (result == 'save') {
    all.add(Exam(exam?.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.text.trim(), course, at, kind));
  }
  store.exams = all;
  try {
    await scheduleReminders(
        store.prefs, 'rem_exam', 'classes', examReminders(store.exams));
  } catch (_) {}
  return true;
}

/// The coming exams as a card for the home screen.
class ExamsCard extends StatelessWidget {
  const ExamsCard(
      {super.key,
      required this.store,
      required this.snap,
      required this.onChanged});
  final Store store;
  final Snapshot snap;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final now = DateTime.now();
    final coming = [
      for (final e in store.exams)
        if (e.at.isAfter(now.subtract(const Duration(hours: 3)))) e
    ];
    Future<void> edit([Exam? e]) async {
      if (await editExam(context, store, snap, exam: e)) onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Exams and quizzes',
          trailing: InkWell(
            onTap: edit,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Add',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      Card(
        child: coming.isEmpty
            ? ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Nothing added yet'),
                subtitle: const Text(
                    'Add your exam and quiz dates to see a countdown and '
                    'get reminders'),
                onTap: edit,
              )
            : Column(children: [
                for (var i = 0; i < coming.length && i < 4; i++) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text('${coming[i].kind}: ${coming[i].title}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (coming[i].course.isNotEmpty) coming[i].course,
                      '${fmtDate(coming[i].at)}, '
                          '${coming[i].at.hour.toString().padLeft(2, '0')}:'
                          '${coming[i].at.minute.toString().padLeft(2, '0')}',
                    ].join(' · ')),
                    trailing: Pill(countdown(coming[i].at, now),
                        color: coming[i].at.difference(now).inDays < 3
                            ? tone.bad
                            : coming[i].at.difference(now).inDays < 8
                                ? tone.warn
                                : t.colorScheme.primary),
                    onTap: () => edit(coming[i]),
                  ),
                ],
                if (coming.length > 4)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('and ${coming.length - 4} more later',
                          style: t.textTheme.bodySmall),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

/// The next dates from the academic calendar, for the home screen.
class TermCard extends StatelessWidget {
  const TermCard({super.key, required this.events});
  final List<TermEvent> events;

  static Color colorOf(BuildContext context, TermEvent e) {
    final t = Theme.of(context);
    return switch (e.kind) {
      'exam' => t.colorScheme.primary,
      'holiday' || 'break' => Tone.of(context).good,
      _ => t.colorScheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final coming = [
      for (final e in events)
        if (!e.to.isBefore(today)) e
    ];
    if (coming.isEmpty) return const SizedBox.shrink();
    Widget row(TermEvent e) => ListTile(
          dense: true,
          title: Text(e.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${spanText(e)} · ${e.label}'),
          trailing: Pill(
              e.from.isAfter(today)
                  ? countdown(e.from, now)
                  : (e.oneDay ? 'Today' : 'Now'),
              color: colorOf(context, e)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Academic calendar',
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar:
                              AppBar(title: const Text('Academic calendar')),
                          body: ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                              children: [
                                for (final g in {
                                  for (final e in events) e.group
                                }) ...[
                                  SectionTitle(g.isEmpty ? 'Dates' : g),
                                  Card(
                                    child: Column(children: [
                                      for (final e in events
                                          .where((e) => e.group == g)) ...[
                                        if (e !=
                                            events.firstWhere(
                                                (x) => x.group == g))
                                          const Divider(indent: 16),
                                        Opacity(
                                            opacity:
                                                e.to.isBefore(today) ? 0.5 : 1,
                                            child: row(e)),
                                      ],
                                    ]),
                                  ),
                                ],
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 12, 4, 0),
                                  child: Text(
                                      'Published by your class admin from the '
                                      'institute\'s academic calendar. Dates '
                                      'can change; the institute\'s notice '
                                      'is final.',
                                      style: t.textTheme.bodySmall?.copyWith(
                                          color:
                                              t.colorScheme.onSurfaceVariant)),
                                ),
                              ]),
                        ))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('See all',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      Card(
        child: Column(children: [
          for (var i = 0; i < coming.length && i < 3; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            row(coming[i]),
          ],
        ]),
      ),
    ]);
  }
}
