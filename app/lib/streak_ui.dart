import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'crony_ui.dart';
import 'mascot.dart';
import 'motion.dart';
import 'streak.dart';
import 'theme.dart';
import 'ui_common.dart';

String _days(int n) => n == 1 ? '1 day' : '$n days';
String _weeks(int n) => n == 1 ? '1 week' : '$n weeks';

/// A slice of lemon: a disc with a rim and spokes.
class LemonSlice extends StatelessWidget {
  const LemonSlice({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _SlicePainter());
}

class _SlicePainter extends CustomPainter {
  const _SlicePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    final ink = Paint()
      ..color = Brand.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r * 0.9, Paint()..color = Brand.lemonDeep);
    canvas.drawCircle(c, r * 0.66, Paint()..color = const Color(0xFFFFF3A8));
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.6,
          ink..strokeWidth = r * 0.1);
    }
    canvas.drawCircle(c, r * 0.9, ink..strokeWidth = r * 0.16);
  }

  @override
  bool shouldRepaint(_SlicePainter old) => false;
}

/// "6 days" on a lemon pill, shown from the second full day in a row.
/// Opens the sheet with the rest.
class StreakChip extends StatelessWidget {
  const StreakChip(this.streak, {super.key});
  final Streak streak;

  @override
  Widget build(BuildContext context) {
    if (streak.days < 2) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: '${_days(streak.days)} in a row with every class attended',
      excludeSemantics: true,
      child: Material(
        color: Brand.lemon,
        shape: const StadiumBorder(
            side: BorderSide(color: Brand.edge, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showStreak(context, streak),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 3, 10, 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const LemonSlice(size: 16),
              const SizedBox(width: 5),
              Text(_days(streak.days),
                  style: Brand.hand(15, color: Brand.onPink, height: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The run in full: how long, since when, the best one, and what is next.
Future<void> showStreak(BuildContext context, Streak s) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final next = nextMilestone(s.days);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHead('${_days(s.days)} in a row',
                  subtitle: s.since == null
                      ? 'Every class attended'
                      : 'Every class attended since ${fmtDate(s.since!)}',
                  trailing:
                      const Crony(mood: Mood.happy, size: 48, play: true)),
              InfoRow('Longest run', Text(_days(s.best))),
              InfoRow('Clean weeks',
                  Text('${_weeks(s.weeks)} in a row without an absence')),
              if (next != null)
                InfoRow('Next cheer',
                    Text('At ${_days(next)}, ${next - s.days} to go')),
              const SizedBox(height: 12),
              Text(
                  'A day counts once its classes are marked on the attendance '
                  'site. One absence starts the count again.',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        );
      },
    );

/// Crony cheers a milestone: lemon drops fly out once, then it is still.
Future<void> cheerStreak(BuildContext context, int days, Streak s) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              height: 170,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: LemonBurst()),
                Crony(mood: Mood.happy, size: 96, play: true),
              ]),
            ),
            Text('${_days(days)} in a row',
                textAlign: TextAlign.center,
                style: Brand.hand(32, height: 1.1)),
            const SizedBox(height: 6),
            Text(
                s.since == null
                    ? 'Not one class missed.'
                    : 'Not one class missed since ${fmtDate(s.since!)}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Keep it going')),
          ]),
        ),
      ),
    );

/// Lemon drops thrown up from the middle that fall away under their own
/// weight. Plays once; draws nothing when the phone asks for less motion.
class LemonBurst extends StatefulWidget {
  const LemonBurst({super.key, this.drops = 22});
  final int drops;

  @override
  State<LemonBurst> createState() => _LemonBurstState();
}

class _LemonBurstState extends State<LemonBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || calm(context)) return;
    _started = true;
    _t.forward();
    tick();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _BurstPainter(_t, widget.drops)),
      );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.drops) : super(repaint: t);
  final Animation<double> t;
  final int drops;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v == 0 || v == 1) return;
    final r = math.Random(7);
    final c = Offset(size.width / 2, size.height * 0.55);
    final fade = v < 0.7 ? 1.0 : (1 - v) / 0.3;
    final fill = Paint()..color = Brand.lemon.withOpacity(fade);
    final ink = Paint()
      ..color = Brand.edge.withOpacity(fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < drops; i++) {
      // Up and out, most of them upward; then gravity takes over.
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.25;
      final speed = size.height * (0.9 + r.nextDouble() * 1.1);
      final radius = 3.0 + r.nextDouble() * 4;
      final x = c.dx + math.cos(angle) * speed * v;
      final y = c.dy + math.sin(angle) * speed * v + size.height * 2.1 * v * v;
      canvas.drawCircle(Offset(x, y), radius, fill);
      canvas.drawCircle(Offset(x, y), radius, ink);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
