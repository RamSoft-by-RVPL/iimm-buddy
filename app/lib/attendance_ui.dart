import 'package:flutter/material.dart';

import 'crony_ui.dart';
import 'mascot.dart';
import 'planner.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

Color statusColor(Course c, int minPct) {
  final left = leaveLeft(c, minPct);
  if (left < 0 || !meets(c.attended, c.held, minPct)) return bad;
  return left == 0 ? warn : good;
}

/// The same judgement in colours that read well in light and dark.
Color toneOf(BuildContext context, Course c, [int? minPct]) {
  final tone = Tone.of(context);
  final base = statusColor(c, minPct ?? _minFor(context));
  return base == bad ? tone.bad : (base == warn ? tone.warn : tone.good);
}

int _minFor(BuildContext context) =>
    context.findAncestorWidgetOfExactType<AttendanceTab>()?.minPct ?? 85;

/// The course's state in two or three words.
String statusShort(Course c, int minPct) {
  final left = leaveLeft(c, minPct);
  if (c.total != null && left < 0) return 'Over the limit';
  if (!meets(c.attended, c.held, minPct)) return 'Below $minPct%';
  if (left == 0) return 'No leave left';
  return 'Can miss $left';
}

/// "Wed 18 Nov (2 classes), Fri 20 Nov": one entry per day.
String datesText(List<DateTime> dates) {
  final perDay = <String, int>{};
  for (final d in [...dates]..sort()) {
    perDay[fmtDate(d)] = (perDay[fmtDate(d)] ?? 0) + 1;
  }
  return [
    for (final e in perDay.entries)
      e.value == 1 ? e.key : '${e.key} (${e.value} classes)'
  ].join(', ');
}

/// "Arjun" from "ARJUN KUMAR SHAH".
String firstName(String full) {
  final w = full.trim().split(RegExp(r'\s+')).first;
  return w.isEmpty
      ? 'there'
      : w[0].toUpperCase() + w.substring(1).toLowerCase();
}

/// "Today", "Tomorrow" or the weekday.
String dayWord(DateTime d, DateTime now, {bool short = false}) {
  final days = DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return short ? 'Tmrw' : 'Tomorrow';
  return short ? fmtDate(d).split(' ').first : fmtDate(d);
}

/// How long until a class: "Now", "in 25 min", "in 3 h", "Tomorrow".
String untilWord(ClassSlot s, DateTime now) {
  final gap = s.startsAt.difference(now);
  if (gap.isNegative) return 'Now';
  if (gap.inMinutes < 60) {
    return 'in ${gap.inMinutes < 1 ? 1 : gap.inMinutes} min';
  }
  if (gap.inHours < 24) {
    final m = gap.inMinutes % 60;
    return gap.inHours < 6 && m >= 10
        ? 'in ${gap.inHours} h $m min'
        : 'in ${gap.inHours} h';
  }
  return 'in ${gap.inDays} ${gap.inDays == 1 ? 'day' : 'days'}';
}

/// A strip needs the course length, and stays legible up to about 90 classes.
bool punchable(Course c) =>
    c.total != null && c.total! >= c.held && c.total! <= 90;

/// The ticks for [PunchStrip]: each held class in order, then the classes
/// still to come, the last ones marked as those that can still be missed.
List<Punch> punchesOf(Course c, Snapshot snap, int minPct) {
  final ids = {c.id, for (final p in c.parts) p.id};
  final past = [
    for (final s in snap.sessions)
      if (!s.upcoming &&
          !s.fromSheet &&
          !s.cancelled &&
          ids.contains(s.courseId))
        s.status
  ];
  final held = past.length == c.held
      ? [
          for (final st in past)
            st == 'Present'
                ? Punch.attended
                : st == 'Absent'
                    ? Punch.missed
                    : Punch.pending
        ]
      : [
          for (var i = 0; i < c.attended; i++) Punch.attended,
          for (var i = 0; i < c.missed - c.pending; i++) Punch.missed,
          for (var i = 0; i < c.pending; i++) Punch.pending,
        ];
  final rest = (c.total ?? c.held) - c.held;
  final spare = leaveLeft(c, minPct).clamp(0, rest);
  return [
    ...held,
    for (var i = 0; i < rest - spare; i++) Punch.due,
    for (var i = 0; i < spare; i++) Punch.spare,
  ];
}

/// The next class, on a pink card: when it starts and whether it can be skipped.
class NowCard extends StatelessWidget {
  const NowCard(
      {super.key,
      required this.slot,
      required this.course,
      required this.minPct,
      required this.now,
      required this.onSkip,
      this.shortName});
  final ClassSlot slot;
  final Course? course;
  final String? shortName;
  final int minPct;
  final DateTime now;
  final VoidCallback onSkip;

  /// "25 min", "3h 20m", "Tmrw": short enough for the big figure.
  static String countdown(ClassSlot s, DateTime now) {
    final gap = s.startsAt.difference(now);
    if (gap.isNegative) return 'Now';
    if (gap.inMinutes < 60) {
      return '${gap.inMinutes < 1 ? 1 : gap.inMinutes} min';
    }
    if (gap.inHours < 6) {
      final m = gap.inMinutes % 60;
      return m == 0 ? '${gap.inHours}h' : '${gap.inHours}h ${m}m';
    }
    if (gap.inHours < 24 && s.date.day == now.day) return '${gap.inHours}h';
    return dayWord(s.date, now, short: true);
  }

  /// Figures in mono, units small and muted; a day name stays whole.
  static List<TextSpan> countdownSpans(ClassSlot s, DateTime now) {
    final text = countdown(s, now);
    if (!text.startsWith(RegExp(r'\d'))) {
      return [
        TextSpan(text: text, style: const TextStyle(fontFamily: 'Geist'))
      ];
    }
    const unit = TextStyle(
        fontFamily: 'Geist',
        fontSize: 16,
        color: Brand.onPinkMuted,
        letterSpacing: 0);
    return [
      for (final m in RegExp(r'(\d+)\s*([a-z]+)').allMatches(text)) ...[
        if (m.start > 0) const TextSpan(text: ' ', style: unit),
        TextSpan(text: m.group(1)),
        TextSpan(text: m.group(2) == 'min' ? ' min' : m.group(2), style: unit),
      ]
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = course;
    final short = shortName?.trim() ?? '';
    final soon =
        slot.startsAt.difference(now).inHours < 24 && slot.date.day == now.day;
    final started = slot.startsAt.isBefore(now);
    const ink = Brand.onPink;
    const muted = Brand.onPinkMuted;
    return Semantics(
      container: true,
      label: 'Next class',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: Brand.sticker(context, radius: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(short.isEmpty ? slot.course : short,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: short.isEmpty
                            ? const TextStyle(
                                color: ink,
                                fontSize: 22,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.45)
                            : Brand.hand(46, color: ink, height: 0.95)),
                    const SizedBox(height: 8),
                    Text(
                        '${soon ? '' : '${dayWord(slot.date, now)}, '}'
                        '${slot.start} to ${slot.end}'
                        '${slot.room.isEmpty ? '' : ' · Room ${slot.room}'}',
                        style: const TextStyle(color: muted, fontSize: 14)),
                    if (slot.faculty.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(slot.faculty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 14)),
                    ],
                  ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (soon) ...[
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Brand.lemon,
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                              BorderSide(color: Brand.edge, width: 1.5)))),
                  const SizedBox(width: 6),
                ],
                Text(
                    started ? 'Under way' : (soon ? 'Starts in' : 'Next class'),
                    style: const TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: countdownSpans(slot, now)),
                  style: Brand.hand(34, color: ink, height: 1.1)),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(height: 2, color: const Color(0x381A1113)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: c == null || c.held == 0
                  ? const SizedBox.shrink()
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: fmtPct(c.percent),
                            style: const TextStyle(
                                color: ink, fontWeight: FontWeight.w600)),
                        TextSpan(text: ' here · ${statusShort(c, minPct)}'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onSkip,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                backgroundColor: Brand.lemon,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                side: const BorderSide(color: Brand.edge, width: 2),
                shape: const StadiumBorder(),
                textStyle: Brand.hand(17),
              ),
              child: const Text('What if I skip'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class AttendanceTab extends StatelessWidget {
  const AttendanceTab(
      {super.key,
      required this.snap,
      required this.minPct,
      required this.onRefresh,
      required this.onEditTotal,
      this.fixEmail = '',
      this.leaveCount = 0,
      this.onOpenLeave,
      this.onOpenTimetable,
      this.exams,
      this.shortNames = const {},
      this.onShortName,
      this.register = false,
      this.onOpenRegister});

  /// Shows the register (every course, class by class) instead of Today.
  final bool register;
  final VoidCallback? onOpenRegister;

  /// The "Exams and quizzes" block, built by the screen that owns the data.
  final Widget? exams;
  final Map<String, String> shortNames;
  final void Function(Course, String)? onShortName;
  final VoidCallback? onOpenTimetable;
  final int leaveCount;
  final VoidCallback? onOpenLeave;
  final String fixEmail;
  final Snapshot snap;
  final int minPct;
  final Future<void> Function() onRefresh;
  final void Function(Course, int?) onEditTotal;

  String code(Course c) => codeOf(c.name, shortNames);

  /// "A", "A and B", "A, B and C".
  String names(List<Course> l) {
    final c = [for (final x in l) code(x)];
    return c.length == 1
        ? c.first
        : '${c.take(c.length - 1).join(', ')} and ${c.last}';
  }

  bool isBelow(Course c) => statusColor(c, minPct) == bad;
  bool isTight(Course c) => statusColor(c, minPct) == warn;

  @override
  Widget build(BuildContext context) {
    final courses = [...snap.courses]..sort((a, b) {
        final x = (isBelow(a) ? -1000 : 0) + leaveLeft(a, minPct);
        final y = (isBelow(b) ? -1000 : 0) + leaveLeft(b, minPct);
        return x.compareTo(y);
      });
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: register
          ? _RegisterView(
              builder: (context, filter, setFilter) =>
                  registerList(context, courses, filter, setFilter))
          : today(context, courses),
    );
  }

  Widget today(BuildContext context, List<Course> courses) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 2));
    final stale = [
      for (final x in snap.sessions)
        if (x.unmarked && x.date.isBefore(cutoff)) x
    ];
    final absent =
        snap.sessions.where((s) => !s.upcoming && s.status == 'Absent').length;
    final next = snap.next.where((s) => s.endsAt.isAfter(now)).toList();
    final below = [
      for (final c in courses)
        if (isBelow(c)) c
    ];
    final tight = [
      for (final c in courses)
        if (isTight(c)) c
    ];
    final fine = courses.length - below.length - tight.length;
    final overallBad = !meets(snap.attended, snap.held, minPct);
    var i = 0;

    const strong = TextStyle(fontWeight: FontWeight.w600);
    final story = <InlineSpan>[
      const TextSpan(text: 'overall. '),
      if (below.isNotEmpty)
        TextSpan(
            text:
                '${names(below)} ${below.length == 1 ? 'is' : 'are'} below $minPct%',
            style: strong.copyWith(color: tone.bad)),
      if (below.isNotEmpty && tight.isNotEmpty) const TextSpan(text: ', and '),
      if (tight.isNotEmpty)
        TextSpan(
            text:
                '${names(tight)} ${tight.length == 1 ? 'needs' : 'need'} every class',
            style: strong),
      if (tight.isNotEmpty) const TextSpan(text: ' until the end of term'),
      if (below.isNotEmpty || tight.isNotEmpty) const TextSpan(text: '. '),
      TextSpan(
          text: courses.isEmpty
              ? ''
              : below.isEmpty && tight.isEmpty
                  ? 'Every course has leave to spare.'
                  : fine == 0
                      ? ''
                      : 'The other ${countWord(fine)} ${fine == 1 ? 'is' : 'are'} on track.'),
    ];

    final needs = <Widget>[
      for (final c in below)
        RowItem(
          dot: tone.bad,
          title: '${code(c)} is below $minPct%',
          note: () {
            final n = classesToRecover(c, minPct);
            if (c.total != null && leaveLeft(c, minPct) < 0) {
              return 'Over the leave limit for this course';
            }
            return n <= 0
                ? statusShort(c, minPct)
                : n == 1
                    ? 'Attend the next class to get back'
                    : 'Attend all of the next $n classes';
          }(),
          value: fmtPct(c.percent),
          valueColor: tone.bad,
          onTap: () => showCourse(context, c),
        ),
      for (final c in tight)
        RowItem(
          dot: tone.warn,
          title: '${code(c)} has no leave left',
          note: 'Go to every class from now',
          value: fmtPct(c.percent),
          onTap: () => showCourse(context, c),
        ),
      if (stale.isNotEmpty)
        RowItem(
          dot: tone.warn,
          title: '${classes(stale.length)} not marked yet',
          note: 'Counted as absent until marked. Tap to ask for a fix',
          onTap: () => showStale(context, stale),
        ),
      if (below.isEmpty && tight.isEmpty && stale.isEmpty)
        const RowItem(
          leading: Crony(mood: Mood.happy, size: 34),
          title: 'Nothing needs you',
          note: 'Every course is on track',
        ),
      if (onOpenLeave != null)
        RowItem(
          title: 'Absences and leave',
          note: absent == 0
              ? 'No absences so far'
              : '$absent ${absent == 1 ? 'absence' : 'absences'} · '
                  '$leaveCount with a reason noted',
          onTap: onOpenLeave,
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        // ---- what is next
        if (next.isNotEmpty) ...[
          Rise(
            index: i++,
            child: NowCard(
                slot: next.first,
                course: snap.courseOf(next.first),
                shortName: code(snap.courseOf(next.first) ??
                    Course(
                        id: '', name: next.first.course, held: 0, attended: 0)),
                minPct: minPct,
                now: now,
                onSkip: () => showSkip(context, snap, next.first, minPct,
                    shortNames: shortNames)),
          ),
        ],

        // ---- where you stand
        Rise(
          index: i++,
          child: Card(
            child: InkWell(
              onTap: onOpenRegister,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          [
                            if (snap.studentName.isNotEmpty)
                              'Hi, ${firstName(snap.studentName)}',
                            '${snap.attended} of ${snap.held} classes attended',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: t.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      CountUp(snap.percent,
                          style: TextStyle(
                              fontFamily: 'Schoolbell',
                              fontSize: 58,
                              height: 1,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                              color: overallBad
                                  ? tone.bad
                                  : t.colorScheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      const SizedBox(height: 10),
                      Text.rich(TextSpan(children: story),
                          style: TextStyle(
                              fontSize: 15,
                              height: 1.45,
                              color: t.colorScheme.onSurfaceVariant)),
                      if (courses.length > 1) ...[
                        const SizedBox(height: 16),
                        MiniBars(
                            courses: courses.toList()
                              ..sort((a, b) => snap.courses
                                  .indexOf(a)
                                  .compareTo(snap.courses.indexOf(b))),
                            minPct: minPct,
                            label: code),
                      ],
                    ]),
              ),
            ),
          ),
        ),

        // ---- what needs doing
        Rise(index: i++, child: const SectionTitle('Needs you')),
        Rise(index: i++, child: GroupCard(children: needs)),

        // ---- coming up after the next class
        if (next.length > 1) ...[
          Rise(
            index: i++,
            child: SectionTitle('Later',
                trailing: onOpenTimetable == null
                    ? null
                    : InkWell(
                        onTap: onOpenTimetable,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text('Timetable',
                              style: t.textTheme.labelLarge
                                  ?.copyWith(color: t.colorScheme.primary)),
                        ),
                      )),
          ),
          Rise(
            index: i++,
            child: GroupCard(children: [
              for (final n in next.skip(1).take(3))
                InkWell(
                  onTap: () => showSkip(context, snap, n, minPct,
                      shortNames: shortNames),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                    child: Row(children: [
                      SizedBox(
                        width: 86,
                        child: Text(
                            '${dayWord(n.date, now, short: true)} ${n.start}',
                            style: TextStyle(
                                fontFamily: 'GeistMono',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: t.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                          child: Text(
                              snap.courseOf(n) == null
                                  ? n.course
                                  : code(snap.courseOf(n)!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600))),
                      if (n.room.isNotEmpty)
                        Text('Room ${n.room}',
                            style: TextStyle(
                                fontSize: 13,
                                color: t.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ),
            ]),
          ),
        ],

        if (exams != null) Rise(index: i++, child: exams!),
      ],
    );
  }

  /// Classes not marked yet, each one leading to a correction email.
  void showStale(BuildContext context, List<ClassSlot> stale) {
    final t = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: t.colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text('Not marked yet',
                      style: TextStyle(
                          fontFamily: 'Schoolbell',
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                      'These count as absent until the faculty marks them. If '
                      'you were present, tap one to write to the faculty.',
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: t.colorScheme.onSurfaceVariant)),
                ),
                GroupCard(children: [
                  for (final n in stale)
                    RowItem(
                      title: n.course,
                      note: '${fmtDate(n.date)}, ${n.start}',
                      onTap: () => showDispute(context, snap, n, fixEmail),
                    ),
                ]),
              ]),
        ),
      ),
    );
  }

  List<Widget> registerList(BuildContext context, List<Course> courses,
      int filter, ValueChanged<int> setFilter) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final shown = filter == 0
        ? courses
        : [
            for (final c in courses)
              if (statusColor(c, minPct) != good || leaveLeft(c, minPct) <= 1) c
          ];
    final strips = courses.every(punchable);
    Widget key(Color c, String label, {bool outline = false}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 12,
              decoration: BoxDecoration(
                  color: outline ? null : c,
                  border: outline ? Border.all(color: c) : null,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
        ]);
    return [
      Segmented(
          options: ['All ${countWord(courses.length)}', 'Needs attention'],
          selected: filter,
          onChanged: setFilter),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Crony(mood: Mood.happy, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                    'Nothing needs attention. Every course has leave to spare.',
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: t.colorScheme.onSurfaceVariant)),
              ),
            ]),
          ),
        )
      else
        GroupCard(children: [
          for (final (n, c) in shown.indexed)
            Rise(
              index: n,
              child: InkWell(
                onTap: () => showCourse(context, c),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(code(c),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.45)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: code(c) == c.name
                                    ? const SizedBox.shrink()
                                    : Text(c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: t
                                                .colorScheme.onSurfaceVariant)),
                              ),
                              const SizedBox(width: 10),
                              Text(fmtPct(c.percent),
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.45,
                                      color: isBelow(c) ? tone.bad : null,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                            ]),
                        const SizedBox(height: 11),
                        punchable(c)
                            ? PunchStrip(punchesOf(c, snap, minPct))
                            : Meter(
                                value: c.percent,
                                min: minPct,
                                color: toneOf(context, c, minPct)),
                        const SizedBox(height: 9),
                        Row(children: [
                          Text(statusShort(c, minPct),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isBelow(c)
                                      ? tone.bad
                                      : isTight(c)
                                          ? tone.warn
                                          : t.colorScheme.onSurfaceVariant)),
                          const Spacer(),
                          Text(
                              '${c.attended} of ${c.held}'
                              '${c.total != null ? ' · ${c.total} in course' : ''}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ]),
                        if (c.parts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                              [
                                for (final p in c.parts)
                                  '${p.label} ${fmtPct(p.percent)}'
                              ].join('  ·  '),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ],
                        if (c.pending > 0) ...[
                          const SizedBox(height: 4),
                          Text('${classes(c.pending)} not marked yet',
                              style: TextStyle(fontSize: 12, color: tone.warn)),
                        ],
                      ]),
                ),
              ),
            ),
        ]),
      const SizedBox(height: 14),
      if (strips)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            key(t.colorScheme.onSurface, 'Attended'),
            key(tone.bad, 'Missed'),
            key(t.colorScheme.outline, 'Still to come', outline: true),
            key(t.brightness == Brightness.dark ? Brand.lemon : Brand.lemonDeep,
                'Can still miss'),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text(
            '${strips ? 'Each bar is one class. ' : 'The tick on each bar is the $minPct% you need. '}'
            'Updated ${fmtDate(snap.syncedAt)}, ${hhmm(snap.syncedAt)} · Roll ${snap.roll}',
            style:
                TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
      ),
    ];
  }

  /// Status, absences, upcoming classes and course length of one course
  /// (or of one half of a combined course).
  List<Widget> details(BuildContext ctx, Course c, {String? heading}) {
    final t = Theme.of(ctx);
    return [
      if (heading != null)
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 2),
          child: Row(children: [
            Expanded(
                child: Text(heading,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600))),
            Text('${fmtPct(c.percent)} · ${c.attended}/${c.held}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isBelow(c) ? Tone.of(ctx).bad : null)),
          ]),
        ),
      InfoRow('Where it stands', Text(statusText(c, minPct))),
      if (c.pending > 0)
        InfoRow(
            'Not marked',
            Text('${classes(c.pending)}. The site counts these as not '
                'attended until the faculty marks them.')),
      InfoRow('Absent on',
          Text(c.absences.isEmpty ? 'No absences' : datesText(c.absences))),
      InfoRow(
          'Coming up',
          Text(c.upcoming.isEmpty
              ? 'Nothing scheduled yet'
              : datesText(c.upcoming.take(6).toList()) +
                  (c.upcoming.length > 6
                      ? ' and ${c.upcoming.length - 6} more'
                      : ''))),
      InfoRow(
        'Course length',
        Text(c.total == null ? 'Not known' : classes(c.total!)),
        action: TextButton(
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () async {
            final n = await askNumber(ctx,
                title:
                    'Classes in ${c.label.isEmpty ? 'this course' : 'the ${c.label.toLowerCase()} part'}',
                initial: c.total ?? c.held,
                min: c.held,
                max: 200,
                help: 'The app works this out from the course hours '
                    '(90 minutes per class). Change it if it is wrong.');
            if (n != null) {
              onEditTotal(c, n);
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: Text('Change', style: TextStyle(color: t.colorScheme.primary)),
        ),
      ),
    ];
  }

  void showCourse(BuildContext context, Course c) {
    openCourseSheet(context,
        course: c,
        snap: snap,
        minPct: minPct,
        shortNames: shortNames,
        extra: (ctx) => [
              const SizedBox(height: 6),
              if (onShortName != null)
                InfoRow(
                  'Short name',
                  Text(shortNames[c.name] ?? 'Not set, shown as ${code(c)}'),
                  action: TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () async {
                      final v = await askText(ctx,
                          title: 'Short name',
                          initial: shortNames[c.name] ?? '',
                          maxLength: 12,
                          help: 'For example DSA or LAC. Used across the app, '
                              'in class reminders and on the home screen '
                              'widget. Leave empty to use ${codeOf(c.name)}.');
                      if (v != null) {
                        onShortName!(c, v);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    child: Text('Change',
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.primary)),
                  ),
                ),
              if (c.parts.isEmpty)
                ...details(ctx, c)
              else ...[
                InfoRow(
                    'Theory and lab together',
                    Text(
                        '${fmtPct(c.percent)} · ${c.attended}/${c.held} attended'
                        '${c.total != null ? ' · ${c.total} in course' : ''}. '
                        '${statusText(c, minPct)}')),
                for (final p in c.parts) ...details(ctx, p, heading: p.label),
              ],
            ]);
  }
}

/// Keeps the register's filter while the tab is open.
class _RegisterView extends StatefulWidget {
  const _RegisterView({required this.builder});
  final List<Widget> Function(BuildContext, int, ValueChanged<int>) builder;

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  int filter = 0;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children:
            widget.builder(context, filter, (v) => setState(() => filter = v)),
      );
}

/// One small column per course: how full it is, red when below the limit.
class MiniBars extends StatelessWidget {
  const MiniBars(
      {super.key,
      required this.courses,
      required this.minPct,
      required this.label});
  final List<Course> courses;
  final int minPct;
  final String Function(Course) label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    double fill(double p) => ((p - 50) / 50).clamp(0.08, 1.0);
    final mark = fill(minPct.toDouble());
    return Row(children: [
      for (final (i, c) in courses.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Column(children: [
            SizedBox(
              height: 44,
              child: LayoutBuilder(builder: (context, box) {
                final isBad = statusColor(c, minPct) == bad;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: calm(context) ? 1 : 0, end: 1),
                  duration: Duration(milliseconds: 600 + i * 60),
                  curve: const Cubic(0.23, 1, 0.32, 1),
                  builder: (_, v, __) => Stack(children: [
                    Container(
                        decoration: BoxDecoration(
                            color: t.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6))),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: box.maxHeight * fill(c.percent) * v,
                      child: Container(
                          decoration: BoxDecoration(
                              color: isBad ? tone.bad : t.colorScheme.onSurface,
                              borderRadius: BorderRadius.circular(6))),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: box.maxHeight * mark,
                      height: 1.5,
                      child: Container(color: t.colorScheme.surface),
                    ),
                  ]),
                );
              }),
            ),
            const SizedBox(height: 6),
            Text(label(c),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                    fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]
    ]);
  }
}

/// Line of the running attendance percentage with the minimum marked.
class TrendPainter extends CustomPainter {
  TrendPainter(this.points, this.min, this.color, this.grid);
  final List<double> points;
  final double min;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    var low = min;
    for (final p in points) {
      if (p < low) low = p;
    }
    low = (low - 5).clamp(0, 100).toDouble();
    double y(double pct) => size.height * (1 - (pct - low) / (100 - low));
    double x(int i) => size.width * i / (points.length - 1);

    final dash = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 10) {
      canvas.drawLine(Offset(dx, y(min)), Offset(dx + 5, y(min)), dash);
    }
    final path = Path()..moveTo(0, y(points.first));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(
        Offset(size.width, y(points.last)), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.min != min ||
      oldDelegate.color != color;
}
