// Lemonade, wherever something has a level: the glass for attendance, the
// drink standing in the pink cards, the bars that fill. All of it pours in
// when first shown, sloshes when its card is pressed or the page is
// scrolled, and then stands still.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';
import 'theme.dart';

/// Where the drink stands in the glass, 0 to 1. The minimum always sits at
/// [line] so the room above it is easy to read: 85% and 100% are far apart
/// on the glass even though they are close as numbers.
double glassLevel(double percent, int min, {double line = 0.6}) {
  final p = percent.clamp(0.0, 100.0);
  if (min <= 0) return p / 100;
  if (min >= 100) return line * p / 100;
  return p <= min
      ? line * p / min
      : line + (1 - line) * (p - min) / (100 - min);
}

/// What every liquid shares: it pours, it sloshes when knocked, it fizzes.
mixin Fluid<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  late final AnimationController pour, fizz, slosh;
  late final CurvedAnimation poured;
  late final Listenable moving;
  final _spring = spring(stiffness: 70, ratio: 0.22);
  ValueListenable<Offset>? _lean;
  ScrollPosition? _scroll;
  double _at = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    pour = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    fizz = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    slosh = AnimationController.unbounded(vsync: this);
    poured = CurvedAnimation(parent: pour, curve: easeOut);
    moving = Listenable.merge([pour, fizz, slosh]);
  }

  bool get still => MediaQuery.of(context).disableAnimations;

  /// Sets the surface rocking, as if the glass were tapped.
  void knock(double push) {
    if (still) return;
    final to = (_lean?.value.dx ?? 0) * 0.3;
    slosh
        .animateWith(SpringSimulation(
            _spring, slosh.value, to, (slosh.velocity + push).clamp(-4.0, 4.0)))
        .whenComplete(() => slosh.value = to);
    if (!fizz.isAnimating) fizz.forward(from: 0);
  }

  void _leaned() => knock(0);

  void _scrolled() {
    final moved = _scroll!.pixels - _at;
    _at = _scroll!.pixels;
    if (moved.abs() > 0.5) knock((moved * 0.03).clamp(-1.0, 1.0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lean = Tilt.of(context);
    if (lean != _lean) {
      _lean?.removeListener(_leaned);
      _lean = lean?..addListener(_leaned);
    }
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_scrolled);
      _scroll = scroll?..addListener(_scrolled);
      _at = scroll != null && scroll.hasPixels ? scroll.pixels : 0;
    }
    if (_started) return;
    _started = true;
    if (still) {
      pour.value = 1;
      return;
    }
    pour.forward();
    slosh.value = 0.2;
    knock(0);
  }

  @override
  void dispose() {
    _lean?.removeListener(_leaned);
    _scroll?.removeListener(_scrolled);
    poured.dispose();
    pour.dispose();
    fizz.dispose();
    slosh.dispose();
    super.dispose();
  }
}

/// Paints a drink standing in [box]: empty at its bottom edge, full at its
/// top. The caller clips to the vessel first.
void paintLiquid(Canvas canvas, Rect box,
    {required double level,
    required AnimationController slosh,
    required double fizz,
    required Color color,
    Color? line,
    Color? bubbles}) {
  final cx = box.center.dx;
  final edge = (box.width * 0.14).clamp(3.0, 9.0);
  final lean = (slosh.value / 0.3).clamp(-1.6, 1.6) * edge;
  final swell = (slosh.velocity.abs() * 1.4).clamp(0.0, 2.6);
  final phase = slosh.value * 9;
  final surface = box.bottom - level * box.height;
  double y(double x) =>
      surface +
      lean * (x - cx) / (box.width / 2) +
      swell * math.sin(x / 11 + phase);

  final wave = Path()..moveTo(box.left, y(box.left));
  for (var x = box.left + 2; x <= box.right; x += 2) {
    wave.lineTo(x, y(x));
  }
  wave.lineTo(box.right, y(box.right));
  canvas.drawPath(
      Path.from(wave)
        ..lineTo(box.right, box.bottom + 12)
        ..lineTo(box.left, box.bottom + 12)
        ..close(),
      Paint()..color = color);
  if (line != null) {
    canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = line);
  }

  // Bubbles rise once after a pour or a knock, then the drink is still.
  if (bubbles == null || fizz <= 0 || fizz >= 1) return;
  final count = (box.width / 46).round().clamp(3, 7);
  for (var i = 0; i < count; i++) {
    final t = (fizz * 1.7 - i * 0.7 / count).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) continue;
    final x = box.left +
        box.width * (0.14 + 0.72 * ((i * 5) % count) / (count - 1)) +
        math.sin(t * 7 + i) * 1.6;
    final from = box.bottom - 5, to = y(x) + 4;
    if (to >= from) continue;
    canvas.drawCircle(
        Offset(x, from + (to - from) * t),
        1.4 + (i % 3) * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = bubbles.withOpacity(bubbles.opacity * (1 - t * t)));
  }
}

/// A glass of lemonade for an attendance figure: the dashed line is the
/// minimum, and what stands above it is what can still be spent.
class LemonGlass extends StatefulWidget {
  const LemonGlass(
      {super.key,
      required this.percent,
      required this.min,
      this.bad = false,
      this.ink,
      this.size = const Size(50, 68)})
      : loading = false;

  /// Fills over and over, for something still on its way.
  const LemonGlass.loading(
      {super.key, this.ink, this.size = const Size(44, 60)})
      : percent = 0,
        min = 0,
        bad = false,
        loading = true;

  final double percent;
  final int min;

  /// Below the minimum: the drink turns the warning colour.
  final bool bad;

  /// The outline, where the card behind is not the page colour.
  final Color? ink;
  final Size size;
  final bool loading;

  @override
  State<LemonGlass> createState() => _LemonGlassState();
}

class _LemonGlassState extends State<LemonGlass>
    with TickerProviderStateMixin, Fluid {
  late final AnimationController _level, _loop;

  double get _target => glassLevel(widget.percent, widget.min);

  @override
  void initState() {
    super.initState();
    _level = AnimationController(vsync: this, value: _target);
    _loop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.loading && !still && !_loop.isAnimating) _loop.repeat();
  }

  @override
  void didUpdateWidget(LemonGlass old) {
    super.didUpdateWidget(old);
    if (_target == _level.value || widget.loading) return;
    if (still) {
      _level.value = _target;
      return;
    }
    final push = _target < _level.value ? -0.9 : 0.9;
    _level.animateTo(_target,
        duration: const Duration(milliseconds: 520), curve: easeOut);
    knock(push);
  }

  @override
  void dispose() {
    _level.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: widget.size,
          painter: _GlassPainter(
            level: _level,
            line: widget.loading
                ? null
                : glassLevel(widget.min.toDouble(), widget.min),
            pour: poured,
            slosh: slosh,
            fizz: fizz,
            loop: widget.loading ? _loop : null,
            ink: widget.ink ?? (dark ? const Color(0xFFFCEAF0) : Brand.edge),
            drink: widget.bad ? Tone.of(context).bad : Brand.lemon,
            repaint: Listenable.merge([moving, _level, _loop]),
          ),
        ),
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(
      {required this.level,
      required this.line,
      required this.pour,
      required this.slosh,
      required this.fizz,
      required this.loop,
      required this.ink,
      required this.drink,
      required Listenable repaint})
      : super(repaint: repaint);
  final Animation<double> level;
  final double? line;
  final Animation<double> pour;
  final AnimationController slosh;
  final Animation<double> fizz;
  final Animation<double>? loop;
  final Color ink;
  final Color drink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    final top = h * 0.2, bottom = h - 2;
    final wide = w / 2 - 2, narrow = wide * 0.74;
    final r = w * 0.12;
    final glass = Path()
      ..moveTo(cx - wide, top)
      ..lineTo(cx - narrow, bottom - r)
      ..quadraticBezierTo(cx - narrow, bottom, cx - narrow + r, bottom)
      ..lineTo(cx + narrow - r, bottom)
      ..quadraticBezierTo(cx + narrow, bottom, cx + narrow, bottom - r)
      ..lineTo(cx + wide, top);
    final box = Rect.fromLTRB(cx - wide, top + 5, cx + wide, bottom);

    // Still loading: the glass fills, then starts again.
    final t = loop?.value;
    final full = t == null
        ? level.value * pour.value
        : 0.12 + 0.76 * easeOut.transform((t * 1.25).clamp(0.0, 1.0));

    canvas.save();
    canvas.clipPath(Path.from(glass)..close());
    paintLiquid(canvas, box,
        level: full,
        slosh: slosh,
        fizz: t ?? fizz.value,
        color: drink,
        line: ink,
        bubbles: ink.withOpacity(0.75));
    final min = line;
    if (min != null) {
      final y = box.bottom - min * box.height;
      final dash = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = ink.withOpacity(0.6);
      for (var x = box.left; x < box.right; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), dash);
      }
    }
    canvas.restore();

    // The straw, outlined like everything else in the logo.
    final foot = Offset(cx - narrow * 0.25, bottom - h * 0.1);
    final tip = Offset(cx + wide * 0.72, h * 0.03);
    Paint stroke(double width, Color c) => Paint()
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawLine(foot, tip, stroke(w * 0.124, ink));
    canvas.drawLine(foot, tip, stroke(w * 0.056, Brand.pink));

    canvas.drawPath(
        glass,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (w * 0.044).clamp(1.6, 3.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink);
    canvas.drawLine(
        Offset(cx - wide + w * 0.13, top + (bottom - top) * 0.34),
        Offset(cx - wide + w * 0.164, top + (bottom - top) * 0.58),
        stroke(w * 0.04, Colors.white.withOpacity(0.9)));
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.line != line || old.ink != ink || old.drink != drink;
}

/// A drink filling its box from the bottom, clipped by whatever holds it.
class Liquid extends StatefulWidget {
  const Liquid(
      {super.key,
      required this.level,
      required this.color,
      this.line,
      this.bubbles});

  /// 0 (empty) to 1 (full).
  final double level;
  final Color color;
  final Color? line;
  final Color? bubbles;

  @override
  State<Liquid> createState() => _LiquidState();
}

class _LiquidState extends State<Liquid> with TickerProviderStateMixin, Fluid {
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _LiquidPainter(widget, poured, slosh, fizz, moving),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter(this.w, this.pour, this.slosh, this.fizz, Listenable repaint)
      : super(repaint: repaint);
  final Liquid w;
  final Animation<double> pour;
  final AnimationController slosh;
  final Animation<double> fizz;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintLiquid(canvas, Offset.zero & size,
        level: w.level.clamp(0.0, 1.0) * pour.value,
        slosh: slosh,
        fizz: fizz.value,
        color: w.color,
        line: w.line,
        bubbles: w.bubbles);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.w.level != w.level ||
      old.w.color != w.color ||
      old.w.line != w.line ||
      old.w.bubbles != w.bubbles;
}

/// The pink sticker card, with lemonade standing in the bottom of it. It
/// leans under a finger like every card, and the drink moves with it.
class Sticker extends StatelessWidget {
  const Sticker(
      {super.key,
      required this.child,
      this.radius = 22,
      this.padding = EdgeInsets.zero,
      this.margin,
      this.level = 0.3});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// How much of the card the drink fills, 0 to 1.
  final double level;

  @override
  Widget build(BuildContext context) => Tilt(
        child: Container(
          margin: margin,
          decoration: Brand.sticker(context, radius: radius),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 2),
            child: Stack(fit: StackFit.passthrough, children: [
              Positioned.fill(
                  child: Liquid(
                      level: level,
                      color: const Color(0xFFE2577B),
                      bubbles: Brand.onPink.withOpacity(0.32))),
              Padding(padding: padding, child: child),
            ]),
          ),
        ),
      );
}

/// A bar that fills like a drink through a straw. Without a [value] it
/// keeps flowing, for work whose end is not known.
class LiquidBar extends StatefulWidget {
  const LiquidBar(
      {super.key, this.value, this.height = 6, this.color, this.track});

  /// 0 to 1, or null while the amount is not known.
  final double? value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  State<LiquidBar> createState() => _LiquidBarState();
}

class _LiquidBarState extends State<LiquidBar>
    with TickerProviderStateMixin, Fluid {
  late final AnimationController _flow;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
  }

  void _run() {
    final flowing = widget.value == null && !still;
    if (flowing && !_flow.isAnimating) _flow.repeat();
    if (!flowing && _flow.isAnimating) _flow.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(LiquidBar old) {
    super.didUpdateWidget(old);
    _run();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _BarPainter(
              value: widget.value,
              pour: poured,
              slosh: slosh,
              flow: _flow,
              color: widget.color ?? t.colorScheme.primary,
              track: widget.track ?? t.colorScheme.surfaceContainerHighest,
              repaint: Listenable.merge([moving, _flow])),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(
      {required this.value,
      required this.pour,
      required this.slosh,
      required this.flow,
      required this.color,
      required this.track,
      required Listenable repaint})
      : super(repaint: repaint);
  final double? value;
  final Animation<double> pour;
  final AnimationController slosh;
  final Animation<double> flow;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2)));
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final fill = Paint()..color = color;
    final v = value;
    if (v == null) {
      // A slug of drink travelling along the bar.
      final t = flow.value;
      final head = w * 1.5 * Curves.easeInOut.transform(t);
      canvas.drawRRect(
          RRect.fromLTRBR(head - w * 0.45, 0, head, h, Radius.circular(h / 2)),
          fill);
    } else if (v > 0) {
      final end = w * v.clamp(0.0, 1.0) * pour.value;
      // The front of the drink rocks a little before it settles.
      final rock = (slosh.value / 0.3).clamp(-1.6, 1.6) * 3;
      final tip = (end + rock).clamp(h, w);
      final lean = (slosh.velocity * 1.2).clamp(-2.5, 2.5);
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(tip - h / 2 + lean, 0)
            ..quadraticBezierTo(tip + h / 2, h / 2, tip - h / 2 - lean, h)
            ..lineTo(0, h)
            ..close(),
          fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// One tube for a whole course. The drink is the classes attended; the
/// hatched end is the classes missed, which can never be filled; the dashed
/// line is where the drink has to reach by the last class.
class Straw extends StatelessWidget {
  const Straw(
      {super.key,
      required this.attended,
      required this.missed,
      required this.total,
      required this.min,
      this.pending = 0,
      this.bad = false});
  final int attended;
  final int missed;

  /// Classes held but not marked yet: dotted, between drink and hatching.
  final int pending;
  final int total;
  final int min;
  final bool bad;

  static const height = 18.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ink = t.colorScheme.onSurface;
    final all = math.max(total, attended + missed + pending);
    final toCome = all - attended - missed - pending;
    return Semantics(
      label: '$attended attended, $missed missed'
          '${pending > 0 ? ', $pending not marked yet' : ''}, $toCome to come',
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: all == 0
            ? null
            : Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(height / 2),
                    child: Stack(children: [
                      Positioned.fill(
                          child: LiquidBar(
                              value: attended / all,
                              height: height,
                              color: bad ? Tone.of(context).bad : Brand.lemon,
                              track: t.colorScheme.surfaceContainerLowest)),
                      Positioned.fill(
                          child: CustomPaint(
                              painter: _LostPainter(
                                  missed / all, pending / all, ink))),
                    ]),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(height / 2),
                          border: Border.all(color: ink, width: 2))),
                ),
                Positioned.fill(
                    child: CustomPaint(painter: _NeedPainter(min / 100, ink))),
              ]),
      ),
    );
  }
}

class _LostPainter extends CustomPainter {
  _LostPainter(this.missed, this.pending, this.ink);
  final double missed;
  final double pending;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final lost = size.width * (1 - missed);
    final line = Paint()
      ..color = ink.withOpacity(0.55)
      ..strokeWidth = 1.4;
    if (missed > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(lost, 0, size.width, size.height));
      for (var x = lost - size.height; x < size.width; x += 5) {
        canvas.drawLine(
            Offset(x, size.height), Offset(x + size.height, 0), line);
      }
      canvas.restore();
      canvas.drawLine(
          Offset(lost, 0),
          Offset(lost, size.height),
          Paint()
            ..color = ink.withOpacity(0.55)
            ..strokeWidth = 2);
    }
    if (pending > 0) {
      final from = lost - size.width * pending;
      final dot = Paint()..color = ink.withOpacity(0.5);
      for (var x = from + 3; x < lost - 1; x += 5) {
        for (var y = 4.5; y < size.height - 2; y += 5) {
          canvas.drawCircle(Offset(x, y), 0.9, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LostPainter old) =>
      old.missed != missed || old.pending != pending || old.ink != ink;
}

class _NeedPainter extends CustomPainter {
  _NeedPainter(this.at, this.ink);
  final double at;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * at;
    final dash = Paint()
      ..color = ink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = -2.0; y < size.height + 2; y += 6) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3), dash);
    }
  }

  @override
  bool shouldRepaint(_NeedPainter old) => old.at != at || old.ink != ink;
}

/// Lemon drops: one for each class that can still be missed, up to six.
class Drops extends StatelessWidget {
  const Drops(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < count.clamp(0, 6); i++)
            Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                    color: Brand.lemon,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 1.5))),
        ]),
      );
}
