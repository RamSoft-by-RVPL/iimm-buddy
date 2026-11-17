import 'package:flutter/material.dart';

import 'absence.dart';
import 'acal.dart';
import 'exams.dart';
import 'moodle.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

/// A week of classes with Moodle deadlines on the same page.
class TimetableTab extends StatefulWidget {
  const TimetableTab(
      {super.key,
      required this.snap,
      required this.minPct,
      required this.deadlines,
      this.fixEmail = '',
      this.exams = const [],
      this.calendar = const [],
      this.onOpenDeadline});
  final List<TermEvent> calendar;
  final List<Exam> exams;
  final void Function(Deadline)? onOpenDeadline;
  final String fixEmail;
  final Snapshot snap;
  final int minPct;
  final List<Deadline> deadlines;

  @override
  State<TimetableTab> createState() => _TimetableTabState();
}

class _TimetableTabState extends State<TimetableTab> {
  int week = 0; // 0 = this week
  int monthOff = 0; // 0 = this month
  bool byMonth = false;
  final todayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Open on today, not on Monday.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = todayKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.02);
    });
  }

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  Widget classTile(BuildContext context, ClassSlot s, DateTime now) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final live = !s.startsAt.isAfter(now) && s.endsAt.isAfter(now);
    final (label, color) = switch (s) {
      _ when live => ('Now', t.colorScheme.primary),
      _ when s.upcoming => ('Upcoming', t.colorScheme.onSurfaceVariant),
      _ when s.fromSheet => ('To be updated', t.colorScheme.onSurfaceVariant),
      _ when s.status == 'Present' => ('Present', tone.good),
      _ when s.status == 'Late' => ('Late', tone.warn),
      _ when s.status == 'Absent' => ('Absent', tone.bad),
      _ => ('Not marked', tone.warn),
    };
    final onTap = s.upcoming
        ? () => showSkip(context, widget.snap, s, widget.minPct)
        : canDispute(s)
            ? () => showDispute(context, widget.snap, s, widget.fixEmail)
            : null;
    return Card(
      color: live ? t.colorScheme.primaryContainer.withOpacity(0.5) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 50,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.start,
                        style: t.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    Text(s.end,
                        style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.course,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, height: 1.25)),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (s.room.isNotEmpty)
                            Text('Room ${s.room}',
                                style: t.textTheme.bodySmall?.copyWith(
                                    color: t.colorScheme.onSurfaceVariant)),
                          if (s.fromSheet)
                            Pill('Not on portal yet',
                                outlined: true,
                                color: t.colorScheme.onSurfaceVariant),
                        ]),
                  ]),
            ),
            const SizedBox(width: 8),
            Pill(label, color: color),
          ]),
        ),
      ),
    );
  }

  Widget dueTile(BuildContext context, Deadline x) {
    final t = Theme.of(context);
    final hh = x.due.hour.toString().padLeft(2, '0');
    final mm = x.due.minute.toString().padLeft(2, '0');
    return Card(
      color: t.colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.assignment_outlined),
        title:
            Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${x.course} · due $hh:$mm'),
        trailing: widget.onOpenDeadline == null || x.url.isEmpty
            ? null
            : const Icon(Icons.chevron_right),
        onTap: widget.onOpenDeadline == null || x.url.isEmpty
            ? null
            : () => widget.onOpenDeadline!(x),
      ),
    );
  }

  Widget examTile(BuildContext context, Exam x) {
    final t = Theme.of(context);
    final hh = x.at.hour.toString().padLeft(2, '0');
    final mm = x.at.minute.toString().padLeft(2, '0');
    return Card(
      color: t.colorScheme.primaryContainer,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.school_outlined,
            color: t.colorScheme.onPrimaryContainer),
        title: Text('${x.kind}: ${x.title}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.colorScheme.onPrimaryContainer)),
        subtitle: Text('${x.course.isEmpty ? '' : '${x.course} · '}$hh:$mm',
            style: TextStyle(color: t.colorScheme.onPrimaryContainer)),
      ),
    );
  }

  List<TermEvent> termOn(DateTime d) => [
        for (final e in widget.calendar)
          if (e.covers(d)) e
      ];

  Widget termTile(BuildContext context, TermEvent e) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final (icon, color) = switch (e.kind) {
      'exam' => (Icons.school_outlined, t.colorScheme.primary),
      'holiday' => (Icons.celebration_outlined, tone.good),
      'break' => (Icons.beach_access_outlined, tone.good),
      _ => (Icons.flag_outlined, t.colorScheme.onSurfaceVariant),
    };
    return Card(
      color: color.withOpacity(0.10),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title:
            Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(e.oneDay
            ? (e.dayOff ? 'No classes' : e.label)
            : '${spanText(e)}${e.dayOff ? ' · no classes' : ''}'),
        trailing: Pill(e.label, color: color),
      ),
    );
  }

  List<ClassSlot> slotsOn(DateTime d) => [
        for (final s in widget.snap.sessions)
          if (day(s.date) == d) s
      ]..sort((a, b) => a.start.compareTo(b.start));

  /// Everything on one day, in a sheet (used by the month view).
  void showDay(BuildContext context, DateTime d) {
    final now = DateTime.now();
    final slots = slotsOn(d);
    final due = widget.deadlines.where((x) => day(x.due) == d).toList();
    final ex = widget.exams.where((x) => day(x.at) == d).toList();
    final term = termOn(d);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmtDate(d), style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final e in term) termTile(ctx, e),
                  if (slots.isEmpty &&
                      due.isEmpty &&
                      ex.isEmpty &&
                      term.isEmpty)
                    const EmptyNote(
                        icon: Icons.event_available_outlined,
                        title: 'Nothing on this day'),
                  for (final x in ex) examTile(ctx, x),
                  for (final s in slots) classTile(ctx, s, now),
                  for (final x in due) dueTile(ctx, x),
                ]),
          ),
        ),
      ),
    );
  }

  /// The month as a grid: one dot per class, coloured by what happened.
  List<Widget> monthView(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final now = DateTime.now();
    final today = day(now);
    final first = DateTime(today.year, today.month + monthOff, 1);
    final days = DateTime(first.year, first.month + 1, 0).day;
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    var held = 0, present = 0, absent = 0;
    Color dot(ClassSlot s) {
      if (s.upcoming || s.fromSheet) return t.colorScheme.outline;
      if (s.status == 'Present' || s.status == 'Late') return tone.good;
      if (s.status == 'Absent') return tone.bad;
      return tone.warn;
    }

    final cells = <Widget>[
      for (var i = 1; i < first.weekday; i++) const SizedBox(),
    ];
    for (var n = 1; n <= days; n++) {
      final d = DateTime(first.year, first.month, n);
      final slots = slotsOn(d);
      for (final s in slots) {
        if (s.upcoming || s.fromSheet) continue;
        held++;
        if (s.status == 'Present' || s.status == 'Late') present++;
        if (s.status == 'Absent') absent++;
      }
      final term = termOn(d);
      final examDay = term.any((e) => e.kind == 'exam');
      final offDay = term.any((e) => e.kind == 'holiday' || e.kind == 'break');
      final marks = examDay || widget.exams.any((x) => day(x.at) == d);
      final due = widget.deadlines.any((x) => day(x.due) == d);
      final isToday = d == today;
      final missed = slots.any((s) => !s.upcoming && s.status == 'Absent');
      cells.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDay(context, d),
        child: Container(
          decoration: BoxDecoration(
            color: missed
                ? tone.bad.withOpacity(0.10)
                : marks
                    ? t.colorScheme.primaryContainer
                    : offDay
                        ? tone.good.withOpacity(0.14)
                        : null,
            border: isToday
                ? Border.all(color: t.colorScheme.primary, width: 1.6)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$n',
                style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
            const SizedBox(height: 3),
            SizedBox(
              height: 7,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final s in slots.take(4))
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration:
                        BoxDecoration(color: dot(s), shape: BoxShape.circle),
                  ),
                if (due)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    color: t.colorScheme.onSurfaceVariant,
                  ),
              ]),
            ),
          ]),
        ),
      ));
    }
    Widget key(Color c, String label, {bool square = false}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: c,
                  shape: square ? BoxShape.rectangle : BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: t.textTheme.bodySmall),
        ]);

    return [
      Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            IconButton(
                tooltip: 'Earlier month',
                onPressed: () => setState(() => monthOff--),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: InkWell(
                onTap:
                    monthOff == 0 ? null : () => setState(() => monthOff = 0),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Text('${names[first.month - 1]} ${first.year}',
                        style: t.textTheme.titleSmall),
                    Text(
                        monthOff == 0
                            ? 'This month'
                            : 'Tap to go back to this month',
                        style: t.textTheme.bodySmall?.copyWith(
                            color: monthOff == 0
                                ? t.colorScheme.onSurfaceVariant
                                : t.colorScheme.primary)),
                  ]),
                ),
              ),
            ),
            IconButton(
                tooltip: 'Later month',
                onPressed: () => setState(() => monthOff++),
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          child: Column(children: [
            Row(children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: t.textTheme.labelSmall
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.95,
              children: cells,
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Wrap(spacing: 14, runSpacing: 6, children: [
          key(tone.good, 'Present'),
          key(tone.bad, 'Absent'),
          key(tone.warn, 'Not marked'),
          key(t.colorScheme.outline, 'Coming up'),
          key(t.colorScheme.onSurfaceVariant, 'Deadline', square: true),
          key(t.colorScheme.primaryContainer, 'Exam day', square: true),
          if (widget.calendar.isNotEmpty)
            key(tone.good.withOpacity(0.35), 'Holiday or break', square: true),
        ]),
      ),
      Card(
        margin: const EdgeInsets.only(top: 12),
        child: ListTile(
          leading: const Icon(Icons.insights_outlined),
          title: Text(held == 0
              ? 'No classes held in ${names[first.month - 1]} yet'
              : 'Attended $present of $held classes'),
          subtitle: held == 0
              ? null
              : Text('${(present * 100 / held).toStringAsFixed(1)}% in '
                  '${names[first.month - 1]} · $absent absent'
                  '${held - present - absent > 0 ? ' · ${held - present - absent} not marked' : ''}'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text('Tap a day to see its classes.',
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ),
    ];
  }

  Widget viewSwitch() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: false,
                icon: Icon(Icons.view_agenda_outlined),
                label: Text('Week')),
            ButtonSegment(
                value: true,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Month')),
          ],
          selected: {byMonth},
          onSelectionChanged: (v) => setState(() => byMonth = v.first),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final today = day(now);
    final monday = DateTime(
        today.year, today.month, today.day - (today.weekday - 1) + 7 * week);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final horizon =
        widget.snap.courses.isEmpty ? null : widget.snap.courses.first.horizon;

    if (byMonth) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [viewSwitch(), ...monthView(context)]),
      );
    }

    // The switch and the week stay put; the days scroll under them.
    final children = <Widget>[];
    final pinned = <Widget>[
      viewSwitch(),
      Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            IconButton(
                tooltip: 'Earlier week',
                onPressed: () => setState(() => week--),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: InkWell(
                onTap: week == 0 ? null : () => setState(() => week = 0),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Text(
                        week == 0
                            ? 'This week'
                            : week == 1
                                ? 'Next week'
                                : week == -1
                                    ? 'Last week'
                                    : '${fmtDate(monday)} to ${fmtDate(sunday)}',
                        style: t.textTheme.titleSmall),
                    Text(
                        week == 0 || week.abs() > 1
                            ? '${monday.day} to ${fmtDate(sunday).substring(4)}'
                            : 'Tap to go back to this week',
                        style: t.textTheme.bodySmall?.copyWith(
                            color: week == 0 || week.abs() > 1
                                ? t.colorScheme.onSurfaceVariant
                                : t.colorScheme.primary)),
                  ]),
                ),
              ),
            ),
            IconButton(
                tooltip: 'Later week',
                onPressed: () => setState(() => week++),
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
      ),
    ];

    var any = false;
    var sheetOnly = false;
    for (var i = 0; i < 7; i++) {
      final d = DateTime(monday.year, monday.month, monday.day + i);
      final slots = slotsOn(d);
      final due = [
        for (final x in widget.deadlines)
          if (day(x.due) == d) x
      ];
      final ex = [
        for (final x in widget.exams)
          if (day(x.at) == d) x
      ];
      final term = termOn(d);
      if (slots.isEmpty && due.isEmpty && ex.isEmpty && term.isEmpty) continue;
      any = true;
      final isToday = d == today;
      children.add(SectionTitle(
        key: isToday ? todayKey : null,
        isToday ? 'Today · ${fmtDate(d)}' : fmtDate(d),
        trailing: Text(
            slots.isEmpty
                ? ''
                : '${slots.length} ${slots.length == 1 ? 'class' : 'classes'}',
            style: t.textTheme.labelSmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ));
      for (final e in term) {
        children.add(termTile(context, e));
      }
      for (final x in ex) {
        children.add(examTile(context, x));
      }
      for (final s in slots) {
        sheetOnly = sheetOnly || s.fromSheet;
        children.add(classTile(context, s, now));
      }
      for (final x in due) {
        children.add(dueTile(context, x));
      }
    }

    if (!any) {
      final notOut = horizon != null && monday.isAfter(horizon);
      children.add(EmptyNote(
        icon: notOut ? Icons.hourglass_empty : Icons.event_available_outlined,
        title:
            notOut ? 'This week is not published yet' : 'No classes this week',
        text: notOut
            ? 'The timetable is out up to ${fmtDate(horizon)}. Later weeks '
                'appear here as soon as the college publishes them.'
            : null,
      ));
    } else {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
        child: Text(
            [
              'Tap an upcoming class to see what skipping it does.',
              if (sheetOnly)
                '"Not on portal yet" classes come from the weekly timetable '
                    'mail. Their attendance appears once the college adds it.',
              if (horizon != null && sunday.isAfter(horizon) && week >= 0)
                'The timetable is published up to ${fmtDate(horizon)}.',
            ].join(' '),
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: pinned),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        ),
      ),
    ]);
  }
}
