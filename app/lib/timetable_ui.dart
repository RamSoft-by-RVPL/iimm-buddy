import 'package:flutter/material.dart';

import 'absence.dart';
import 'acal.dart';
import 'attendance_ui.dart' show NowCard;
import 'crony_ui.dart';
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
      this.shortNames = const {},
      this.onOpenDeadline});
  final Map<String, String> shortNames;
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

  /// The day highlighted in the strip, 0 = Monday. Opens on today.
  int picked = DateTime.now().weekday - 1;
  final dayKeys = List.generate(7, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    // Open on today, not on Monday.
    WidgetsBinding.instance.addPostFrameCallback((_) => jump(picked, 0));
  }

  void jump(int i, int ms) {
    final c = dayKeys[i].currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(c,
        alignment: 0,
        duration: ms == 0 || calm(context)
            ? Duration.zero
            : Duration(milliseconds: ms),
        curve: const Cubic(0.23, 1, 0.32, 1));
  }

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  Widget classTile(BuildContext context, ClassSlot s, DateTime now,
      {bool next = false}) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final live = !s.startsAt.isAfter(now) && s.endsAt.isAfter(now);
    final soon = next && s.startsAt.difference(now).inHours < 12;
    final wine = t.brightness == Brightness.dark ? Brand.wineDark : Brand.wine;
    final (label, color, filled) = switch (s) {
      _ when live => ('Now', wine, true),
      _ when soon => ('In ${NowCard.countdown(s, now)}', wine, true),
      _ when s.upcoming => ('Upcoming', t.colorScheme.onSurfaceVariant, false),
      _ when s.fromSheet => (
          'To be updated',
          t.colorScheme.onSurfaceVariant,
          false
        ),
      _ when s.status == 'Present' => ('Present', tone.good, false),
      _ when s.status == 'Late' => ('Late', tone.warn, false),
      _ when s.status == 'Absent' => ('Absent', tone.bad, false),
      _ => ('Not marked', tone.warn, false),
    };
    final onTap = s.upcoming
        ? () => showSkip(context, widget.snap, s, widget.minPct,
            shortNames: widget.shortNames)
        : canDispute(s)
            ? () => showDispute(context, widget.snap, s, widget.fixEmail)
            : null;
    final c = widget.snap.courseOf(s);
    final mono = TextStyle(
        fontFamily: 'GeistMono',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: t.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 56,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.start,
                  style: mono.copyWith(color: t.colorScheme.onSurface)),
              const SizedBox(height: 2),
              Text(s.end, style: mono.copyWith(fontSize: 11)),
            ]),
          ),
        ),
        Expanded(
          child: Material(
            color: t.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: live || soon
                    ? BorderSide(color: wine, width: 1.6)
                    : BorderSide.none),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              c == null
                                  ? s.course
                                  : codeOf(c.name, widget.shortNames),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 2),
                          Text(
                              [
                                if (s.fromSheet) 'Not on portal yet',
                                if (s.room.isNotEmpty) 'Room ${s.room}',
                                if (c != null &&
                                    codeOf(c.name, widget.shortNames) != c.name)
                                  c.name,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: filled
                          ? color
                          : s.fromSheet && !s.upcoming
                              ? null
                              : color.withOpacity(0.12),
                      border: s.fromSheet && !s.upcoming
                          ? Border.all(
                              color: t.colorScheme.outline.withOpacity(0.6))
                          : null,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: filled ? Brand.wineInk : color)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// The current time as a line across the day.
  Widget nowLine(BuildContext context, DateTime now) {
    final t = Theme.of(context);
    final c = t.brightness == Brightness.dark ? Brand.lime : Brand.wine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Text(hhmm(now),
              style: TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c)),
        ),
        Dot(c, size: 8),
        Expanded(child: Container(height: 1.5, color: c)),
      ]),
    );
  }

  Widget dueTile(BuildContext context, Deadline x) {
    final t = Theme.of(context);
    final hh = x.due.hour.toString().padLeft(2, '0');
    final mm = x.due.minute.toString().padLeft(2, '0');
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(Icons.assignment_outlined, color: t.colorScheme.primary),
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
                fontWeight: FontWeight.w600,
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
            Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                  SheetHead(longDay(d),
                      subtitle: [
                        fmtDate(d),
                        if (slots.isNotEmpty)
                          '${slots.length} ${slots.length == 1 ? 'class' : 'classes'}',
                        if (ex.isNotEmpty)
                          '${ex.length} ${ex.length == 1 ? 'exam' : 'exams'}',
                        if (due.isNotEmpty) '${due.length} due',
                      ].join(' · '),
                      trailing: DateBlock(d)),
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
                    ? Brand.lime.withOpacity(0.38)
                    : offDay
                        ? tone.good.withOpacity(0.14)
                        : null,
            border: isToday
                ? Border.all(color: t.colorScheme.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
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
      Row(children: [
        IconButton(
            tooltip: 'Earlier month',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => monthOff--),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: InkWell(
            onTap: monthOff == 0 ? null : () => setState(() => monthOff = 0),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                  '${names[first.month - 1]} ${first.year}'
                  '${monthOff == 0 ? '' : ' · back to this month'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: monthOff == 0
                          ? t.colorScheme.onSurfaceVariant
                          : t.colorScheme.primary)),
            ),
          ),
        ),
        IconButton(
            tooltip: 'Later month',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => monthOff++),
            icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 6),
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
          key(Brand.lime.withOpacity(0.6), 'Exam day', square: true),
          key(tone.bad.withOpacity(0.25), 'Day with an absence', square: true),
          if (widget.calendar.isNotEmpty)
            key(tone.good.withOpacity(0.35), 'Holiday or break', square: true),
        ]),
      ),
      Card(
        margin: const EdgeInsets.only(top: 12),
        child: ListTile(
          leading: const IconTile(Icons.insights_outlined),
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
        padding: const EdgeInsets.only(bottom: 10),
        child: Segmented(
            options: const ['Week', 'Month'],
            selected: byMonth ? 1 : 0,
            onChanged: (v) => setState(() => byMonth = v == 1)),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [viewSwitch(), ...monthView(context)]),
      );
    }

    // The switch and the days stay put; the chosen day scrolls under them.
    const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i)
    ];
    bool busy(DateTime d) =>
        slotsOn(d).isNotEmpty ||
        widget.exams.any((x) => day(x.at) == d) ||
        widget.deadlines.any((x) => day(x.due) == d) ||
        termOn(d).isNotEmpty;
    // Sunday only when something is on it.
    final count = busy(days[6]) ? 7 : 6;
    final pick = picked.clamp(0, count - 1);
    final dark = t.brightness == Brightness.dark;

    final pinned = <Widget>[
      viewSwitch(),
      Row(children: [
        IconButton(
            tooltip: 'Earlier week',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
                  week--;
                  picked = 0;
                }),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: InkWell(
            onTap: week == 0
                ? null
                : () => setState(() {
                      week = 0;
                      picked = now.weekday - 1;
                    }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                  '${week == 0 ? 'This week' : week == 1 ? 'Next week' : week == -1 ? 'Last week' : 'Week of ${fmtDate(monday)}'}'
                  ' · ${monday.day} to ${fmtDate(sunday).substring(4)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: week == 0
                          ? t.colorScheme.onSurfaceVariant
                          : t.colorScheme.primary)),
            ),
          ),
        ),
        IconButton(
            tooltip: 'Later week',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
                  week++;
                  picked = 0;
                }),
            icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Semantics(
                selected: i == pick,
                button: true,
                label: fmtDate(days[i]),
                child: GestureDetector(
                  onTap: () {
                    setState(() => picked = i);
                    jump(i, 320);
                  },
                  child: AnimatedContainer(
                    duration: calm(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == pick
                          ? (dark ? const Color(0xFF3A373E) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: i == pick && !dark
                          ? const [
                              BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 1))
                            ]
                          : null,
                    ),
                    child: Column(children: [
                      Text(short[i],
                          style: TextStyle(
                              fontSize: 12,
                              color: t.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('${days[i].day}',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight:
                                  i == pick ? FontWeight.w700 : FontWeight.w500,
                              color: days[i] == today
                                  ? t.colorScheme.primary
                                  : t.colorScheme.onSurface)),
                      const SizedBox(height: 3),
                      Dot(
                          busy(days[i])
                              ? t.colorScheme.onSurfaceVariant.withOpacity(0.6)
                              : Colors.transparent,
                          size: 4),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
    ];

    // Every day of the week in one list; the strip jumps to a day.
    final children = <Widget>[];
    var any = false;
    var sheetOnly = false;
    for (var i = 0; i < count; i++) {
      final d = days[i];
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
      final empty = slots.isEmpty && due.isEmpty && ex.isEmpty && term.isEmpty;
      any = any || !empty;
      final isToday = d == today;
      children.add(SectionTitle(
        key: dayKeys[i],
        isToday ? 'Today · ${fmtDate(d)}' : fmtDate(d),
        trailing: Text(
            slots.isEmpty
                ? ''
                : '${slots.length} ${slots.length == 1 ? 'class' : 'classes'}',
            style: t.textTheme.labelSmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ));
      if (empty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(
              horizon != null && d.isAfter(horizon)
                  ? 'Not published yet'
                  : 'No classes',
              style: TextStyle(
                  fontSize: 14, color: t.colorScheme.onSurfaceVariant)),
        ));
        continue;
      }
      for (final e in term) {
        children.add(termTile(context, e));
      }
      for (final x in ex) {
        children.add(examTile(context, x));
      }
      final firstNext =
          isToday ? slots.indexWhere((x) => x.endsAt.isAfter(now)) : -1;
      var lineDone = !isToday;
      for (final (n, x) in slots.indexed) {
        sheetOnly = sheetOnly || x.fromSheet;
        if (!lineDone && x.startsAt.isAfter(now)) {
          children.add(nowLine(context, now));
          lineDone = true;
        }
        children.add(Rise(
            index: n, child: classTile(context, x, now, next: n == firstNext)));
      }
      if (!lineDone && slots.isNotEmpty) children.add(nowLine(context, now));
      for (final x in due) {
        children.add(dueTile(context, x));
      }
    }

    if (!any) {
      final notOut = horizon != null && monday.isAfter(horizon);
      children
        ..clear()
        ..add(EmptyNote(
          icon: notOut ? Icons.hourglass_empty : Icons.event_available_outlined,
          title: notOut
              ? 'This week is not published yet'
              : 'No classes this week',
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: pinned),
      ),
      Expanded(
        child: GestureDetector(
          // A sideways swipe moves to the next or previous week.
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v.abs() < 300) return;
            setState(() {
              week += v < 0 ? 1 : -1;
              picked = 0;
            });
          },
          child: SingleChildScrollView(
            key: ValueKey(week),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children),
          ),
        ),
      ),
    ]);
  }
}
