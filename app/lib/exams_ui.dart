import 'package:flutter/material.dart';

import 'acal.dart';
import 'crony_ui.dart';
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
                SheetHead(exam == null ? 'Add an exam or quiz' : 'Change',
                    subtitle: 'Get a countdown and reminders'),
                Segmented(
                    options: examKinds,
                    selected: examKinds.indexOf(kind).clamp(0, 9),
                    onChanged: (i) => set(() => kind = examKinds[i])),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                const FieldLabel('When'),
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
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.notifications_none,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'You get a reminder a week before, the evening before '
                        'and two hours before.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ),
                ]),
                const SizedBox(height: 18),
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
      if (e.id != exam?.id && !e.published) e
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

/// One published paper: what the exam timetable says about it.
void _showPaper(BuildContext context, Exam e) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHead(e.course,
                  subtitle: 'Exam',
                  trailing: DaysCount(e.at, DateTime.now(),
                      urgent: e.at.difference(DateTime.now()).inDays < 3)),
              InfoRow('Date', Text(fmtDate(e.at))),
              InfoRow('Time', Text(examWhere(e).split(' · ').first)),
              if (e.room.isNotEmpty)
                InfoRow('Where', Text(examWhere(e).split(' · ').last)),
              if (e.note.isNotEmpty) InfoRow('Note', Text(e.note)),
              const SizedBox(height: 14),
              Text(
                  'From the exam timetable your class admin published. You '
                  'get a reminder the evening before and an hour before. '
                  'The exam office\'s notice is final.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ]),
      ),
    );

/// The coming exams as a card for the home screen: the papers of the
/// student's courses from the exam timetable, and the ones they added.
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
    final now = DateTime.now();
    final coming = [
      for (final e in store.allExams(snap.courses))
        if (e.at.isAfter(now.subtract(const Duration(hours: 3)))) e
    ];
    Future<void> edit([Exam? e]) async {
      if (await editExam(context, store, snap, exam: e)) onChanged();
    }

    void tap(Exam e) => e.published ? _showPaper(context, e) : edit(e);
    void all() => Navigator.push(context, MaterialPageRoute(builder: (_) {
          final months = <String, List<Exam>>{};
          for (final e in coming) {
            months.putIfAbsent(monthTitle(e.at), () => []).add(e);
          }
          return Scaffold(
            appBar: screenBar('Exams and quizzes',
                subtitle: '${coming.length} coming up'),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  for (final m in months.entries) ...[
                    SectionTitle(m.key),
                    GroupCard(children: [
                      for (final e in m.value)
                        _ExamTile(e, now, onTap: () => tap(e)),
                    ]),
                  ],
                ]),
          );
        }));

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
      coming.isEmpty
          ? Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
                leading: const IconTile(Icons.edit_calendar_outlined),
                title: const Text('Nothing added yet',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Add your exam and quiz dates to see a countdown and '
                    'get reminders'),
                onTap: edit,
              ),
            )
          : GroupCard(children: [
              for (var i = 0; i < coming.length && i < 4; i++)
                _ExamTile(coming[i], now, onTap: () => tap(coming[i])),
              if (coming.length > 4)
                InkWell(
                  onTap: all,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
                    child: Row(children: [
                      Expanded(
                        child: Text('See all ${coming.length}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: t.colorScheme.primary)),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: t.colorScheme.primary),
                    ]),
                  ),
                ),
            ]),
    ]);
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile(this.e, this.now, {required this.onTap});
  final Exam e;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final days = e.at.difference(now).inDays;
    final time = '${e.at.hour.toString().padLeft(2, '0')}:'
        '${e.at.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(children: [
          DateBlock(e.at,
              color: days < 3 ? Tone.of(context).bad : t.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.published ? e.course : e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15)),
              const SizedBox(height: 2),
              Text(
                  e.published
                      ? 'Exam · ${examWhere(e)}'
                      : [e.kind, if (e.course.isNotEmpty) e.course, time]
                          .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          DaysCount(e.at, now, urgent: days < 3),
        ]),
      ),
    );
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
    Widget row(TermEvent e) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(children: [
            DateBlock(e.from, color: colorOf(context, e)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.15)),
                    const SizedBox(height: 2),
                    Text('${spanText(e)} · ${e.label}',
                        style: TextStyle(
                            fontSize: 13,
                            color: t.colorScheme.onSurfaceVariant)),
                  ]),
            ),
            const SizedBox(width: 12),
            e.from.isAfter(today)
                ? DaysCount(e.from, now)
                : Pill(e.oneDay ? 'Today' : 'Now', color: colorOf(context, e)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Academic calendar',
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: screenBar('Academic calendar',
                              subtitle: '${coming.length} dates ahead'),
                          body: ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                              children: [
                                for (final g in {
                                  for (final e in events) e.group
                                }) ...[
                                  SectionTitle(g.isEmpty ? 'Dates' : g),
                                  GroupCard(children: [
                                    for (final e
                                        in events.where((e) => e.group == g))
                                      Opacity(
                                          opacity:
                                              e.to.isBefore(today) ? 0.5 : 1,
                                          child: row(e)),
                                  ]),
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
      GroupCard(children: [
        for (var i = 0; i < coming.length && i < 3; i++) row(coming[i]),
      ]),
    ]);
  }
}
