// Crony, the app's mascot. Its two lime crest marks are the classes you can
// still skip, like the app icon: one dims when worried, both turn red when
// alarmed. Drawn on a 64 x 64 grid so it stays sharp at any size.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

enum Mood { idle, happy, worried, alarmed, sleep }

class Crony extends StatelessWidget {
  const Crony(
      {super.key, this.mood = Mood.idle, this.size = 48, this.onWine = false});

  final Mood mood;
  final double size;

  /// Light body with a wine face, for wine cards.
  final bool onWine;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Crony',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _CronyPainter(mood, onWine, dark)),
      ),
    );
  }
}

class _CronyPainter extends CustomPainter {
  _CronyPainter(this.mood, this.onWine, this.dark);
  final Mood mood;
  final bool onWine;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final body = onWine
        ? Brand.wineInk
        : dark
            ? Brand.wineDark
            : Brand.wine;
    final face = onWine ? Brand.wine : Brand.wineInk;
    final on = onWine || dark ? Brand.lime : Brand.limeDeep;
    final off =
        onWine || dark ? const Color(0x3DF7F1EC) : const Color(0x29191714);
    final bad = onWine
        ? const Color(0xFFFFB4AB)
        : dark
            ? const Color(0xFFFF8C82)
            : const Color(0xFFB3261E);
    final crest = switch (mood) {
      Mood.alarmed => [bad, bad],
      Mood.worried => [on, off],
      Mood.sleep => [off, off],
      _ => [on, on],
    };

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.6;
    final crestBox = Rect.fromCircle(center: const Offset(32, 32), radius: 25);
    double rad(double d) => d * math.pi / 180;
    canvas.drawArc(
        crestBox, rad(-76), rad(18), false, stroke..color = crest[0]);
    canvas.drawArc(
        crestBox, rad(-44), rad(18), false, stroke..color = crest[1]);

    final fill = Paint()..color = body;
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(24.5, 58.5), width: 10.4, height: 6.8),
        fill);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(39.5, 58.5), width: 10.4, height: 6.8),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(13.5, 12, 37, 46), const Radius.circular(18.5)),
        fill);

    // The face sits in the upper part of the body.
    canvas.save();
    canvas.translate(32, 31);
    canvas.scale(0.8);
    canvas.translate(-32, -39);
    final f = Paint()..color = face;
    final line = Paint()
      ..color = face
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6;

    void eyesOpen() {
      for (final x in [22.0, 36.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, 30, 6, 10), const Radius.circular(3)),
            f);
      }
    }

    void brows() {
      canvas.drawLine(const Offset(21, 28.5), const Offset(28, 26.5), line);
      canvas.drawLine(const Offset(43, 28.5), const Offset(36, 26.5), line);
    }

    void curve(
        double x0, double y0, double cx, double cy, double x1, double y1) {
      canvas.drawPath(
          Path()
            ..moveTo(x0, y0)
            ..quadraticBezierTo(cx, cy, x1, y1),
          line);
    }

    switch (mood) {
      case Mood.idle:
        eyesOpen();
        canvas.drawLine(const Offset(29.5, 48), const Offset(34.5, 48), line);
      case Mood.happy:
        curve(21.5, 36.5, 25, 31.5, 28.5, 36.5);
        curve(35.5, 36.5, 39, 31.5, 42.5, 36.5);
        curve(27.5, 46.5, 32, 50.7, 36.5, 46.5);
      case Mood.worried:
        eyesOpen();
        brows();
        curve(28.5, 49.5, 32, 46.3, 35.5, 49.5);
      case Mood.alarmed:
        canvas.drawCircle(const Offset(25, 35), 4.4, f);
        canvas.drawCircle(const Offset(39, 35), 4.4, f);
        brows();
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(32, 48.5), width: 5.2, height: 6),
            f);
      case Mood.sleep:
        canvas.drawLine(
            const Offset(21.5, 35.5), const Offset(28.5, 35.5), line);
        canvas.drawLine(
            const Offset(35.5, 35.5), const Offset(42.5, 35.5), line);
        canvas.drawLine(const Offset(29.5, 48), const Offset(34.5, 48), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CronyPainter old) =>
      old.mood != mood || old.onWine != onWine || old.dark != dark;
}
