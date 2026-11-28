// Depth and movement: cards that lean under a finger, tabs that turn like
// pages and screens that slide over the one before. All of it stands still
// when the phone asks for less motion.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

const easeOut = Cubic(0.23, 1, 0.32, 1);
const easeInOut = Cubic(0.77, 0, 0.175, 1);
const easeDrawer = Cubic(0.32, 0.72, 0, 1);

/// How strongly far things shrink: 1 / the viewer's distance in pixels.
const depth = 0.0012;

/// A small click under the finger, for a choice that changed.
void tick() => HapticFeedback.selectionClick();

SpringDescription spring({double stiffness = 220, double ratio = 0.62}) =>
    SpringDescription.withDampingRatio(
        mass: 1, stiffness: stiffness, ratio: ratio);

/// Leans its child away from the finger pressing it, like a card on a pin,
/// and springs back on release. Taps and scrolling pass through untouched.
class Tilt extends StatefulWidget {
  const Tilt({super.key, required this.child, this.max = 0.085});
  final Widget child;

  /// The lean at the card's edge, in radians.
  final double max;

  /// How far the nearest [Tilt] above leans, each axis from -1 to 1.
  static ValueListenable<Offset>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Lean>()?.lean;

  @override
  State<Tilt> createState() => _TiltState();
}

class _TiltState extends State<Tilt> with TickerProviderStateMixin {
  late final AnimationController _x, _y;
  final _lean = ValueNotifier(Offset.zero);
  final _spring = spring();
  Offset? _down;

  /// A large card leans by a smaller angle, so its edges travel no further
  /// than a small card's.
  double _ease = 1;

  @override
  void initState() {
    super.initState();
    _x = AnimationController.unbounded(vsync: this)..addListener(_moved);
    _y = AnimationController.unbounded(vsync: this)..addListener(_moved);
  }

  void _moved() => _lean.value = Offset(_x.value, _y.value);

  // Ends exactly on its target, so a card at rest is drawn flat and sharp.
  void _to(Offset t) {
    _x
        .animateWith(SpringSimulation(_spring, _x.value, t.dx, _x.velocity))
        .whenComplete(() => _x.value = t.dx);
    _y
        .animateWith(SpringSimulation(_spring, _y.value, t.dy, _y.velocity))
        .whenComplete(() => _y.value = t.dy);
  }

  void _aim(PointerEvent e) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _ease = (230 / size.longestSide).clamp(0.22, 1.0);
    _to(Offset((e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0)));
  }

  void _release() {
    if (_down == null) return;
    _down = null;
    _to(Offset.zero);
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _lean.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _down = e.position;
        _aim(e);
      },
      onPointerMove: (e) {
        final from = _down;
        if (from == null) return;
        // A finger travelling down the page is scrolling, not pressing.
        if ((e.position.dy - from.dy).abs() > 14) return _release();
        _aim(e);
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: _Lean(
        lean: _lean,
        child: AnimatedBuilder(
          animation: _lean,
          builder: (_, child) => Transform(
            alignment: Alignment.center,
            transform: _lean.value == Offset.zero
                ? Matrix4.identity()
                : (Matrix4.identity()
                  ..setEntry(3, 2, depth)
                  ..rotateX(_lean.value.dy * widget.max * _ease)
                  ..rotateY(-_lean.value.dx * widget.max * _ease)),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _Lean extends InheritedWidget {
  const _Lean({required this.lean, required super.child});
  final ValueListenable<Offset> lean;

  @override
  bool updateShouldNotify(_Lean old) => old.lean != lean;
}

/// A card that leans under a finger, and stands up from lying back as the
/// screen it is on slides in.
class TiltCard extends StatelessWidget {
  const TiltCard(
      {super.key,
      this.child,
      this.color,
      this.margin,
      this.shape,
      this.clipBehavior,
      this.elevation});
  final Widget? child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    final card = Tilt(
        child: Card(
            color: color,
            margin: margin,
            shape: shape,
            clipBehavior: clipBehavior,
            elevation: elevation,
            child: child));
    final arriving = ModalRoute.of(context)?.animation;
    if (arriving == null || MediaQuery.of(context).disableAnimations) {
      return card;
    }
    return AnimatedBuilder(
      animation: arriving,
      builder: (_, child) {
        final u = arriving.status == AnimationStatus.forward
            ? 1 - easeOut.transform(arriving.value)
            : 0.0;
        return Transform(
          alignment: Alignment.topCenter,
          transform: u == 0
              ? Matrix4.identity()
              : (Matrix4.identity()
                ..setEntry(3, 2, depth)
                ..translate(0.0, 22 * u)
                ..rotateX(-0.42 * u)),
          child: child,
        );
      },
      child: card,
    );
  }
}

/// A hand-drawn line under the top bar that shows once the page has moved,
/// and ripples as it is scrolled, like the surface of a drink.
class LiquidEdge extends StatefulWidget implements PreferredSizeWidget {
  const LiquidEdge({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(6);

  @override
  State<LiquidEdge> createState() => _LiquidEdgeState();
}

class _LiquidEdgeState extends State<LiquidEdge> with TickerProviderStateMixin {
  late final AnimationController _shown, _ripple;
  final _spring = spring(stiffness: 90, ratio: 0.3);
  ScrollNotificationObserverState? _page;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _shown = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _ripple = AnimationController.unbounded(vsync: this);
  }

  void _scrolled(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return;
    final still = MediaQuery.of(context).disableAnimations;
    final moved = n.metrics.pixels - _offset;
    _offset = n.metrics.pixels;
    final show = _offset > 2 ? 1.0 : 0.0;
    if (still) {
      _shown.value = show;
      return;
    }
    if (_shown.status !=
            (show == 1 ? AnimationStatus.forward : AnimationStatus.reverse) &&
        _shown.value != show) {
      show == 1 ? _shown.forward() : _shown.reverse();
    }
    if (moved.abs() > 0.5) {
      _ripple
          .animateWith(SpringSimulation(_spring, _ripple.value, 0,
              (_ripple.velocity + moved * 0.05).clamp(-5.0, 5.0)))
          .whenComplete(() => _ripple.value = 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final page = ScrollNotificationObserver.maybeOf(context);
    if (page == _page) return;
    _page?.removeListener(_scrolled);
    _page = page?..addListener(_scrolled);
  }

  @override
  void dispose() {
    _page?.removeListener(_scrolled);
    _shown.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: const Size(double.infinity, 6),
          painter: _EdgePainter(_shown, _ripple, () => _offset,
              Theme.of(context).colorScheme.onSurface),
        ),
      );
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.shown, this.ripple, this.offset, this.ink)
      : super(repaint: Listenable.merge([shown, ripple]));
  final Animation<double> shown;
  final AnimationController ripple;
  final double Function() offset;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (shown.value == 0) return;
    final swell = 0.9 + (ripple.value.abs() * 10).clamp(0.0, 2.2);
    // The ripples travel as the page moves under them.
    final phase = offset() / 26 + ripple.value * 6;
    final line = Path();
    for (var x = 0.0; x <= size.width; x += 3) {
      final y = size.height / 2 + swell * math.sin(x / 15 + phase);
      x == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = ink.withOpacity(0.85 * shown.value));
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.ink != ink;
}

/// Brings a tab in from the side it sits on, turning a little like a page.
class TabTurn extends StatefulWidget {
  const TabTurn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<TabTurn> createState() => _TabTurnState();
}

class _TabTurnState extends State<TabTurn> {
  int _dir = 0;

  @override
  void didUpdateWidget(TabTurn old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.index),
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: easeOut,
      builder: (_, v, child) {
        final u = 1 - v;
        return Opacity(
          opacity: v,
          child: Transform(
            alignment: Alignment.center,
            transform: u == 0
                ? Matrix4.identity()
                : _dir == 0
                    ? Matrix4.translationValues(0, 6 * u, 0)
                    : (Matrix4.identity()
                      ..setEntry(3, 2, depth)
                      ..translate(_dir * 22.0 * u)
                      ..rotateY(-_dir * 0.12 * u)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A new screen slides over from the right while the one under it steps
/// back and dims; going back plays the same in reverse.
class DepthPageTransitionsBuilder extends PageTransitionsBuilder {
  const DepthPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.of(context).disableAnimations) {
      return FadeTransition(opacity: animation, child: child);
    }
    final over = CurvedAnimation(
        parent: animation, curve: easeDrawer, reverseCurve: Curves.easeIn);
    final under = CurvedAnimation(
        parent: secondaryAnimation,
        curve: easeDrawer,
        reverseCurve: Curves.easeIn);
    return AnimatedBuilder(
      animation: Listenable.merge([over, under]),
      builder: (context, child) {
        final a = over.value, b = under.value;
        Widget page = child!;
        if (b > 0) {
          page = Stack(fit: StackFit.passthrough, children: [
            page,
            Positioned.fill(
                child: IgnorePointer(
                    child:
                        ColoredBox(color: Colors.black.withOpacity(0.16 * b)))),
          ]);
        }
        page = Transform(
          alignment: Alignment.center,
          transform: b == 0
              ? Matrix4.identity()
              : (Matrix4.identity()
                ..setEntry(3, 2, depth * 0.5)
                ..translate(0.0, 0.0, 70 * b)),
          child: FractionalTranslation(
              translation: Offset(1 - a, 0),
              child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [
                    if (a < 1)
                      BoxShadow(
                          color: Colors.black.withOpacity(0.18 * a),
                          blurRadius: 24,
                          offset: const Offset(-6, 0))
                  ]),
                  child: page)),
        );
        // What shows round a screen that has stepped back: the page colour,
        // dimmed like the screen itself.
        return b == 0
            ? page
            : ColoredBox(
                color: Color.alphaBlend(Colors.black.withOpacity(0.16 * b),
                    Theme.of(context).colorScheme.surface),
                child: page);
      },
      child: child,
    );
  }
}
