// Crony, the app's mascot: the Lemonade face from the logo. Sunglasses on while
// all is well; they slide down the nose to show the eyes when a skip would
// hurt, and the lenses turn red past the limit. Drawn on the logo's own
// 1024 grid so it matches the icon line for line.

import 'package:flutter/material.dart';

import 'theme.dart';

enum Mood { idle, happy, worried, alarmed, sleep }

class Crony extends StatelessWidget {
  const Crony(
      {super.key, this.mood = Mood.idle, this.size = 48, this.onPink = false});

  final Mood mood;
  final double size;

  /// Drawn in the pink card's ink, for pink cards.
  final bool onPink;

  static double _drop(Mood m) => switch (m) {
        Mood.happy => -16,
        Mood.worried || Mood.sleep => 92,
        Mood.alarmed => 124,
        Mood.idle => 0,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final line = onPink
        ? Brand.onPink
        : dark
            ? const Color(0xFFFCEAF0)
            : Brand.edge;
    final bad = onPink ? const Color(0xFF6E0F16) : Tone.of(context).bad;
    return Semantics(
      label: 'Crony',
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _drop(mood)),
          duration: const Duration(milliseconds: 260),
          curve: const Cubic(0.23, 1, 0.32, 1),
          builder: (_, drop, __) =>
              CustomPaint(painter: _CronyPainter(mood, drop, line, bad)),
        ),
      ),
    );
  }
}

class _CronyPainter extends CustomPainter {
  _CronyPainter(this.mood, this.drop, this.line, this.bad);
  final Mood mood;
  final double drop;
  final Color line;
  final Color bad;

  static const _cx = 522.0, _cy = 572.0, _rx = 248.0, _ry = 298.0;
  static const _deg = 3.141592653589793 / 180;

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
    final head = Rect.fromCenter(
        center: const Offset(_cx, _cy), width: _rx * 2, height: _ry * 2);
    canvas.drawArc(head, -24 * _deg, -348 * _deg, false, stroke(40));
    final shine = Rect.fromCenter(
        center: const Offset(_cx, _cy),
        width: (_rx - 30) * 2,
        height: (_ry - 30) * 2);
    canvas.drawArc(shine, -84 * _deg, 48 * _deg, false, stroke(22));

    canvas.drawPath(
        Path()
          ..moveTo(522, 626)
          ..cubicTo(518, 664, 506, 698, 512, 712)
          ..quadraticBezierTo(524, 726, 572, 714),
        stroke(34));

    // Eyes sit behind the lenses and only show when the glasses come down.
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

  @override
  bool shouldRepaint(_CronyPainter old) =>
      old.mood != mood ||
      old.drop != drop ||
      old.line != line ||
      old.bad != bad;
}
