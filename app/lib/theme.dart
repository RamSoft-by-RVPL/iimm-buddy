// The app's look, from the Lemonade logo: pink first, lemon second and black
// outlines like the logo's line. Schoolbell for titles, numbers and buttons,
// Geist for everything read in sentences.

import 'package:flutter/material.dart';

import 'mascot.dart';
import 'motion.dart';
import 'glass.dart';

/// Brand colours used outside the colour scheme (the mascot, the Now card).
class Brand {
  static const pink = Color(0xFFEC6989);
  static const onPink = Color(0xFF1A1113);
  static const onPinkMuted = Color(0xFF3D1520);
  static const lemon = Color(0xFFFAE474);
  static const lemonDeep = Color(0xFFE5BE12);
  static const edge = Color(0xFF1A1113);

  /// Schoolbell has one weight; asking for more would smear it.
  static TextStyle hand(double size, {Color? color, double? height}) =>
      TextStyle(
          fontFamily: 'Schoolbell',
          fontSize: size,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: height,
          color: color);

  /// A raised pink card: black outline and a hard offset shadow, like a sticker.
  static BoxDecoration sticker(BuildContext context,
      {Color color = pink, double radius = 22}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? Colors.black : edge;
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: line, width: 2),
      boxShadow: [BoxShadow(color: line, offset: const Offset(3, 4))],
    );
  }
}

ThemeData appTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final ink = dark ? const Color(0xFFFCEAF0) : const Color(0xFF1A1113);
  final ink2 = dark ? const Color(0xFFD8A9B9) : const Color(0xFF5E2E3C);
  final line = dark ? Colors.black : Brand.edge;
  final scheme =
      ColorScheme.fromSeed(seedColor: Brand.pink, brightness: b).copyWith(
    primary: dark ? Brand.lemon : const Color(0xFF1A1113),
    onPrimary: dark ? Brand.onPink : Brand.lemon,
    primaryContainer: Brand.lemon,
    onPrimaryContainer: Brand.onPink,
    secondaryContainer:
        dark ? const Color(0xFF3A1F2B) : const Color(0xFFFFBFD2),
    onSecondaryContainer: ink,
    tertiary: dark ? Brand.lemon : Brand.lemonDeep,
    surface: dark ? const Color(0xFF1C0E14) : const Color(0xFFFFD3E0),
    onSurface: ink,
    onSurfaceVariant: ink2,
    surfaceContainerLowest:
        dark ? const Color(0xFF140A0E) : const Color(0xFFFFFAFC),
    surfaceContainerLow:
        dark ? const Color(0xFF2A1720) : const Color(0xFFFFF5F8),
    surfaceContainer: dark ? const Color(0xFF2F1A23) : const Color(0xFFFFE3EC),
    surfaceContainerHigh:
        dark ? const Color(0xFF3A1F2B) : const Color(0xFFFFBFD2),
    surfaceContainerHighest:
        dark ? const Color(0xFF452632) : const Color(0xFFF9AFC6),
    outline: dark ? const Color(0xFF8F6573) : const Color(0xFF8E5A69),
    outlineVariant: dark ? const Color(0xFF3A1F2B) : const Color(0xFFF4B6C9),
    surfaceTint: Colors.transparent,
  );
  final base =
      ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Geist');
  final text = base.textTheme;
  TextStyle? hand(TextStyle? s, double size) => s?.copyWith(
      fontFamily: 'Schoolbell',
      fontSize: size,
      fontWeight: FontWeight.w400,
      letterSpacing: 0);
  TextStyle? tight(TextStyle? s, FontWeight w, double spacing) =>
      s?.copyWith(fontWeight: w, letterSpacing: spacing);
  final outlined = BorderSide(color: line, width: 2);
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: DepthPageTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displaySmall: hand(text.displaySmall, 40),
      headlineMedium: hand(text.headlineMedium, 32),
      headlineSmall: hand(text.headlineSmall, 28),
      titleLarge: hand(text.titleLarge, 24),
      titleMedium: tight(text.titleMedium, FontWeight.w600, -0.2),
      titleSmall: tight(text.titleSmall, FontWeight.w600, -0.1),
      labelLarge: tight(text.labelLarge, FontWeight.w600, 0),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Brand.hand(30, color: scheme.onSurface),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: outlined,
      ),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: Brand.lemon,
      indicatorShape: StadiumBorder(side: BorderSide(color: line, width: 2)),
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Brand.onPink
              : scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => Brand.hand(14,
          color: s.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        minVerticalPadding: 10,
        horizontalTitleGap: 14,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.15,
            color: scheme.onSurface),
        subtitleTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            height: 1.35,
            color: scheme.onSurfaceVariant)),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Brand.onPink : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? Brand.lemon
                : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? line : scheme.outline)),
    checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    tabBarTheme: TabBarTheme(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant,
        labelStyle: Brand.hand(18),
        unselectedLabelStyle: Brand.hand(18)),
    expansionTileTheme:
        const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            backgroundColor: Brand.lemon,
            foregroundColor: Brand.onPink,
            disabledBackgroundColor: scheme.surfaceContainerHigh,
            side: outlined,
            textStyle: Brand.hand(18),
            shape: const StadiumBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: scheme.onSurface,
            side: outlined,
            textStyle: Brand.hand(17),
            shape: const StadiumBorder())),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface, textStyle: Brand.hand(17))),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
            selectedBackgroundColor: Brand.lemon,
            selectedForegroundColor: Brand.onPink,
            backgroundColor: scheme.surfaceContainerLow,
            side: outlined,
            textStyle: Brand.hand(16))),
    chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: line, width: 1.5),
        selectedColor: Brand.lemon),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary, linearTrackColor: scheme.surfaceContainerHigh),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1113),
        actionTextColor: Brand.lemon,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerLow,
        titleTextStyle: Brand.hand(26, color: scheme.onSurface),
        contentTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            height: 1.45,
            color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28), side: outlined)),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        dragHandleColor: scheme.onSurface.withOpacity(0.4),
        shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            side: outlined)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: outlined),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: outlined),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line, width: 2.5)),
    ),
  );
}

/// Good, careful and bad, readable in light and dark.
class Tone {
  Tone._(this.good, this.warn, this.bad);
  final Color good;
  final Color warn;
  final Color bad;

  static Tone of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Tone._(const Color(0xFF7FD39D), const Color(0xFFF2B45C),
              const Color(0xFFFF8C82))
          : Tone._(const Color(0xFF1E6B40), const Color(0xFF7A4300),
              const Color(0xFFA3141C));
}

/// A small rounded label: "Can miss 3", "Present", "Not on portal yet".
class Pill extends StatelessWidget {
  const Pill(this.text,
      {super.key, this.color, this.icon, this.outlined = false});
  final String text;
  final Color? color;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? null : c.withOpacity(0.12),
        border: outlined ? Border.all(color: c.withOpacity(0.5)) : null,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Brand.hand(15, color: c, height: 1.1)),
        ),
      ]),
    );
  }
}

/// A heading above a group of cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(children: [
        Expanded(
          child:
              Text(text, style: Brand.hand(22, color: t.colorScheme.onSurface)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// One line of news at the top of a screen, with one thing to do about it.
class Strip extends StatelessWidget {
  const Strip(
      {super.key,
      required this.icon,
      required this.text,
      this.action,
      this.onAction,
      this.color,
      this.filled = false,
      this.inset = true});

  /// False when the parent already has side padding.
  final bool inset;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Container(
      margin: EdgeInsets.fromLTRB(inset ? 12 : 0, 4, inset ? 12 : 0, 4),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(text, style: t.textTheme.bodyMedium),
          ),
        ),
        if (action != null)
          filled
              ? FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: Text(action!))
              : TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

/// A progress bar with a tick where the minimum is.
class Meter extends StatelessWidget {
  const Meter(
      {super.key, required this.value, required this.min, required this.color});

  /// 0 to 100.
  final double value;
  final int min;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (_, box) => Stack(alignment: Alignment.centerLeft, children: [
          LiquidBar(value: (value / 100).clamp(0, 1), color: color),
          Positioned(
            left: box.maxWidth * min / 100 - 1,
            child: Container(
                width: 2,
                height: 12,
                decoration: BoxDecoration(
                    color: t.colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      ),
    );
  }
}

enum Punch { attended, missed, pending, due, spare }

/// One tick per class: the classes held so far, then the ones still to come,
/// with the last few in lemon: the classes that can still be missed.
class PunchStrip extends StatelessWidget {
  const PunchStrip(this.ticks, {super.key});
  final List<Punch> ticks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final dark = t.brightness == Brightness.dark;
    return SizedBox(
      height: 14,
      width: double.infinity,
      child: CustomPaint(
        painter: _PunchPainter(
            ticks,
            {
              Punch.attended: t.colorScheme.onSurface,
              Punch.missed: tone.bad,
              Punch.pending: tone.warn,
              Punch.due:
                  t.colorScheme.onSurface.withOpacity(dark ? 0.16 : 0.14),
              Punch.spare: Brand.lemon,
            },
            t.colorScheme.onSurface),
      ),
    );
  }
}

class _PunchPainter extends CustomPainter {
  _PunchPainter(this.ticks, this.colors, this.outline);
  final List<Punch> ticks;
  final Map<Punch, Color> colors;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ticks.length;
    if (n == 0) return;
    final gap = n > 60 ? 1.0 : 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    final r = Radius.circular(w < 4 ? w / 2 : 2);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final box = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      final p = ticks[i];
      if (p == Punch.due && w >= 4) {
        canvas.drawRRect(RRect.fromRectAndRadius(box.deflate(0.5), r),
            edge..color = colors[p]!);
        continue;
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, r), fill..color = colors[p]!);
      if (p == Punch.spare && w >= 4) {
        canvas.drawRRect(RRect.fromRectAndRadius(box.deflate(0.5), r),
            edge..color = outline);
      }
    }
  }

  @override
  bool shouldRepaint(_PunchPainter old) =>
      old.ticks != ticks || old.colors != colors || old.outline != outline;
}

/// A friendly message for a screen with nothing to show.
class EmptyNote extends StatelessWidget {
  const EmptyNote(
      {super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(children: [
        const Crony(mood: Mood.sleep, size: 64, play: true),
        const SizedBox(height: 12),
        Text(title,
            style: t.textTheme.titleMedium, textAlign: TextAlign.center),
        if (text != null) ...[
          const SizedBox(height: 4),
          Text(text!,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
