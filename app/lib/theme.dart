// The app's look: warm paper surfaces, wine as the one brand colour, lime only
// for Crony's crest and the "can still skip" marks, and Geist throughout.

import 'package:flutter/material.dart';

import 'mascot.dart';

/// Brand colours used outside the colour scheme (the mascot, the Now card).
class Brand {
  static const wine = Color(0xFF4A1F28);
  static const wineDark = Color(0xFF5C2733);
  static const wineInk = Color(0xFFF7F1EC);
  static const wineMuted = Color(0xFFDCC9C6);
  static const lime = Color(0xFFD6EE4A);
  static const limeDeep = Color(0xFFA3BA14);
}

ThemeData appTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final ink = dark ? const Color(0xFFF1EEE9) : const Color(0xFF191714);
  final ink2 = dark ? const Color(0xFFA9A39B) : const Color(0xFF5F5A52);
  final scheme =
      ColorScheme.fromSeed(seedColor: Brand.wine, brightness: b).copyWith(
    primary: dark ? const Color(0xFFE6BFC6) : Brand.wine,
    onPrimary: dark ? const Color(0xFF3A1219) : Brand.wineInk,
    primaryContainer: dark ? const Color(0xFF3A2229) : const Color(0xFFF0E5E2),
    onPrimaryContainer: dark ? const Color(0xFFF0DADD) : Brand.wine,
    secondaryContainer:
        dark ? const Color(0xFF26242A) : const Color(0xFFECE9E3),
    onSecondaryContainer: ink,
    tertiary: dark ? Brand.lime : Brand.limeDeep,
    surface: dark ? const Color(0xFF121113) : const Color(0xFFF3F1EC),
    onSurface: ink,
    onSurfaceVariant: ink2,
    surfaceContainerLowest:
        dark ? const Color(0xFF0D0C0E) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        dark ? const Color(0xFF1B1A1D) : const Color(0xFFFFFFFF),
    surfaceContainer: dark ? const Color(0xFF1F1D21) : const Color(0xFFEEEBE5),
    surfaceContainerHigh:
        dark ? const Color(0xFF26242A) : const Color(0xFFE8E4DD),
    surfaceContainerHighest:
        dark ? const Color(0xFF2E2B31) : const Color(0xFFE1DDD5),
    outline: dark ? const Color(0xFF6C6770) : const Color(0xFF9A948A),
    outlineVariant: dark ? const Color(0xFF2A282D) : const Color(0xFFE4E1DA),
    surfaceTint: Colors.transparent,
  );
  final base =
      ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Geist');
  final text = base.textTheme;
  TextStyle? tight(TextStyle? s, FontWeight w, double spacing) =>
      s?.copyWith(fontWeight: w, letterSpacing: spacing);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displaySmall: tight(text.displaySmall, FontWeight.w700, -1.6),
      headlineMedium: tight(text.headlineMedium, FontWeight.w700, -1.0),
      headlineSmall: tight(text.headlineSmall, FontWeight.w700, -0.8),
      titleLarge: tight(text.titleLarge, FontWeight.w600, -0.4),
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
      titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          color: scheme.onSurface),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: dark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Geist',
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
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
            s.contains(WidgetState.selected)
                ? (dark ? Brand.wine : Colors.white)
                : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? (dark ? const Color(0xFFE6BFC6) : Brand.wine)
                : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? Colors.transparent
                : scheme.outline.withOpacity(0.5))),
    checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    tabBarTheme: TabBarTheme(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant,
        labelStyle: const TextStyle(
            fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500)),
    expansionTileTheme:
        const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            textStyle: const TextStyle(
                fontFamily: 'Geist', fontWeight: FontWeight.w600, fontSize: 15),
            shape: const StadiumBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            side: BorderSide(color: scheme.outline.withOpacity(0.5)),
            shape: const StadiumBorder())),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            textStyle: const TextStyle(
                fontFamily: 'Geist', fontWeight: FontWeight.w600))),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
            selectedBackgroundColor: scheme.surfaceContainerLow,
            backgroundColor: scheme.surfaceContainer,
            side: BorderSide.none)),
    chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant)),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary, linearTrackColor: scheme.surfaceContainerHigh),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF2E2B31) : const Color(0xFF191714),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerLow,
        titleTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: scheme.onSurface),
        contentTextStyle: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            height: 1.45,
            color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        dragHandleColor: scheme.outline.withOpacity(0.4),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant)),
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
          : Tone._(const Color(0xFF1E6B40), const Color(0xFF9A5400),
              const Color(0xFFB3261E));
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
              style: t.textTheme.labelMedium
                  ?.copyWith(color: c, fontWeight: FontWeight.w600)),
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
          child: Text(text,
              style: t.textTheme.titleMedium
                  ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0, 1),
              minHeight: 6,
              color: color,
              backgroundColor: t.colorScheme.surfaceContainerHighest,
            ),
          ),
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
/// with the last few in lime: the classes that can still be missed, as on
/// the app icon.
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
        painter: _PunchPainter(ticks, {
          Punch.attended: t.colorScheme.onSurface,
          Punch.missed: tone.bad,
          Punch.pending: tone.warn,
          Punch.due: t.colorScheme.onSurface.withOpacity(dark ? 0.16 : 0.14),
          Punch.spare: dark ? Brand.lime : Brand.limeDeep,
        }),
      ),
    );
  }
}

class _PunchPainter extends CustomPainter {
  _PunchPainter(this.ticks, this.colors);
  final List<Punch> ticks;
  final Map<Punch, Color> colors;

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
    }
  }

  @override
  bool shouldRepaint(_PunchPainter old) =>
      old.ticks != ticks || old.colors != colors;
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
        const Crony(mood: Mood.sleep, size: 64),
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
