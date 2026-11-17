import 'package:flutter/material.dart';

import 'acal.dart';
import 'planner.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

/// Leave planner: how long you can be away, and what given days off cost.
class PlanTab extends StatefulWidget {
  const PlanTab(
      {super.key,
      required this.snap,
      required this.minPct,
      this.calendar = const []});
  final Snapshot snap;
  final int minPct;
  final List<TermEvent> calendar;

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  DateTimeRange? range;

  DateTime get today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> pick() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: range,
      helpText: 'Days you will be away',
    );
    if (r != null) setState(() => range = r);
  }

  String days(int n) => '$n ${n == 1 ? 'day' : 'days'}';

  // The idea lists take a moment to work out, so keep them until the
  // attendance, the limit or the calendar changes.
  Object? _ideasFor;
  List<BreakIdea> _weekends = const [];
  List<BreakIdea> _breaks = const [];

  void _ideas() {
    final key = (widget.snap, widget.minPct, widget.calendar, today);
    if (_ideasFor == key) return;
    _ideasFor = key;
    final courses = widget.snap.courses;
    _weekends = longWeekends(courses, today, widget.minPct);
    // Leave out breaks already shown as a long weekend.
    _breaks = [
      for (final b in suggestBreaks(courses, today, widget.minPct))
        if (!_weekends
            .any((w) => !b.from.isBefore(w.from) && !b.to.isAfter(w.to)))
          b
    ];
  }

  /// Holidays from the academic calendar that fall inside [i].
  String? _holiday(BreakIdea i) {
    final names = {
      for (final e in widget.calendar)
        if (e.dayOff && !e.to.isBefore(i.from) && !e.from.isAfter(i.to)) e.title
    };
    return names.isEmpty ? null : names.join(', ');
  }

  Widget _idea(BreakIdea i, {required bool weekend}) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final guess = widget.snap.courses.any((c) => isEstimated(c, i.to));
    final holiday = _holiday(i);
    final picked = range?.start == i.from && range?.end == i.to;
    return Card(
      child: InkWell(
        onTap: () =>
            setState(() => range = DateTimeRange(start: i.from, end: i.to)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${fmtDate(i.from)} to ${fmtDate(i.to)}',
                        style: t.textTheme.titleSmall),
                    if (holiday != null) ...[
                      const SizedBox(height: 2),
                      Text(holiday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      Pill('${days(i.days)} away', color: tone.good),
                      if (weekend) Pill('${days(i.leave)} of leave'),
                      Pill('Misses ${classes(i.missed)}'),
                      if (guess) const Pill('Estimate', outlined: true),
                    ]),
                  ]),
            ),
            Icon(picked ? Icons.check_circle : Icons.chevron_right,
                color: picked ? tone.good : null),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final min = widget.minPct;
    final courses = widget.snap.courses;
    final dim =
        t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final tomorrow = today.add(const Duration(days: 1));
    final until = safeUntil(courses, today, tomorrow, min, cap: 120);
    final r = range;
    _ideas();

    final children = <Widget>[
      // ---- the one number most people want
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(until == null ? 'Tomorrow' : 'From tomorrow', style: dim),
            const SizedBox(height: 4),
            Text(
                until == null
                    ? 'One day away puts a course below $min%'
                    : 'You can be away until ${fmtDate(until)}',
                style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                until == null
                    ? (_weekends.isEmpty && _breaks.isEmpty
                        ? 'Attend for a while before taking leave.'
                        : 'Attend the next few days and the dates below '
                            'still work.')
                    : '${days(until.difference(tomorrow).inDays + 1)} and every '
                        'course stays at or above $min% by the end of term.',
                style: t.textTheme.bodyMedium),
          ]),
        ),
      ),

      // ---- check given days
      const SectionTitle('Check your dates'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.date_range),
          title: Text(r == null
              ? 'Pick the days you will be away'
              : '${fmtDate(r.start)} to ${fmtDate(r.end)}'),
          subtitle: r == null ? null : Text(days(r.duration.inDays + 1)),
          trailing: TextButton(
              onPressed: pick, child: Text(r == null ? 'Pick' : 'Change')),
          onTap: pick,
        ),
      ),
    ];

    if (r != null) {
      final list = [
        for (final c in courses) holidayImpact(c, today, r.start, r.end, min)
      ]..sort((a, b) => a.leaveAfter.compareTo(b.leaveAfter));
      final hit = list.where((i) => breaksCourse(i, min)).toList();
      final missed = list.fold(0, (a, i) => a + i.missed);
      final off = [
        for (final e in widget.calendar)
          if (e.dayOff && !e.to.isBefore(r.start) && !e.from.isAfter(r.end)) e
      ];
      children.add(Card(
        child: Column(children: [
          ListTile(
            leading: Icon(
                hit.isEmpty ? Icons.check_circle_outline : Icons.error_outline,
                color: hit.isEmpty ? tone.good : tone.bad),
            title: Text(
                missed == 0
                    ? 'No classes on these days'
                    : hit.isEmpty
                        ? 'Fine: every course stays above $min%'
                        : '${hit.length} ${hit.length == 1 ? 'course falls' : 'courses fall'} below $min%',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (missed > 0) 'About ${classes(missed)} missed in all',
              if (off.isNotEmpty)
                '${off.map((e) => e.title).toSet().join(' and ')} '
                    '${off.map((e) => e.title).toSet().length == 1 ? 'falls' : 'fall'} in these days',
            ].join('. ')),
          ),
          if (missed > 0) ...[
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Expanded(child: Text('Course', style: dim)),
                SizedBox(
                    width: 56,
                    child:
                        Text('Misses', style: dim, textAlign: TextAlign.end)),
                SizedBox(
                    width: 70,
                    child: Text('After', style: dim, textAlign: TextAlign.end)),
              ]),
            ),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(children: [
                  Expanded(
                      child: Text(i.course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodyMedium)),
                  SizedBox(
                      width: 56,
                      child: Text('${i.missed}',
                          textAlign: TextAlign.end,
                          style: t.textTheme.bodyMedium)),
                  SizedBox(
                      width: 70,
                      child: Text(fmtPct(i.percentAfter),
                          textAlign: TextAlign.end,
                          style: t.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: !i.safe
                                  ? tone.bad
                                  : i.leaveAfter == 0
                                      ? tone.warn
                                      : tone.good))),
                ]),
              ),
            const SizedBox(height: 8),
          ],
        ]),
      ));
    }

    // ---- ready-made ideas
    children.add(const SectionTitle('Long weekends'));
    if (_weekends.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(
            'No Sunday or holiday in the next six weeks can be stretched '
            'with one or two days of leave and keep every course at $min%.',
            style: dim),
      ));
    } else {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(
            'One or two days of leave next to a Sunday or a holiday. Tap one '
            'to check it.',
            style: dim),
      ));
      for (final i in _weekends) {
        children.add(_idea(i, weekend: true));
      }
    }

    children.add(const SectionTitle('Longest breaks you can take'));
    if (_breaks.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(
            'No break of three days or more in the next 45 days keeps every '
            'course at $min%. Attend a few more classes and look again.',
            style: dim),
      ));
    } else {
      for (final i in _breaks) {
        children.add(_idea(i, weekend: false));
      }
    }

    // ---- leave left in each course
    final sorted = [...courses]
      ..sort((a, b) => leaveLeft(a, min).compareTo(leaveLeft(b, min)));
    children.add(const SectionTitle('Leave left in each course'));
    children.add(Card(
      child: Column(children: [
        for (var n = 0; n < sorted.length; n++) ...[
          if (n > 0) const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                  child: Text(sorted[n].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium)),
              const SizedBox(width: 8),
              Text(
                  leaveLeft(sorted[n], min) < 0 ||
                          !meets(sorted[n].attended, sorted[n].held, min)
                      ? 'Below $min%'
                      : leaveLeft(sorted[n], min) == 0
                          ? 'None'
                          : classes(leaveLeft(sorted[n], min)),
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: leaveLeft(sorted[n], min) < 0 ||
                              !meets(sorted[n].attended, sorted[n].held, min)
                          ? tone.bad
                          : leaveLeft(sorted[n], min) == 0
                              ? tone.warn
                              : null)),
            ]),
          ),
        ],
      ]),
    ));

    // ---- days off already coming
    final coming = [
      for (final e in widget.calendar)
        if (e.dayOff &&
            e.kind != 'exam' &&
            !e.to.isBefore(today) &&
            e.from.isBefore(today.add(const Duration(days: 90))))
          e
    ];
    if (coming.isNotEmpty) {
      children.add(const SectionTitle('Days off already coming'));
      children.add(Card(
        child: Column(children: [
          for (var n = 0; n < coming.length; n++) ...[
            if (n > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              dense: true,
              title: Text(coming[n].title),
              trailing: Text(spanText(coming[n]), style: dim),
            ),
          ],
        ]),
      ));
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
      child: Text(
          'Counted to the end of each course. Where the timetable is not out '
          'yet, the app assumes a full day of $classesPerDay classes (09:00 to '
          '17:10), Monday to Saturday, and no classes on holidays, breaks and '
          'exam days from the academic calendar.',
          style: dim),
    ));

    return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28), children: children);
  }
}
