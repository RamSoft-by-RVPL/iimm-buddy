import 'package:flutter/material.dart';

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
      this.onShortName});

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final now = DateTime.now();
    final courses = [...snap.courses]
      ..sort((a, b) => leaveLeft(a, minPct).compareTo(leaveLeft(b, minPct)));
    final cutoff = now.subtract(const Duration(days: 2));
    final stale = [
      for (final x in snap.sessions)
        if (x.unmarked && x.date.isBefore(cutoff)) x
    ];
    final absent =
        snap.sessions.where((s) => !s.upcoming && s.status == 'Absent').length;
    final next = snap.next.where((s) => s.endsAt.isAfter(now)).toList();
    final below = courses.where((c) => statusColor(c, minPct) == bad).length;
    final tight = courses.where((c) => statusColor(c, minPct) == warn).length;
    final at = snap.syncedAt;
    final overall = below > 0 ? tone.bad : (tight > 0 ? tone.warn : tone.good);
    // The ring is about the total; the label under the name is about courses.
    final ring = meets(snap.attended, snap.held, minPct) ? tone.good : tone.bad;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        children: [
          // ---- where you stand
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (snap.percent / 100).clamp(0, 1),
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        color: ring,
                        backgroundColor: t.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Text(
                        '${snap.percent.toStringAsFixed(snap.percent >= 99.95 ? 0 : 1)}%',
                        style: t.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi, ${firstName(snap.studentName)}',
                            style: t.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                            '${snap.attended} of ${snap.held} classes attended',
                            style: t.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Pill(
                            below > 0
                                ? '$below ${below == 1 ? 'course' : 'courses'} below $minPct%'
                                : tight > 0
                                    ? 'No leave left in $tight ${tight == 1 ? 'course' : 'courses'}'
                                    : 'Every course is above $minPct%',
                            color: overall,
                            icon: below > 0
                                ? Icons.error_outline
                                : tight > 0
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline),
                      ]),
                ),
              ]),
            ),
          ),

          // ---- what is next
          if (next.isNotEmpty) ...[
            SectionTitle('Next class',
                trailing: onOpenTimetable == null
                    ? null
                    : InkWell(
                        onTap: onOpenTimetable,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text('Full timetable',
                              style: t.textTheme.labelLarge
                                  ?.copyWith(color: t.colorScheme.primary)),
                        ),
                      )),
            Card(
              child: Column(children: [
                InkWell(
                  onTap: () => showSkip(context, snap, next.first, minPct),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(next.first.course,
                                      style: t.textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${dayWord(next.first.date, now)}, '
                                      '${next.first.start} to ${next.first.end}'
                                      '${next.first.room.isEmpty ? '' : ' · Room ${next.first.room}'}',
                                      style: t.textTheme.bodyMedium?.copyWith(
                                          color:
                                              t.colorScheme.onSurfaceVariant)),
                                ]),
                          ),
                          const SizedBox(width: 8),
                          Pill(untilWord(next.first, now),
                              color: t.colorScheme.primary),
                        ]),
                  ),
                ),
                for (final n in next.skip(1).take(3)) ...[
                  const Divider(indent: 16, endIndent: 16),
                  InkWell(
                    onTap: () => showSkip(context, snap, n, minPct),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                              '${dayWord(n.date, now, short: true)} ${n.start}',
                              style: t.textTheme.bodySmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ),
                        Expanded(
                            child: Text(n.course,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodyMedium)),
                      ]),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tap a class to see what skipping it does.',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ),
                ),
              ]),
            ),
          ],

          if (exams != null) exams!,

          // ---- things to sort out
          if (stale.isNotEmpty || onOpenLeave != null) ...[
            const SectionTitle('To look at'),
            Card(
              child: Column(children: [
                if (stale.isNotEmpty)
                  Theme(
                    data: t.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Icon(Icons.pending_actions_outlined,
                          color: tone.warn),
                      title: Text(
                          '${stale.length} ${stale.length == 1 ? 'class' : 'classes'} not marked yet'),
                      subtitle: const Text(
                          'Counted as absent until the faculty marks them'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                      children: [
                        for (final n in stale)
                          InkWell(
                            onTap: () =>
                                showDispute(context, snap, n, fixEmail),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                      '${fmtDate(n.date)}, ${n.start} · ${n.course}',
                                      style: t.textTheme.bodyMedium),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.mail_outline,
                                      size: 18,
                                      color: t.colorScheme.onSurfaceVariant),
                                ),
                              ]),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'If you were present, tap a class to write to '
                              'the faculty.',
                              style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),
                if (stale.isNotEmpty && onOpenLeave != null)
                  const Divider(indent: 16, endIndent: 16),
                if (onOpenLeave != null)
                  ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: const Text('Absences and leave'),
                    subtitle: Text(absent == 0
                        ? 'No absences so far'
                        : '$absent ${absent == 1 ? 'absence' : 'absences'} · '
                            '$leaveCount with a reason noted'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onOpenLeave,
                  ),
              ]),
            ),
          ],

          // ---- each course
          SectionTitle('Courses',
              trailing: Text('Tightest first',
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant))),
          for (final c in courses)
            Card(
              child: InkWell(
                onTap: () => showCourse(context, c),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(c.name,
                                      style: t.textTheme.titleSmall
                                          ?.copyWith(height: 1.25))),
                              const SizedBox(width: 12),
                              Text(fmtPct(c.percent),
                                  style: t.textTheme.titleLarge?.copyWith(
                                      color: toneOf(context, c),
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                            ]),
                        const SizedBox(height: 10),
                        Meter(
                            value: c.percent,
                            min: minPct,
                            color: toneOf(context, c)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Pill(statusShort(c, minPct),
                              color: toneOf(context, c)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                [
                                  '${c.attended}/${c.held} attended',
                                  if (c.total != null) '${c.total} in course',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodySmall?.copyWith(
                                    color: t.colorScheme.onSurfaceVariant)),
                          ),
                        ]),
                        if (statusColor(c, minPct) == bad) ...[
                          const SizedBox(height: 8),
                          Text(statusText(c, minPct),
                              style: t.textTheme.bodySmall),
                        ],
                        if (c.parts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              for (final p in c.parts)
                                '${p.label} ${fmtPct(p.percent)}'
                            ].join('  ·  '),
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant),
                          ),
                        ],
                        if (c.pending > 0) ...[
                          const SizedBox(height: 4),
                          Text('${classes(c.pending)} not marked yet',
                              style: t.textTheme.bodySmall
                                  ?.copyWith(color: tone.warn)),
                        ],
                      ]),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Text(
                'Updated ${fmtDate(at)}, ${at.hour.toString().padLeft(2, '0')}:'
                '${at.minute.toString().padLeft(2, '0')} · Roll ${snap.roll} · '
                'The tick on each bar is the $minPct% you need.',
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  /// How the percentage moved class by class, and where it is heading.
  List<Widget> trend(ThemeData t, Course c) {
    final ids = c.parts.isEmpty ? {c.id} : {for (final p in c.parts) p.id};
    final held = [
      for (final s in snap.sessions)
        if (ids.contains(s.courseId) && !s.upcoming) s
    ];
    final points = runningPercent(
        [for (final s in held) s.status == 'Present' || s.status == 'Late']);
    final p = projection(c);
    return [
      if (points.length >= 3) ...[
        const SizedBox(height: 12),
        Text('So far', style: t.textTheme.labelLarge),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(
              painter: TrendPainter(points, minPct.toDouble(),
                  statusColor(c, minPct), t.colorScheme.outline)),
        ),
        Text('Each step is one class. The dashed line is $minPct%.',
            style: t.textTheme.bodySmall),
      ],
      if (p != null) ...[
        const SizedBox(height: 8),
        Text('At this rate you finish at ${fmtPct(p.$1)}. '
            'Attending every class from now: ${fmtPct(p.$2)}.'),
      ],
    ];
  }

  /// Status, absences, upcoming classes and course length of one course
  /// (or of one half of a combined course).
  List<Widget> details(BuildContext ctx, ThemeData t, Course c) => [
        Text(statusText(c, minPct)),
        if (c.pending > 0) ...[
          const SizedBox(height: 6),
          Text(
              '${classes(c.pending)} not marked yet. The site counts '
              'these as not attended until the faculty marks them.',
              style: t.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Text('Absent on', style: t.textTheme.labelLarge),
        Text(c.absences.isEmpty ? 'No absences' : datesText(c.absences)),
        const SizedBox(height: 12),
        Text('Coming up', style: t.textTheme.labelLarge),
        Text(c.upcoming.isEmpty
            ? 'Nothing scheduled yet'
            : datesText(c.upcoming)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(c.total == null
                ? 'Course length not known'
                : 'Course length: ${classes(c.total!)}'),
          ),
          TextButton(
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
            child: const Text('Change'),
          ),
        ]),
      ];

  void showCourse(BuildContext context, Course c) {
    final t = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.name, style: t.textTheme.titleLarge),
                if (c.faculty.isNotEmpty)
                  Text(c.faculty, style: t.textTheme.bodySmall),
                if (onShortName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final v = await askText(ctx,
                            title: 'Short name',
                            initial: shortNames[c.name] ?? '',
                            maxLength: 12,
                            help: 'For example DSA or LAC. Used in class '
                                'reminders and on the home screen widget, '
                                'where the full name does not fit. Leave '
                                'empty to use the full name.');
                        if (v != null) {
                          onShortName!(c, v);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Pill(
                            shortNames[c.name] == null
                                ? 'Add a short name'
                                : 'Short name: ${shortNames[c.name]}',
                            icon: Icons.edit_outlined,
                            outlined: shortNames[c.name] == null,
                            color: t.colorScheme.primary),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                ...trend(t, c),
                const SizedBox(height: 12),
                if (c.parts.isEmpty)
                  ...details(ctx, t, c)
                else ...[
                  Text('Theory and lab together',
                      style: t.textTheme.labelLarge),
                  Text('${fmtPct(c.percent)} · ${c.attended}/${c.held} attended'
                      '${c.total != null ? ' · ${c.total} in course' : ''}'),
                  Text(statusText(c, minPct)),
                  for (final p in c.parts) ...[
                    const Divider(height: 28),
                    Row(children: [
                      Expanded(
                          child: Text(p.label, style: t.textTheme.titleMedium)),
                      Text(fmtPct(p.percent),
                          style: t.textTheme.titleMedium?.copyWith(
                              color: statusColor(p, minPct),
                              fontWeight: FontWeight.w700)),
                    ]),
                    Text('${p.attended}/${p.held} attended',
                        style: t.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    ...details(ctx, t, p),
                  ],
                ],
              ]),
        ),
      ),
    );
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
