import 'package:flutter/material.dart';

import 'background.dart';
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
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: t.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: t.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(body,
                          style: t.textTheme.bodyMedium?.copyWith(
                              color: t.colorScheme.onSurfaceVariant)),
                      if (liked.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.favorite,
                              size: 16, color: t.colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(liked.join(', '),
                                style: t.textTheme.bodyMedium?.copyWith(
                                    color: t.colorScheme.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ],
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
                Text('Favourite dishes', style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                    'When one is on the menu you get a note before that '
                    'meal. A word is enough: "Paneer" covers every paneer '
                    'dish.',
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (favs.isNotEmpty)
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
                const SizedBox(height: 8),
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
                const SizedBox(height: 12),
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
    final t = Theme.of(context);
    final now = DateTime.now();
    final days = store.menu;
    final favs = store.favDishes;
    final today = DateTime(now.year, now.month, now.day);
    final shown = [
      for (final d in days)
        if (!d.date.isBefore(today)) d
    ];
    if (shown.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Mess menu')),
          body: const EmptyNote(
              icon: Icons.restaurant_outlined,
              title: 'No menu yet',
              text: 'The menu shows here once it is published.'));
    }
    final next = nextMeal(days, now);
    return DefaultTabController(
      length: shown.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mess menu'),
          actions: [
            IconButton(
              tooltip: 'Favourite dishes',
              icon: Icon(favs.isEmpty ? Icons.favorite_border : Icons.favorite),
              onPressed: () async {
                await editFavourites(context, store);
                if (mounted) setState(() {});
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final d in shown)
                Tab(
                    text: d.date == today
                        ? 'Today'
                        : '${_weekdays[d.date.weekday - 1].substring(0, 3)} '
                            '${d.date.day}'),
            ],
          ),
        ),
        body: TabBarView(children: [
          for (final d in shown)
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
              children: [
                SectionTitle(d.date.difference(today).inDays <= 1
                    ? '${_dayName(d.date, now)}, ${fmtDate(d.date)}'
                    : fmtDate(d.date)),
                if (d.meals.isEmpty)
                  const Card(
                      child: ListTile(title: Text('No meals listed this day'))),
                for (final m in d.meals)
                  Card(
                    shape: next != null && next.$1 == d && next.$2 == m
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: t.colorScheme.primary, width: 1.5))
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(_mealIcon(m.name),
                                  size: 20, color: t.colorScheme.primary),
                              const SizedBox(width: 10),
                              Text(m.name,
                                  style: t.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 8),
                            for (final i in m.items)
                              _Dish(i,
                                  liked: isFavourite(i, favs),
                                  onTap: () => _toggle(i)),
                          ]),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                      'Tap a heart to hear when that dish is on the menu. '
                      'From the mess\'s weekly menu; the mess may change a '
                      'dish on the day.',
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
        ]),
      ),
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
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text(name,
                style: liked
                    ? t.textTheme.bodyMedium?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.w600)
                    : t.textTheme.bodyMedium),
          ),
          Icon(liked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: liked
                  ? t.colorScheme.primary
                  : t.colorScheme.onSurfaceVariant.withOpacity(0.5)),
        ]),
      ),
    );
  }
}
