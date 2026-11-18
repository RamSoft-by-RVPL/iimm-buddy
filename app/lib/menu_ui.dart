import 'package:flutter/material.dart';

import 'background.dart';
import 'crony_ui.dart';
import 'menu.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];

IconData _mealIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('break')) return Icons.free_breakfast_outlined;
  if (n.contains('snack') || n.contains('tea')) return Icons.coffee_outlined;
  if (n.contains('dinner')) return Icons.dinner_dining_outlined;
  return Icons.lunch_dining_outlined;
}

String _dayName(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final n = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (n == 0) return 'Today';
  if (n == 1) return 'Tomorrow';
  return _weekdays[d.weekday - 1];
}

/// The next meal, for the home screen. Hidden when there is no menu.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.store, required this.onChanged});
  final Store store;

  /// Favourites were changed on the menu screen.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final days = store.menu;
    final favs = store.favDishes;
    final next = nextMeal(days, now);
    final later = next == null ? firstMenuDay(days, now) : null;
    if (next == null && later == null) return const SizedBox.shrink();
    Future<void> open() async {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => MenuScreen(store: store)));
      onChanged();
    }

    // The menu starts on a later day: say so and lead to it.
    final (icon, title, body) = next == null
        ? (
            Icons.restaurant_menu_outlined,
            'Menu from ${fmtDate(later!.date)}',
            'The next menu is up. Tap to see every day.'
          )
        : (
            _mealIcon(next.$2.name),
            '${next.$2.name} · ${_dayName(next.$1.date, now)}',
            next.$2.items.join(' · ')
          );
    final liked = next == null
        ? const <String>[]
        : [
            for (final i in next.$2.items)
              if (isFavourite(i, favs)) i
          ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Mess menu',
          trailing: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Whole week',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      Card(
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 8),
                      if (next == null)
                        Text(body,
                            style: t.textTheme.bodyMedium?.copyWith(
                                color: t.colorScheme.onSurfaceVariant))
                      else
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final i in next.$2.items)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: liked.contains(i)
                                      ? t.colorScheme.primary
                                      : t.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(99)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (liked.contains(i)) ...[
                                      Icon(Icons.favorite,
                                          size: 13,
                                          color: t.colorScheme.onPrimary),
                                      const SizedBox(width: 5),
                                    ],
                                    Text(i,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: liked.contains(i)
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: liked.contains(i)
                                                ? t.colorScheme.onPrimary
                                                : t.colorScheme.onSurface)),
                                  ]),
                            ),
                        ]),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Dishes people often look out for, offered as one-tap favourites.
const _suggested = [
  'Paneer',
  'Biryani',
  'Chicken',
  'Egg',
  'Ice Cream',
  'Gulab Jamun',
  'Pav Bhaji',
  'Chole Bhature',
  'Dosa',
  'Pasta',
  'Noodles',
  'Rajma',
];

/// Choose favourite dishes. Returns when the sheet is closed.
Future<void> editFavourites(BuildContext context, Store store) async {
  final input = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final t = Theme.of(ctx);
      final favs = store.favDishes;
      void save(List<String> l) {
        store.favDishes = l;
        set(() {});
        scheduleDishAlerts(store).catchError((_) {});
      }

      void add(String raw) {
        final d = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (d.isEmpty || d.length > 40) return;
        if (favs.any((f) => f.toLowerCase() == d.toLowerCase())) return;
        save([...favs, d]);
        input.clear();
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHead('Favourite dishes',
                    subtitle: 'When one is on the menu you get a note before '
                        'that meal. A word is enough: "Paneer" covers every '
                        'paneer dish.'),
                if (favs.isNotEmpty) ...[
                  FieldLabel('Your dishes · ${favs.length}'),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final f in favs)
                      InputChip(
                        label: Text(f),
                        avatar: Icon(Icons.favorite,
                            size: 16, color: t.colorScheme.primary),
                        onDeleted: () => save([
                          for (final x in favs)
                            if (x != f) x
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: input,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: add,
                  decoration: InputDecoration(
                    labelText: 'Add a dish',
                    hintText: 'Paneer, Biryani, Ice Cream',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => add(input.text)),
                  ),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Suggestions'),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final d in _suggested)
                    if (!favs.any((f) => f.toLowerCase() == d.toLowerCase()))
                      ActionChip(label: Text(d), onPressed: () => add(d)),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tell me before the meal'),
                  value: store.dishAlerts,
                  onChanged: (v) {
                    store.dishAlerts = v;
                    set(() {});
                    scheduleDishAlerts(store).catchError((_) {});
                  },
                ),
              ]),
        ),
      );
    }),
  );
}

/// Every published day, one tab each, starting today. A heart beside each
/// dish marks it as a favourite.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.store});
  final Store store;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Store get store => widget.store;

  /// Tapping a heart: a dish that is not a favourite becomes one; one that
  /// is stops being one (with every favourite word that matched it).
  void _toggle(String item) {
    final favs = store.favDishes;
    store.favDishes = isFavourite(item, favs)
        ? [
            for (final f in favs)
              if (!isFavourite(item, [f])) f
          ]
        : [...favs, item];
    setState(() {});
    scheduleDishAlerts(store).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = store.menu;
    final favs = store.favDishes;
    final today = DateTime(now.year, now.month, now.day);
    final shown = [
      for (final d in days)
        if (!d.date.isBefore(today)) d
    ];
    final heart = IconButton(
      tooltip: 'Favourite dishes',
      icon: Icon(favs.isEmpty ? Icons.favorite_border : Icons.favorite),
      onPressed: () async {
        await editFavourites(context, store);
        if (mounted) setState(() {});
      },
    );
    if (shown.isEmpty) {
      return Scaffold(
          appBar: screenBar('Mess menu', actions: [heart]),
          body: const Center(
            child: EmptyNote(
                icon: Icons.restaurant_outlined,
                title: 'No menu yet',
                text: 'The menu shows here once it is published.'),
          ));
    }
    final next = nextMeal(days, now);
    final likedToday = [
      for (final m in shown.first.date == today ? shown.first.meals : <Meal>[])
        for (final i in m.items)
          if (isFavourite(i, favs)) i
    ];
    return DefaultTabController(
      length: shown.length,
      child: Scaffold(
        appBar: screenBar('Mess menu',
            subtitle: likedToday.isEmpty
                ? '${shown.length} ${shown.length == 1 ? 'day' : 'days'} published'
                : '${likedToday.length} of your favourites today',
            actions: [heart]),
        body: Column(children: [
          _DayStrip(days: shown, today: today),
          Expanded(
            child: TabBarView(children: [
              for (final d in shown)
                _dayView(context, d, today, now, next, favs),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dayView(BuildContext context, MenuDay d, DateTime today, DateTime now,
      (MenuDay, Meal)? next, List<String> favs) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final nextAt = next != null && next.$1 == d ? d.meals.indexOf(next.$2) : -1;
    final isToday = d.date == today;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        SectionTitle(d.date.difference(today).inDays <= 1
            ? '${_dayName(d.date, now)}, ${fmtDate(d.date)}'
            : fmtDate(d.date)),
        if (d.meals.isEmpty)
          const EmptyNote(
              icon: Icons.no_meals_outlined, title: 'No meals listed this day'),
        for (final (i, m) in d.meals.indexed)
          Rise(
            index: i,
            child: i == nextAt
                ? _NextMeal(m, favs: favs, onTap: _toggle)
                : Opacity(
                    opacity: isToday && nextAt > i ? 0.55 : 1,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 16, 8),
                              child: Row(children: [
                                IconTile(_mealIcon(m.name)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(m.name,
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.3)),
                                ),
                                if (isToday && nextAt > i)
                                  Text('Over',
                                      style:
                                          TextStyle(fontSize: 13, color: muted))
                                else
                                  Text(
                                      '${m.items.length} '
                                      '${m.items.length == 1 ? 'dish' : 'dishes'}',
                                      style: TextStyle(
                                          fontSize: 13, color: muted)),
                              ]),
                            ),
                            for (final x in m.items)
                              _Dish(x,
                                  liked: isFavourite(x, favs),
                                  onTap: () => _toggle(x)),
                            const SizedBox(height: 6),
                          ]),
                    ),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.favorite_border, size: 15, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Tap a heart to hear when that dish is on the menu. '
                  'From the mess\'s weekly menu; the mess may change a '
                  'dish on the day.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: muted)),
            ),
          ]),
        ),
      ],
    );
  }
}

/// The days of the menu as a row of dates, following the swipe.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.days, required this.today});
  final List<MenuDay> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = DefaultTabController.of(context);
    final dark = t.brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => SizedBox(
        height: 74,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          children: [
            for (final (i, d) in days.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => c.animateTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: const Cubic(0.23, 1, 0.32, 1),
                    width: 52,
                    decoration: BoxDecoration(
                      color: c.index == i
                          ? (dark ? Brand.wineDark : Brand.wine)
                          : t.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              d.date == today
                                  ? 'Today'
                                  : _weekdays[d.date.weekday - 1]
                                      .substring(0, 3),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: c.index == i
                                      ? Brand.wineInk.withOpacity(0.8)
                                      : t.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text('${d.date.day}',
                              style: TextStyle(
                                  fontSize: 19,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: c.index == i
                                      ? Brand.wineInk
                                      : t.colorScheme.onSurface)),
                        ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The coming meal, raised in wine so it is the first thing seen.
class _NextMeal extends StatelessWidget {
  const _NextMeal(this.m, {required this.favs, required this.onTap});
  final Meal m;
  final List<String> favs;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
          color: dark ? Brand.wineDark : Brand.wine,
          borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_mealIcon(m.name), size: 20, color: Brand.lime),
          const SizedBox(width: 8),
          const Text('UP NEXT',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Brand.lime)),
        ]),
        const SizedBox(height: 6),
        Text(m.name,
            style: const TextStyle(
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.9,
                color: Brand.wineInk)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in m.items)
            Material(
              color: isFavourite(x, favs)
                  ? Brand.lime
                  : Brand.wineInk.withOpacity(0.12),
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => onTap(x),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        isFavourite(x, favs)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 15,
                        color: isFavourite(x, favs)
                            ? Brand.wine
                            : Brand.wineInk.withOpacity(0.7)),
                    const SizedBox(width: 6),
                    Text(x,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isFavourite(x, favs)
                                ? Brand.wine
                                : Brand.wineInk)),
                  ]),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Dish extends StatelessWidget {
  const _Dish(this.name, {required this.liked, required this.onTap});
  final String name;
  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: liked ? t.colorScheme.primary.withOpacity(0.07) : null,
        padding: const EdgeInsets.fromLTRB(66, 10, 16, 10),
        child: Row(children: [
          Expanded(
            child: Text(name,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: liked ? FontWeight.w600 : FontWeight.w400,
                    color: liked ? t.colorScheme.primary : null)),
          ),
          Icon(liked ? Icons.favorite : Icons.favorite_border,
              size: 19,
              color: liked
                  ? t.colorScheme.primary
                  : t.colorScheme.onSurfaceVariant.withOpacity(0.45)),
        ]),
      ),
    );
  }
}
