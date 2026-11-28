// Crony, the app's mascot: the Lemonade face from the logo. Sunglasses on while
// all is well; they slide down the nose to show the eyes when a skip would
// hurt, and the lenses turn red past the limit. Drawn on the logo's own
// 1024 grid so it matches the icon line for line.
//
// The face is built in layers, glasses in front and the head behind, so it
// has depth when it turns: it nods when its mood changes and, where [play]
// is set, spins on a tap and turns under a finger.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';

enum Mood { idle, happy, worried, alarmed, sleep }

class Crony extends StatefulWidget {
  const Crony(
      {super.key,
      this.mood = Mood.idle,
      this.size = 48,
      this.onPink = false,
      this.play = false});

  final Mood mood;
  final double size;

  /// Drawn in the pink card's ink, for pink cards.
  final bool onPink;

  /// Spins when tapped and turns when dragged sideways.
  final bool play;

  @override
  State<Crony> createState() => _CronyState();
}

class _CronyState extends State<Crony> with TickerProviderStateMixin {
  late final AnimationController _turn, _nod, _peek;
  final _spring = spring(stiffness: 130, ratio: 0.5);
  bool _started = false;
  double _spinTo = 0;

  static double _drop(Mood m) => switch (m) {
        Mood.happy => -16,
        Mood.worried || Mood.sleep => 92,
        Mood.alarmed => 124,
        Mood.idle => 0,
      };

  @override
  void initState() {
    super.initState();
    _turn = AnimationController.unbounded(vsync: this);
    _nod = AnimationController.unbounded(vsync: this);
    _peek = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 760));
  }

  bool get _still => MediaQuery.of(context).disableAnimations;

  // Ends exactly at rest, where the face is drawn flat like the logo.
  void _home(AnimationController c, [double? velocity]) => c
      .animateWith(
          SpringSimulation(_spring, c.value, 0, velocity ?? c.velocity))
      .whenComplete(() => c.value = 0);

  Future<void> _spin() async {
    HapticFeedback.lightImpact();
    if (_still) return;
    // A tap during a spin adds a turn instead of starting over.
    _spinTo = (_turn.isAnimating && _spinTo > _turn.value ? _spinTo : 0) +
        2 * math.pi;
    final to = _spinTo;
    _peek.forward(from: 0);
    await _turn.animateTo(to,
        duration: const Duration(milliseconds: 760), curve: easeInOut);
    if (mounted && _spinTo == to) {
      _turn.value = 0;
      _spinTo = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Turns to face you when it first appears.
    if (widget.play && !_still) {
      _turn.value = -0.75;
      _home(_turn);
    }
  }

  @override
  void didUpdateWidget(Crony old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood && !_still) _home(_nod, 3.2);
  }

  @override
  void dispose() {
    _turn.dispose();
    _nod.dispose();
    _peek.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final line = widget.onPink
        ? Brand.onPink
        : dark
            ? const Color(0xFFFCEAF0)
            : Brand.edge;
    final bad = widget.onPink ? const Color(0xFF6E0F16) : Tone.of(context).bad;
    final mood = widget.mood;
    final face = TweenAnimationBuilder<double>(
      tween: Tween(end: _drop(mood)),
      duration: const Duration(milliseconds: 260),
      curve: easeOut,
      builder: (_, drop, __) => AnimatedBuilder(
        animation: Listenable.merge([_turn, _nod, _peek]),
        builder: (_, __) => CustomPaint(
            painter: _CronyPainter(
                mood,
                // Mid-spin the glasses dip, and the eyes look out over them.
                drop + math.sin(_peek.value * math.pi) * (92 - drop) * 0.8,
                line,
                bad,
                _turn.value,
                _nod.value)),
      ),
    );
    return Semantics(
      label: 'Crony',
      child: SizedBox.square(
        dimension: widget.size,
        child: !widget.play
            ? face
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _spin,
                onHorizontalDragUpdate: _still
                    ? null
                    : (d) {
                        _spinTo = 0;
                        _turn.value =
                            (_turn.value + d.delta.dx / widget.size * 1.8)
                                .clamp(-1.0, 1.0);
                      },
                onHorizontalDragEnd: _still
                    ? null
                    : (d) => _home(
                        _turn,
                        (d.velocity.pixelsPerSecond.dx / widget.size * 1.8)
                            .clamp(-12.0, 12.0)),
                child: face,
              ),
      ),
    );
  }
}

class _CronyPainter extends CustomPainter {
  _CronyPainter(this.mood, this.drop, this.line, this.bad,
      [this.turn = 0, this.nod = 0]);
  final Mood mood;
  final double drop;
  final Color line;
  final Color bad;

  /// Turned about the upright axis and tipped forward, in radians.
  final double turn;
  final double nod;

  static const _cx = 522.0, _cy = 572.0, _rx = 248.0, _ry = 298.0;
  static const _deg = 3.141592653589793 / 180;

  /// 1 / the viewer's distance, in grid units.
  static const _far = 1 / 1500;

  /// Where a layer [z] grid units behind the face lands on the page. Each
  /// layer is sized so that, facing front, it sits exactly where the flat
  /// logo has it.
  Matrix4 _at(double z) => Matrix4.identity()
    ..translate(_cx, _cy)
    ..multiply(Matrix4.identity()..setEntry(3, 2, _far))
    ..rotateY(turn)
    ..rotateX(nod)
    ..translate(0.0, 0.0, z)
    ..scale(1 + _far * z, 1 + _far * z, 1.0)
    ..translate(-_cx, -_cy);

  @override
  void paint(Canvas canvas, Size size) {
    // The face's box on the logo grid, 740 wide from (150, 200).
    canvas.scale(size.width / 740);
    canvas.translate(-150, -200);

    Paint stroke(double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w
      ..color = line;
    final fill = Paint()..color = line;

    // The head, open at the top right like the logo, and its shine.
    void head() {
      final head = Rect.fromCenter(
          center: const Offset(_cx, _cy), width: _rx * 2, height: _ry * 2);
      canvas.drawArc(head, -24 * _deg, -348 * _deg, false, stroke(40));
      final shine = Rect.fromCenter(
          center: const Offset(_cx, _cy),
          width: (_rx - 30) * 2,
          height: (_ry - 30) * 2);
      canvas.drawArc(shine, -84 * _deg, 48 * _deg, false, stroke(22));
    }

    void rim() {
      final head = Rect.fromCenter(
          center: const Offset(_cx, _cy), width: _rx * 2, height: _ry * 2);
      canvas.drawArc(head, -24 * _deg, -348 * _deg, false, stroke(40));
    }

    void nose() => canvas.drawPath(
        Path()
          ..moveTo(522, 626)
          ..cubicTo(518, 664, 506, 698, 512, 712)
          ..quadraticBezierTo(524, 726, 572, 714),
        stroke(34));

    // Eyes sit behind the lenses and only show when the glasses come down.
    void eyes() {
      final lid = stroke(28);
      switch (mood) {
        case Mood.alarmed:
          canvas.drawCircle(const Offset(348, 546), 36, fill);
          canvas.drawCircle(const Offset(690, 546), 36, fill);
        case Mood.sleep:
          for (final x in [348.0, 690.0]) {
            canvas.drawPath(
                Path()
                  ..moveTo(x - 34, 548)
                  ..quadraticBezierTo(x, 570, x + 34, 548),
                lid);
          }
        default:
          canvas.drawCircle(const Offset(348, 548), 26, fill);
          canvas.drawCircle(const Offset(690, 548), 26, fill);
      }
      if (mood == Mood.worried || mood == Mood.alarmed) {
        canvas.drawPath(
            Path()
              ..moveTo(308, 474)
              ..quadraticBezierTo(350, 470, 394, 450)
              ..moveTo(648, 450)
              ..quadraticBezierTo(692, 470, 734, 474),
            lid);
      }
    }

    void glasses() {
      canvas.save();
      canvas.translate(0, drop);
      final lens = Paint()..color = mood == Mood.alarmed ? bad : Brand.lemon;
      final left = Path()
        ..moveTo(188, 506)
        ..lineTo(482, 514)
        ..cubicTo(478, 610, 442, 698, 376, 700)
        ..cubicTo(296, 702, 226, 628, 188, 506)
        ..close();
      final right = Path()
        ..moveTo(542, 514)
        ..lineTo(848, 506)
        ..cubicTo(818, 610, 748, 678, 676, 678)
        ..cubicTo(606, 678, 552, 622, 542, 514)
        ..close();
      for (final p in [left, right]) {
        canvas.drawPath(p, lens);
        canvas.drawPath(p, stroke(34));
      }
      canvas.drawPath(
          Path()
            ..moveTo(188, 506)
            ..lineTo(482, 514)
            ..quadraticBezierTo(512, 490, 542, 514)
            ..lineTo(848, 506),
          stroke(46));
      canvas.drawCircle(
          const Offset(786, 560), 18, Paint()..color = Colors.white);
      canvas.restore();
    }

    if (turn == 0 && nod == 0) {
      head();
      nose();
      eyes();
      glasses();
      return;
    }

    // Back to front. The extra rims behind the head give it an edge, like a
    // coin; seen from behind the order runs the other way.
    final layers = <(double, VoidCallback)>[
      for (var z = 36.0; z > 0; z -= 6) (z, rim),
      (0, head),
      (-10, eyes),
      (-34, nose),
      (-64, glasses),
    ];
    for (final (z, draw) in math.cos(turn) < 0 ? layers.reversed : layers) {
      canvas.save();
      canvas.transform(_at(z).storage);
      draw();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CronyPainter old) =>
      old.mood != mood ||
      old.drop != drop ||
      old.line != line ||
      old.bad != bad ||
      old.turn != turn ||
      old.nod != nod;
}
