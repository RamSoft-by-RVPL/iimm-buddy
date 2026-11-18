import 'package:flutter/material.dart';

import 'acal.dart';
import 'crony_ui.dart';
import 'mascot.dart';
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
      this.calendar = const [],
      this.shortNames = const {}});
  final Map<String, String> shortNames;
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

  /// Taps on the calendar: the first picks a day, a later one stretches it
  /// into a range, any other starts again.
  void tapDay(DateTime d) => setState(() {
        final r = range;
        if (r != null && r.start == r.end && d.isAfter(r.start)) {
          range = DateTimeRange(start: r.start, end: d);
        } else if (r != null && r.start == d && r.end == d) {
          range = null;
        } else {
          range = DateTimeRange(start: d, end: d);
        }
      });

  /// What one day away costs: 0 nothing (no classes), 1 fine, 2 uses a
  /// last spare somewhere, 3 puts a course below the limit.
  Object? _costFor;
  final Map<DateTime, int> _cost = {};
  int cost(DateTime d) {
    final key = (widget.snap, widget.minPct, today);
    if (_costFor != key) {
      _costFor = key;
      _cost.clear();
    }
    return _cost.putIfAbsent(d, () {
      var missed = 0, worst = 1;
      for (final c in widget.snap.courses) {
        final i = holidayImpact(c, today, d, d, widget.minPct);
        missed += i.missed;
        if (i.missed == 0) continue;
        if (breaksCourse(i, widget.minPct)) {
          worst = 3;
        } else if (i.leaveAfter == 0 && worst < 2) {
          worst = 2;
        }
      }
      return missed == 0 ? 0 : worst;
    });
  }

  Widget calendar(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final r = range;
    final colors = {
      1: tone.good,
      2: tone.warn,
      3: tone.bad,
    };
    Widget cell(DateTime d) {
      final past = d.isBefore(today);
      final isToday = d == today;
      final c = past ? 0 : cost(d);
      final inRange = r != null && !d.isBefore(r.start) && !d.isAfter(r.end);
      final edge = r != null && (d == r.start || d == r.end);
      final wine =
          t.brightness == Brightness.dark ? Brand.wineDark : Brand.wine;
      return GestureDetector(
        onTap: past ? null : () => tapDay(d),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: edge
                ? wine
                : inRange
                    ? wine.withOpacity(0.12)
                    : null,
            border: isToday && !edge
                ? Border.all(color: t.colorScheme.outlineVariant, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${d.day}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: edge
                        ? Brand.wineInk
                        : past || d.weekday == DateTime.sunday
                            ? t.colorScheme.onSurfaceVariant.withOpacity(0.55)
                            : t.colorScheme.onSurface)),
            const SizedBox(height: 4),
            Dot(
                c == 0
                    ? Colors.transparent
                    : edge
                        ? Brand.wineInk
                        : colors[c]!,
                size: 5),
          ]),
        ),
      );
    }

    Widget key(Color c, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Dot(c, size: 6),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
        ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        child: Column(children: [
          Row(children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                  child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: t.colorScheme.onSurfaceVariant)))),
          ]),
          const SizedBox(height: 6),
          for (var w = 0; w < 5; w++)
            SizedBox(
              height: 50,
              child: Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                      child: cell(DateTime(
                          monday.year, monday.month, monday.day + w * 7 + i))),
              ]),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Wrap(spacing: 16, runSpacing: 6, children: [
              key(tone.good, 'Free'),
              key(tone.warn, 'Uses a last spare'),
              key(tone.bad, 'Breaks ${widget.minPct}%'),
            ]),
          ),
        ]),
      ),
    );
  }

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
    return InkWell(
      onTap: () =>
          setState(() => range = DateTimeRange(start: i.from, end: i.to)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fmtDate(i.from)} to ${fmtDate(i.to)}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15)),
              const SizedBox(height: 2),
              Text(
                  [
                    if (weekend) '${days(i.leave)} of leave',
                    'misses ${classes(i.missed)}',
                    if (holiday != null) holiday,
                    if (guess) 'estimate',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${i.days}',
                style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: picked ? tone.good : null)),
            Text(picked ? 'picked' : (i.days == 1 ? 'day' : 'days'),
                style: TextStyle(
                    fontSize: 11,
                    color:
                        picked ? tone.good : t.colorScheme.onSurfaceVariant)),
          ]),
        ]),
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
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text(
            until == null
                ? 'One day away puts a course below $min%.'
                : until == tomorrow
                    ? 'You can be away tomorrow, ${fmtDate(tomorrow)}.'
                    : 'You can be away until ${fmtDate(until)}.',
            style: TextStyle(
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: t.colorScheme.onSurface)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Text(
            until == null
                ? (_weekends.isEmpty && _breaks.isEmpty
                    ? 'Attend for a while before taking leave.'
                    : 'Attend the next few days and the dates below still work.')
                : '${days(until.difference(tomorrow).inDays + 1)} in a row and '
                    'every course stays at or above $min% by the end of term.',
            style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: t.colorScheme.onSurfaceVariant)),
      ),

      // ---- check given days
      calendar(context),
      if (r == null)
        Card(
          child: InkWell(
            onTap: pick,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                const Crony(mood: Mood.idle, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pick the days you will be away',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                            'Tap a day above, then a later one for a longer '
                            'trip. I add up the classes you would miss in '
                            'each course.',
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: t.colorScheme.onSurfaceVariant)),
                      ]),
                ),
              ]),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 0, 2),
          child: Row(children: [
            Expanded(
              child: Text(
                  '${fmtDate(r.start)}${r.end == r.start ? '' : ' to ${fmtDate(r.end)}'}'
                  ' · ${days(r.duration.inDays + 1)}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: pick, child: const Text('Change')),
            TextButton(
                onPressed: () => setState(() => range = null),
                child: const Text('Clear')),
          ]),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Crony(
                  mood: missed == 0 || hit.isEmpty ? Mood.happy : Mood.alarmed,
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    missed == 0
                        ? 'No classes on these days.'
                        : hit.isEmpty
                            ? 'Fine. Every course can still finish at $min% or above.'
                            : '${hit.length} ${hit.length == 1 ? 'course falls' : 'courses fall'} below $min%.',
                    style: TextStyle(
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: hit.isEmpty ? null : tone.bad)),
              ),
            ]),
            if (missed > 0 || off.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                  [
                    if (missed > 0) 'About ${classes(missed)} missed in all',
                    if (off.isNotEmpty)
                      '${off.map((e) => e.title).toSet().join(' and ')} '
                          '${off.map((e) => e.title).toSet().length == 1 ? 'falls' : 'fall'} in these days',
                  ].join('. '),
                  style: TextStyle(
                      fontSize: 14, color: t.colorScheme.onSurfaceVariant)),
            ],
            if (missed > 0) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('Course', style: dim)),
                SizedBox(
                    width: 56,
                    child:
                        Text('Misses', style: dim, textAlign: TextAlign.end)),
                SizedBox(
                    width: 74,
                    child: Text('After', style: dim, textAlign: TextAlign.end)),
              ]),
              for (final i in list)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color: t.colorScheme.outlineVariant
                                  .withOpacity(0.5)))),
                  child: Row(children: [
                    Expanded(
                        child: Text(codeOf(i.course.name, widget.shortNames),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600))),
                    SizedBox(
                        width: 56,
                        child: Text('${i.missed}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 15))),
                    SizedBox(
                        width: 74,
                        child: Text(fmtPct(i.percentAfter),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: !i.safe
                                    ? tone.bad
                                    : i.leaveAfter == 0
                                        ? tone.warn
                                        : tone.good))),
                  ]),
                ),
            ],
          ]),
        ),
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
      children.add(GroupCard(children: [
        for (final i in _weekends) _idea(i, weekend: true),
      ]));
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
      children.add(GroupCard(children: [
        for (final i in _breaks) _idea(i, weekend: false),
      ]));
    }

    // ---- leave left in each course
    final sorted = [...courses]
      ..sort((a, b) => leaveLeft(a, min).compareTo(leaveLeft(b, min)));
    children.add(const SectionTitle('Leave left in each course'));
    children.add(GroupCard(children: [
      for (final c in sorted)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(children: [
            Expanded(
                child: Text(codeOf(c.name, widget.shortNames),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Text(
                leaveLeft(c, min) < 0 || !meets(c.attended, c.held, min)
                    ? 'Below $min%'
                    : leaveLeft(c, min) == 0
                        ? 'None left'
                        : '${classes(leaveLeft(c, min))} left',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        leaveLeft(c, min) < 0 || !meets(c.attended, c.held, min)
                            ? tone.bad
                            : leaveLeft(c, min) == 0
                                ? tone.warn
                                : t.colorScheme.onSurfaceVariant)),
          ]),
        ),
    ]));

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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: children);
  }
}
