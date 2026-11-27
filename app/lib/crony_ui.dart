// Pieces of the Crony look shared by several screens: grouped cards, the
// segmented switch, counting numbers and the course sheet with the skip
// simulator.

import 'package:flutter/material.dart';

import 'mascot.dart';
import 'planner.dart';
import 'site.dart';
import 'faculty.dart';
import 'theme.dart';
import 'ui_common.dart';

const _small = {'and', 'for', 'with', 'of', 'the', 'in', 'to', 'on', 'a', '&'};

/// "PBM" for "Product and Brand Management": the student's own short name if
/// set, else the initials of the main words.
String codeOf(String name, [Map<String, String> shortNames = const {}]) {
  final own = shortNames[name]?.trim() ?? '';
  if (own.isNotEmpty) return own;
  final words = name
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .split(RegExp(r'[\s\-:,/]+'))
      .where((w) => w.isNotEmpty && !_small.contains(w.toLowerCase()))
      .toList();
  if (words.length < 2) return name;
  final code = words.map((w) => w[0].toUpperCase()).join();
  return code.length > 7 ? name : code;
}

/// "two", "five": small counts read better as words in a sentence.
String countWord(int n) => n >= 0 && n <= 10
    ? const [
        'no',
        'one',
        'two',
        'three',
        'four',
        'five',
        'six',
        'seven',
        'eight',
        'nine',
        'ten'
      ][n]
    : '$n';

/// "Tuesday 17 Nov".
String longDay(DateTime d) => '${const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ][d.weekday - 1]} '
    '${fmtDate(d).split(' ').skip(1).join(' ')}';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

bool calm(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// The large two-line title used at the top of each tab.
class BigTitle extends StatelessWidget {
  const BigTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Schoolbell',
                  fontSize: 29,
                  height: 1.15,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                  color: t.colorScheme.onSurface)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w400,
                      color: t.colorScheme.onSurfaceVariant)),
            ),
        ]);
  }
}

/// A card whose rows are split by hairlines, like a settings group.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: line),
          c,
        ]
      ]),
    );
  }
}

/// Two or three options in a pill-shaped track, the chosen one raised.
class Segmented extends StatelessWidget {
  const Segmented(
      {super.key,
      required this.options,
      required this.selected,
      required this.onChanged});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: calm(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: const Cubic(0.23, 1, 0.32, 1),
            left: w * selected,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF3A373E) : Colors.white,
                borderRadius: BorderRadius.circular(11),
                boxShadow: dark
                    ? null
                    : const [
                        BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 6,
                            offset: Offset(0, 1))
                      ],
              ),
            ),
          ),
          Row(children: [
            for (final (i, o) in options.indexed)
              Expanded(
                child: Semantics(
                  selected: i == selected,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => onChanged(i),
                    child: Center(
                      child: Text(o,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: i == selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: i == selected
                                  ? t.colorScheme.onSurface
                                  : t.colorScheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// A percentage that counts up to its value the first time it is shown.
class CountUp extends StatelessWidget {
  const CountUp(this.value,
      {super.key, required this.style, this.suffix = '%'});
  final double value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    String text(double v) => '${v.toStringAsFixed(v >= 99.95 ? 0 : 1)}$suffix';
    if (calm(context)) return Text(text(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: (value - 12).clamp(0, 100).toDouble(), end: value),
      duration: const Duration(milliseconds: 700),
      curve: const Cubic(0.23, 1, 0.32, 1),
      builder: (_, v, __) => Text(text(v), style: style),
    );
  }
}

/// Slides and fades a child in, [index] steps after the first one.
class Rise extends StatelessWidget {
  const Rise({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (calm(context)) return child;
    final delay = (index * 0.06).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (delay * 1000).round()),
      curve: Interval(delay / (0.42 + delay), 1,
          curve: const Cubic(0.23, 1, 0.32, 1)),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// A small dot, for list rows that carry a state.
class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// A tappable row inside a [GroupCard]: dot, title over a note, a value.
class RowItem extends StatelessWidget {
  const RowItem(
      {super.key,
      required this.title,
      this.note,
      this.dot,
      this.value,
      this.valueColor,
      this.leading,
      this.onTap});
  final String title;
  final String? note;
  final Color? dot;
  final String? value;
  final Color? valueColor;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          if (dot != null) ...[Dot(dot!), const SizedBox(width: 14)],
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15)),
              if (note != null && note!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(note!,
                    style: TextStyle(
                        fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            Text(value!,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? t.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ] else if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                size: 20, color: t.colorScheme.onSurfaceVariant),
          ],
        ]),
      ),
    );
  }
}

/// What missing [n] classes in a row does to [c], in a sentence. The
/// percentages are shown beside it, so the sentence is about what follows.
String skipLineN(Course c, int n, int minPct) {
  final after = Course(
      id: c.id,
      name: c.name,
      held: c.held + n,
      attended: c.attended,
      total: c.total);
  final left = leaveLeft(after, minPct);
  if (c.total != null && leaveLeft(c, minPct) < 0) {
    return 'Already over the limit. Do not skip.';
  }
  final above = meets(after.attended, after.held, minPct);
  if (c.total != null) {
    if (left < 0) return 'Over the limit: $minPct% is then out of reach.';
    final leave = left == 0
        ? 'No leave left after.'
        : '${classes(left)} of leave left after.';
    return above
        ? 'Still at or above $minPct%. $leave'
        : 'Below $minPct% for a while, but still within leave. $leave';
  }
  return above
      ? 'Still at or above $minPct%.'
      : 'Below $minPct%. You would need '
          '${classes(classesToRecover(after, minPct))} in a row to recover.';
}

/// The course sheet: where the course stands, how it got there, and what
/// skipping does. [slot] is the class being thought about, if any.
class CourseSheet extends StatefulWidget {
  const CourseSheet(
      {super.key,
      required this.course,
      required this.snap,
      required this.minPct,
      this.slot,
      this.shortNames = const {},
      this.extra = const []});
  final Course course;
  final Snapshot snap;
  final int minPct;
  final ClassSlot? slot;
  final Map<String, String> shortNames;

  /// More rows under the simulator (absences, course length and so on).
  final List<Widget> extra;

  @override
  State<CourseSheet> createState() => _CourseSheetState();
}

class _CourseSheetState extends State<CourseSheet> {
  int n = 1;

  Course get c => widget.course;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final min = widget.minPct;
    final left = leaveLeft(c, min);
    final below =
        !meets(c.attended, c.held, min) || (c.total != null && left < 0);
    final remaining = c.total == null ? 10 : (c.total! - c.held).clamp(1, 20);
    final after = Course(
        id: c.id,
        name: c.name,
        held: c.held + n,
        attended: c.attended,
        total: c.total);
    final leftAfter = leaveLeft(after, min);
    final mood = left < 0
        ? Mood.alarmed
        : leftAfter < 0
            ? Mood.alarmed
            : leftAfter == 0
                ? Mood.worried
                : Mood.happy;
    final ids = c.parts.isEmpty ? {c.id} : {for (final p in c.parts) p.id};
    final held = [
      for (final s in widget.snap.sessions)
        if (ids.contains(s.courseId) &&
            !s.upcoming &&
            !s.fromSheet &&
            !s.cancelled)
          s
    ];
    final points = runningPercent(
        [for (final s in held) s.status == 'Present' || s.status == 'Late']);
    final p = projection(c);
    const ink = Brand.onPink;
    const muted = Brand.onPinkMuted;
    final s = widget.slot;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(codeOf(c.name, widget.shortNames),
                            style: const TextStyle(
                                fontFamily: 'Schoolbell',
                                fontSize: 33,
                                height: 1.05,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0)),
                        const SizedBox(height: 4),
                        Text(c.name,
                            style: TextStyle(
                                fontSize: 13,
                                color: t.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                            '${c.attended} of ${c.held} attended'
                            '${c.total == null ? '' : ' · ${c.total} in course'}',
                            style: TextStyle(
                                fontSize: 13,
                                color: t.colorScheme.onSurfaceVariant)),
                      ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  CountUp(c.percent,
                      style: TextStyle(
                          fontFamily: 'Schoolbell',
                          fontSize: 40,
                          height: 1.05,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                          color: below ? tone.bad : t.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Pill(
                      left < 0 || !meets(c.attended, c.held, min)
                          ? 'Below $min%'
                          : left == 0
                              ? 'No leave left'
                              : 'Can miss $left',
                      color: below
                          ? tone.bad
                          : left == 0
                              ? tone.warn
                              : t.colorScheme.onSurfaceVariant),
                ]),
              ]),
              if (s != null) ...[
                const SizedBox(height: 10),
                Text(
                    '${fmtDate(s.date)}, ${s.start} to ${s.end}'
                    '${s.room.isEmpty ? '' : ' · Room ${s.room}'}',
                    style: TextStyle(
                        fontSize: 14, color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Builder(builder: (context) {
                  final part = [
                    for (final x in c.parts)
                      if (x.id == s.courseId) x
                  ].firstOrNull;
                  final ok = canSkip(c, min);
                  final partOk = part == null || canSkip(part, min);
                  return Text(
                      ok
                          ? (partOk ? 'You can skip this one' : 'Careful')
                          : 'Better not skip this',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ok && partOk
                              ? tone.good
                              : ok
                                  ? tone.warn
                                  : tone.bad));
                }),
              ],
              if (points.length >= 3) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: BoxDecoration(
                      color: t.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('So far',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 96,
                          width: double.infinity,
                          child: CustomPaint(
                              painter: SteppedTrend(
                                  points,
                                  min.toDouble(),
                                  t.colorScheme.onSurface,
                                  t.colorScheme.onSurfaceVariant)),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text('Class 1',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: t.colorScheme.onSurfaceVariant)),
                          const Spacer(),
                          Text('Class ${points.length}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                            'Each step is one class. The dashed line is $min%.',
                            style: TextStyle(
                                fontSize: 12,
                                color: t.colorScheme.onSurfaceVariant)),
                        if (p != null) ...[
                          const SizedBox(height: 8),
                          Text.rich(
                              TextSpan(children: [
                                const TextSpan(
                                    text: 'At this rate you finish at '),
                                TextSpan(
                                    text: fmtPct(p.$1),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const TextSpan(
                                    text: '. Attending every class from now: '),
                                TextSpan(
                                    text: fmtPct(p.$2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const TextSpan(text: '.'),
                              ]),
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: t.colorScheme.onSurfaceVariant)),
                        ],
                      ]),
                ),
              ],
              const SizedBox(height: 14),
              // The simulator.
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 18),
                decoration: Brand.sticker(context),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text('What if I skip',
                              style: TextStyle(
                                  fontFamily: 'Schoolbell',
                                  color: ink,
                                  fontSize: 20)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                              color: Brand.lemon,
                              border: Border.all(color: Brand.edge, width: 2),
                              borderRadius: BorderRadius.circular(99)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'One fewer',
                              visualDensity: VisualDensity.compact,
                              color: ink,
                              disabledColor: const Color(0x521A1113),
                              onPressed:
                                  n > 1 ? () => setState(() => n--) : null,
                              icon: const Icon(Icons.remove, size: 18),
                            ),
                            SizedBox(
                              width: 58,
                              child: Text('skip $n',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              tooltip: 'One more',
                              visualDensity: VisualDensity.compact,
                              color: ink,
                              disabledColor: const Color(0x521A1113),
                              onPressed: n < remaining
                                  ? () => setState(() => n++)
                                  : null,
                              icon: const Icon(Icons.add, size: 18),
                            ),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Crony(mood: mood, size: 44, onPink: true),
                        const SizedBox(width: 12),
                        Text(fmtPct(c.percent),
                            style: Brand.hand(32, color: ink)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('to',
                              style: TextStyle(color: muted, fontSize: 14)),
                        ),
                        AnimatedSwitcher(
                          duration: calm(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          transitionBuilder: (w, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                  position: Tween(
                                          begin: const Offset(0, 0.25),
                                          end: Offset.zero)
                                      .animate(a),
                                  child: w)),
                          child: Text(fmtPct(after.percent),
                              key: ValueKey(n),
                              style: Brand.hand(32,
                                  color: leftAfter < 0
                                      ? const Color(0xFF6E0F16)
                                      : ink)),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(skipLineN(c, n, min),
                          style: const TextStyle(
                              color: ink, fontSize: 14, height: 1.4)),
                      for (final part in c.parts)
                        if (s != null && part.id == s.courseId) ...[
                          const SizedBox(height: 6),
                          Text(
                              '${part.label} on its own: ${skipLineN(part, n, min)}',
                              style: const TextStyle(
                                  color: muted, fontSize: 13, height: 1.4)),
                        ],
                    ]),
              ),
              TeacherRows(
                  faculty:
                      s?.faculty.isNotEmpty == true ? s!.faculty : c.faculty,
                  course: c.name),
              ...widget.extra,
            ]),
      ),
    );
  }
}

/// A label on the left and its value on the right, for the sheet's details.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.action});
  final String label;
  final Widget value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: t.colorScheme.outlineVariant.withOpacity(0.5)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 112,
            child: Text(label,
                style: TextStyle(
                    fontSize: 14, color: t.colorScheme.onSurfaceVariant))),
        Expanded(
            child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 14, height: 1.4),
                child: value)),
        if (action != null) action!,
      ]),
    );
  }
}

/// The running percentage as steps, with the minimum as a dashed line.
class SteppedTrend extends CustomPainter {
  SteppedTrend(this.points, this.min, this.line, this.grid);
  final List<double> points;
  final double min;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    var low = min;
    for (final p in points) {
      if (p < low) low = p;
    }
    low = (low - 6).clamp(0, 100).toDouble();
    double y(double pct) =>
        4 + (size.height - 8) * (1 - (pct - low) / (100 - low));
    final step = size.width / points.length;

    final dash = Paint()
      ..color = grid.withOpacity(0.7)
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 7) {
      canvas.drawLine(Offset(dx, y(min)), Offset(dx + 3.5, y(min)), dash);
    }
    final tp = TextPainter(
        text: TextSpan(
            text: '${min.round()}%',
            style: TextStyle(fontFamily: 'Geist', fontSize: 10, color: grid)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(0, y(min) - tp.height - 2));

    final path = Path()..moveTo(0, y(points.first));
    for (var i = 0; i < points.length; i++) {
      path.lineTo(i * step, y(points[i]));
      path.lineTo((i + 1) * step, y(points[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(
        Offset(size.width - 1, y(points.last)), 4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(SteppedTrend oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.min != min ||
      oldDelegate.line != line;
}

/// Opens [CourseSheet] as a bottom sheet.
Future<void> openCourseSheet(BuildContext context,
        {required Course course,
        required Snapshot snap,
        required int minPct,
        ClassSlot? slot,
        Map<String, String> shortNames = const {},
        List<Widget> Function(BuildContext)? extra}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => CourseSheet(
          course: course,
          snap: snap,
          minPct: minPct,
          slot: slot,
          shortNames: shortNames,
          extra: extra?.call(ctx) ?? const []),
    );

/// Crony's one-time note at the bottom of a tab, with a "Got it".
class CronyTip extends StatelessWidget {
  const CronyTip({super.key, required this.text, required this.onDone});
  final String text;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final card = Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF26242A) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: dark ? Border.all(color: t.colorScheme.outlineVariant) : null,
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x1F191714),
                      blurRadius: 24,
                      offset: Offset(0, 8))
                ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Crony(mood: Mood.idle, size: 46),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Crony',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
              Align(
                alignment: Alignment.centerRight,
                child:
                    TextButton(onPressed: onDone, child: const Text('Got it')),
              ),
            ]),
          ),
        ]),
      ),
    );
    if (calm(context)) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: const Interval(0.45, 1, curve: Cubic(0.23, 1, 0.32, 1)),
      builder: (_, v, c) => Opacity(
          opacity: v,
          child:
              Transform.translate(offset: Offset(0, 24 * (1 - v)), child: c)),
      child: card,
    );
  }
}

/// "12 days" as a big figure over a small unit, or "Today" and "Tmrw".
class DaysCount extends StatelessWidget {
  const DaysCount(this.at, this.now, {super.key, this.urgent = false});
  final DateTime at;
  final DateTime now;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = urgent ? Tone.of(context).bad : t.colorScheme.onSurface;
    final days = DateTime(at.year, at.month, at.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days <= 1) {
      return Text(days <= 0 ? 'Today' : 'Tmrw',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: color));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$days',
          style: TextStyle(
              fontFamily: 'Schoolbell',
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: color)),
      Text('days',
          style:
              TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// An icon on a soft pink square, to lead a card.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
          color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 21, color: c),
    );
  }
}

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// "November 2026", for grouping lists by month.
String monthTitle(DateTime d) => '${const [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December'
    ][d.month - 1]} ${d.year}';

/// A small calendar leaf: the day's number over its month.
class DateBlock extends StatelessWidget {
  const DateBlock(this.d, {super.key, this.color});
  final DateTime d;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
          color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${d.day}',
            style: TextStyle(
                fontSize: 18,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: c,
                fontFeatures: const [FontFeature.tabularFigures()])),
        Text(_mon[d.month - 1].toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: c.withOpacity(0.8))),
      ]),
    );
  }
}

/// The top bar of a screen opened from a tab: the big title, a back arrow.
AppBar screenBar(String title, {String? subtitle, List<Widget>? actions}) =>
    AppBar(
      toolbarHeight: 76,
      titleSpacing: 0,
      title: BigTitle(title, subtitle: subtitle),
      actions: [...?actions, const SizedBox(width: 8)],
    );

/// The title block at the top of a bottom sheet.
class SheetHead extends StatelessWidget {
  const SheetHead(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Schoolbell',
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(subtitle!,
                    style: TextStyle(
                        fontSize: 14, color: t.colorScheme.onSurfaceVariant)),
              ),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
  }
}

/// A small heading inside a sheet or form, above a group of controls.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// While the first data comes in: Crony waiting, with a thin bar.
class LoadingNote extends StatelessWidget {
  const LoadingNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Crony(mood: Mood.idle, size: 72),
      const SizedBox(height: 18),
      Text(text, style: t.textTheme.titleMedium),
      const SizedBox(height: 14),
      SizedBox(
        width: 120,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: t.colorScheme.primary.withOpacity(0.12)),
        ),
      ),
    ]);
  }
}
