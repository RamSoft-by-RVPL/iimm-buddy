// The mess menu, published for everyone a week at a time.

import 'dart:convert';

class Meal {
  Meal(this.name, this.items);
  final String name;
  final List<String> items;
}

class MenuDay {
  MenuDay(this.date, this.meals);
  final DateTime date;
  final List<Meal> meals;
}

/// Every published day, soonest first. [raw] is the server's answer.
List<MenuDay> decodeMenu(String? raw) {
  try {
    final out = <MenuDay>[];
    for (final w in (jsonDecode(raw ?? '{}') as Map)['weeks'] as List) {
      for (final d in (w as Map)['days'] as List) {
        final p = '${d['d']}'.split('-').map(int.parse).toList();
        out.add(MenuDay(DateTime(p[0], p[1], p[2]), [
          for (final m in d['meals'] as List)
            Meal('${m['n']}', [for (final i in m['items'] as List) '$i'])
        ]));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  } catch (_) {
    return [];
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

MenuDay? menuOn(List<MenuDay> days, DateTime day) {
  final want = _day(day);
  for (final d in days) {
    if (d.date == want) return d;
  }
  return null;
}

/// Roughly when each meal is over, to know which one is next. The menu
/// itself has no times, so these only decide what the home screen shows.
int _endsAt(String meal, int index) {
  final n = meal.toLowerCase();
  if (n.contains('break')) return 10 * 60;
  if (n.contains('brunch')) return 12 * 60;
  if (n.contains('lunch')) return 14 * 60 + 30;
  if (n.contains('snack') || n.contains('tea')) return 18 * 60 + 30;
  if (n.contains('dinner') || n.contains('supper')) return 22 * 60;
  return const [
    10 * 60,
    14 * 60 + 30,
    18 * 60 + 30,
    22 * 60
  ][index.clamp(0, 3)];
}

/// The meal to show now: the next one today, or tomorrow's first once
/// dinner is over. Null when the menu does not cover that day.
(MenuDay, Meal)? nextMeal(List<MenuDay> days, DateTime now) {
  final today = menuOn(days, now);
  final minute = now.hour * 60 + now.minute;
  if (today != null) {
    for (var i = 0; i < today.meals.length; i++) {
      if (minute < _endsAt(today.meals[i].name, i)) {
        return (today, today.meals[i]);
      }
    }
  }
  final tomorrow = menuOn(days, now.add(const Duration(days: 1)));
  if (tomorrow != null && tomorrow.meals.isNotEmpty) {
    return (tomorrow, tomorrow.meals.first);
  }
  return null;
}
