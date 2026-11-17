import 'package:flutter/material.dart';

import 'menu.dart';
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
  const MenuCard({super.key, required this.days});
  final List<MenuDay> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final next = nextMeal(days, now);
    final later = next == null ? firstMenuDay(days, now) : null;
    if (next == null && later == null) return const SizedBox.shrink();
    void open() => Navigator.push(context,
        MaterialPageRoute(builder: (_) => MenuScreen(days: days, now: now)));
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
                    ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Every published day, one tab each, starting today.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.days, required this.now});
  final List<MenuDay> days;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
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
                SectionTitle('${_dayName(d.date, now)}, ${fmtDate(d.date)}'),
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
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(i, style: t.textTheme.bodyMedium),
                              ),
                          ]),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                      'From the mess\'s weekly menu. The mess may change '
                      'a dish on the day.',
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
