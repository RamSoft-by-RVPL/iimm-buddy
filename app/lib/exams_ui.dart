import 'package:flutter/material.dart';

import 'acal.dart';
import 'crony_ui.dart';
import 'exams.dart';
import 'notify.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';
import 'glass.dart';

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
/// student's courses from the exam timetable, and the ones they added. The
/// nearest one leads; the next three follow as lines.
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
    final coming = _coming(store, snap, now);
    Future<void> edit([Exam? e]) async {
      if (await editExam(context, store, snap, exam: e)) onChanged();
    }

    void tap(Exam e) => e.published ? _showPaper(context, e) : edit(e);
    Future<void> all() async {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _ExamsScreen(store: store, snap: snap)));
      onChanged();
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
      coming.isEmpty
          ? TiltCard(
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
              InkWell(
                onTap: () => tap(coming.first),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NEXT · ${_kind(coming.first).toUpperCase()}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: _urgent(coming.first, now)
                                        ? Tone.of(context).bad
                                        : t.colorScheme.primary)),
                            const SizedBox(height: 4),
                            Text(_name(coming.first),
                                style: const TextStyle(
                                    fontFamily: 'Schoolbell',
                                    fontSize: 21,
                                    height: 1.2,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0)),
                            const SizedBox(height: 4),
                            Text(
                                '${fmtDate(coming.first.at)} · ${_where(coming.first)}',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    color: t.colorScheme.onSurfaceVariant)),
                          ]),
                    ),
                    const SizedBox(width: 12),
                    DaysCount(coming.first.at, now,
                        urgent: _urgent(coming.first, now)),
                  ]),
                ),
              ),
              for (final e in coming.skip(1).take(3))
                _ExamLine(e, now, onTap: () => tap(e)),
              if (coming.length > 1)
                InkWell(
                  onTap: all,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            coming.length > 4
                                ? 'See all ${coming.length}'
                                : 'See them by week',
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

List<Exam> _coming(Store store, Snapshot snap, DateTime now) => [
      for (final e in store.allExams(snap.courses))
        if (e.at.isAfter(now.subtract(const Duration(hours: 3)))) e
    ];

bool _urgent(Exam e, DateTime now) => e.at.difference(now).inDays < 3;

String _name(Exam e) => e.published ? e.course : e.title;

String _where(Exam e) => e.published
    ? examWhere(e)
    : [if (e.course.isNotEmpty) e.course, hhmm(e.at)].join(' · ');

String _kind(Exam e) => e.published ? 'Exam' : e.kind;

/// A later exam as one line: the day, then what and when.
class _ExamLine extends StatelessWidget {
  const _ExamLine(this.e, this.now, {required this.onTap});
  final Exam e;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 11, 16, 11),
        child: Row(children: [
          SizedBox(
            width: 54,
            child: Text('${_weekday(e.at)} ${e.at.day}',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
          ),
          Expanded(
            child: Text(_name(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 10),
          Text(_kind(e), style: TextStyle(fontSize: 12.5, color: muted)),
        ]),
      ),
    );
  }
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _weekday(DateTime d) => _wd[d.weekday - 1];
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _monday(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

String _weekTitle(DateTime monday, DateTime now) {
  final n = monday.difference(_monday(now)).inDays ~/ 7;
  if (n == 0) return 'This week';
  if (n == 1) return 'Next week';
  return 'Week of ${monday.day} ${monthTitle(monday).split(' ').first.substring(0, 3)}';
}

/// The day of the month, large, with its weekday above.
class _DayCol extends StatelessWidget {
  const _DayCol(this.d, {this.color});
  final DateTime d;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: 46,
      child: Column(children: [
        Text(_weekday(d).toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: color ?? t.colorScheme.onSurfaceVariant)),
        Text('${d.day}',
            style: TextStyle(
                fontFamily: 'Schoolbell',
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                color: color ?? t.colorScheme.onSurface)),
      ]),
    );
  }
}

/// Every coming exam: the nearest raised in wine, the rest week by week.
class _ExamsScreen extends StatefulWidget {
  const _ExamsScreen({required this.store, required this.snap});
  final Store store;
  final Snapshot snap;

  @override
  State<_ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<_ExamsScreen> {
  Future<void> _edit([Exam? e]) async {
    if (await editExam(context, widget.store, widget.snap, exam: e)) {
      setState(() {});
    }
  }

  void _tap(Exam e) => e.published ? _showPaper(context, e) : _edit(e);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final coming = _coming(widget.store, widget.snap, now);
    final weeks = <DateTime, List<Exam>>{};
    for (final e in coming.skip(1)) {
      weeks.putIfAbsent(_monday(e.at), () => []).add(e);
    }
    final add = IconButton(
        tooltip: 'Add an exam or quiz',
        icon: const Icon(Icons.add),
        onPressed: _edit);
    if (coming.isEmpty) {
      return Scaffold(
        appBar: screenBar('Exams and quizzes', actions: [add]),
        body: const Center(
          child: EmptyNote(
              icon: Icons.edit_calendar_outlined,
              title: 'Nothing coming up',
              text: 'Add your exam and quiz dates to see a countdown and '
                  'get reminders.'),
        ),
      );
    }
    final first = coming.first;
    return Scaffold(
      appBar: screenBar('Exams and quizzes',
          subtitle: '${coming.length} coming up', actions: [add]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Rise(
              index: 0,
              child: Sticker(
                  radius: 24,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _tap(first),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'NEXT · ${countdown(first.at, now).toUpperCase()}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                      color: Brand.onPink)),
                              const SizedBox(height: 8),
                              Text(_name(first),
                                  style: const TextStyle(
                                      fontFamily: 'Schoolbell',
                                      fontSize: 31,
                                      height: 1.15,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0,
                                      color: Brand.onPink)),
                              const SizedBox(height: 12),
                              Text(fmtDate(first.at),
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Brand.onPink)),
                              const SizedBox(height: 2),
                              Text('${_kind(first)} · ${_where(first)}',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Brand.onPink.withOpacity(0.75))),
                              if (first.note.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(first.note,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        color: Brand.onPink.withOpacity(0.75))),
                              ],
                            ]),
                      ),
                    ),
                  )),
            ),
            for (final (k, w) in weeks.entries.indexed) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                child: Row(children: [
                  Text(_weekTitle(w.key, now),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3)),
                  const Spacer(),
                  Text(
                      '${w.value.length} ${w.value.length == 1 ? 'paper' : 'papers'}',
                      style: TextStyle(fontSize: 13, color: muted)),
                ]),
              ),
              Rise(
                index: k + 1,
                child: GroupCard(children: [
                  for (final (i, e) in w.value.indexed)
                    InkWell(
                      onTap: () => _tap(e),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                        child: Row(children: [
                          i > 0 && _day(w.value[i - 1].at) == _day(e.at)
                              ? const SizedBox(width: 46)
                              : _DayCol(e.at),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_name(e),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.15)),
                                  const SizedBox(height: 2),
                                  Text('${_kind(e)} · ${_where(e)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13, color: muted)),
                                ]),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
              child: Text(
                  'Papers from the exam timetable your class admin published, '
                  'and the ones you added. Tap one to see it or change it.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted)),
            ),
          ]),
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
    final today = _day(now);
    final coming = [
      for (final e in events)
        if (!e.to.isBefore(today)) e
    ];
    if (coming.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Academic calendar',
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _CalendarScreen(events: events))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('See all',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      GroupCard(children: [
        for (var i = 0; i < coming.length && i < 3; i++)
          _TermRow(coming[i], today, now, countdown: i == 0),
      ]),
    ]);
  }
}

/// One date of the calendar: the day it starts, what it is, how long.
class _TermRow extends StatelessWidget {
  const _TermRow(this.e, this.today, this.now, {this.countdown = false});
  final TermEvent e;
  final DateTime today;
  final DateTime now;
  final bool countdown;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final c = TermCard.colorOf(context, e);
    final on = !e.from.isAfter(today) && !e.to.isBefore(today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(children: [
        _DayCol(e.from, color: on ? c : null),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(e.label,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(spanText(e),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted)),
              ),
            ]),
          ]),
        ),
        if (on)
          Pill(e.oneDay ? 'Today' : 'Now', color: c)
        else if (countdown && e.from.isAfter(today))
          Text(_countdownDays(e.from, now),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
      ]),
    );
  }
}

String _countdownDays(DateTime at, DateTime now) {
  final s = countdown(at, now);
  return s.startsWith('in ') && s.endsWith(' h') ? 'Today' : s;
}

/// The whole academic calendar, term by term, month by month.
class _CalendarScreen extends StatelessWidget {
  const _CalendarScreen({required this.events});
  final List<TermEvent> events;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final today = _day(now);
    final ahead = [
      for (final e in events)
        if (!e.to.isBefore(today)) e
    ];
    final nextAt = ahead.isEmpty ? null : ahead.first;
    return Scaffold(
      appBar: screenBar('Academic calendar',
          subtitle:
              '${ahead.length} ${ahead.length == 1 ? 'date' : 'dates'} ahead'),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            for (final g in {for (final e in events) e.group}) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(g.isEmpty ? 'Dates' : g,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
              ),
              GroupCard(children: [
                for (final e in events.where((e) => e.group == g))
                  Opacity(
                      opacity: e.to.isBefore(today) ? 0.45 : 1,
                      child: _TermRow(e, today, now, countdown: e == nextAt)),
              ]),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                  'Published by your class admin from the institute\'s academic '
                  'calendar. Dates can change; the institute\'s notice is final.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted)),
            ),
          ]),
    );
  }
}
