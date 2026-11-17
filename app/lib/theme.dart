// The app's look: calm neutral surfaces, one brand colour, and a few small
// building blocks every screen shares.

import 'package:flutter/material.dart';

const _brand = Color(0xFF9B1C1C);

ThemeData appTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(seedColor: _brand, brightness: b).copyWith(
    primary: dark ? const Color(0xFFFFB4AB) : _brand,
    onPrimary: dark ? const Color(0xFF5F1412) : Colors.white,
    primaryContainer: dark ? const Color(0xFF6E211D) : const Color(0xFFFBE3E0),
    onPrimaryContainer:
        dark ? const Color(0xFFFFDAD6) : const Color(0xFF5C0F0F),
    secondaryContainer:
        dark ? const Color(0xFF34302F) : const Color(0xFFF1ECEA),
    onSecondaryContainer:
        dark ? const Color(0xFFECE7E6) : const Color(0xFF2B2726),
    surface: dark ? const Color(0xFF121111) : const Color(0xFFF8F6F5),
    onSurface: dark ? const Color(0xFFECE7E6) : const Color(0xFF1C1A1A),
    onSurfaceVariant: dark ? const Color(0xFFB5AEAC) : const Color(0xFF615C5A),
    surfaceContainerLowest:
        dark ? const Color(0xFF0D0C0C) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        dark ? const Color(0xFF1A1919) : const Color(0xFFFFFFFF),
    surfaceContainer: dark ? const Color(0xFF1F1D1D) : const Color(0xFFF2EFEE),
    surfaceContainerHigh:
        dark ? const Color(0xFF292727) : const Color(0xFFECE8E7),
    surfaceContainerHighest:
        dark ? const Color(0xFF343131) : const Color(0xFFE5E1E0),
    outline: dark ? const Color(0xFF8E8785) : const Color(0xFF8A8482),
    outlineVariant: dark ? const Color(0xFF3A3736) : const Color(0xFFE2DCDA),
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
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
          ? Tone._(const Color(0xFF7FCB8A), const Color(0xFFF2B45A),
              const Color(0xFFFF8F87))
          : Tone._(const Color(0xFF1F7A36), const Color(0xFFA65F00),
              const Color(0xFFBF2A2A));
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
                  ?.copyWith(color: c, fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: t.textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: t.colorScheme.onSurfaceVariant)),
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
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
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
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: t.colorScheme.surfaceContainerHighest,
            ),
          ),
          Positioned(
            left: box.maxWidth * min / 100 - 1,
            child: Container(
                width: 2, height: 12, color: t.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
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
        Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(height: 10),
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
