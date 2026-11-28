// The mess menu, published for everyone a week at a time.

import 'dart:convert';

import 'notify.dart';

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

/// The mess hours as posted at the counter, in minutes from midnight.
/// The menu itself has no times; these decide which meal is next and when
/// one is being served.
(int, int) _hours(String meal, int index) {
  const breakfast = (7 * 60 + 30, 10 * 60 + 15);
  const lunch = (12 * 60 + 10, 15 * 60);
  const snacks = (17 * 60, 18 * 60 + 15);
  const dinner = (20 * 60 + 15, 22 * 60 + 30);
  final n = meal.toLowerCase();
  if (n.contains('break')) return breakfast;
  if (n.contains('brunch') || n.contains('lunch')) return lunch;
  if (n.contains('snack') || n.contains('tea')) return snacks;
  if (n.contains('dinner') || n.contains('supper')) return dinner;
  return const [breakfast, lunch, snacks, dinner][index.clamp(0, 3)];
}

int _endsAt(String meal, int index) => _hours(meal, index).$2;

String _clock(int m, {bool half = true}) {
  final h = m ~/ 60 % 12 == 0 ? 12 : m ~/ 60 % 12;
  final t = '$h:${(m % 60).toString().padLeft(2, '0')}';
  return half ? '$t ${m < 12 * 60 ? 'am' : 'pm'}' : t;
}

/// When a meal is served, as "12:10 to 3:00 pm".
String mealHours(String meal, int index) {
  final (a, b) = _hours(meal, index);
  final same = (a < 12 * 60) == (b < 12 * 60);
  return '${_clock(a, half: !same)} to ${_clock(b)}';
}

/// When a meal is over, as "3:00 pm".
String mealEnds(String meal, int index) => _clock(_hours(meal, index).$2);

/// Whether the mess has begun serving this meal by [now] (it may be over).
bool mealBegun(String meal, int index, DateTime now) =>
    now.hour * 60 + now.minute >= _hours(meal, index).$1;

/// Whether the mess is serving this meal at [now].
bool isServing(String meal, int index, DateTime now) {
  final (a, b) = _hours(meal, index);
  final m = now.hour * 60 + now.minute;
  return m >= a && m < b;
}

const _sides = [
  'salad', 'chapati', 'fulka', 'roti', 'plain rice', 'curd rice', 'jeera rice',
  'papad', 'pickle', 'bread', 'tea', 'coffee', 'milk', 'banana', 'fruit',
  'sauce', 'onion', 'lemon', 'rasna', 'buttermilk', 'curd',
];

/// Whether a dish comes with nearly every meal (rice, chapati, pickle). These
/// are shown quieter so the day's own dishes stand out; nothing is hidden.
bool isSide(String item) => _sideWords.hasMatch(item);

final _sideWords =
    RegExp('\\b(${_sides.join('|')})\\b', caseSensitive: false);

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

/// The first day from today on that has a menu, for when the next meal is
/// not known yet (the menu starts later in the week, or next week).
MenuDay? firstMenuDay(List<MenuDay> days, DateTime now) {
  final today = _day(now);
  for (final d in days) {
    if (!d.date.isBefore(today) && d.meals.isNotEmpty) return d;
  }
  return null;
}

// ---- favourite dishes

List<String> _words(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z ]'), ' ')
    .split(' ')
    .where((w) => w.length > 1)
    .toList();

/// Two words are the same dish word despite the mess's spelling
/// ("Biriyani" and "Biryani", "Kolhapuri" and "Kolapuri").
bool _sameWord(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  // One letter added, dropped or changed.
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// True when a menu item is one of the student's favourites: every word of
/// the favourite is in the item ("Paneer" matches "Paneer Kolhapuri").
bool isFavourite(String item, List<String> favourites) {
  final have = _words(item);
  for (final f in favourites) {
    final want = _words(f);
    if (want.isNotEmpty &&
        want.every((w) => have.any((h) => _sameWord(w, h)))) {
      return true;
    }
  }
  return false;
}

/// When to say a favourite is coming: a while before each meal.
(int, int) _alertAt(String meal, int index) {
  final n = meal.toLowerCase();
  if (n.contains('break')) return (7, 15);
  if (n.contains('lunch') || n.contains('brunch')) return (12, 0);
  if (n.contains('snack') || n.contains('tea')) return (16, 30);
  if (n.contains('dinner') || n.contains('supper')) return (19, 15);
  return const [(7, 15), (12, 0), (16, 30), (19, 15)][index.clamp(0, 3)];
}

String _list(List<String> l) => l.length == 1
    ? l.first
    : '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';

/// One reminder for each meal of the coming week that has a favourite.
List<Reminder> dishReminders(List<MenuDay> days, List<String> favourites) {
  if (favourites.isEmpty) return [];
  final out = <Reminder>[];
  for (var d = 0; d < days.length && d < 21; d++) {
    final day = days[d];
    for (var m = 0; m < day.meals.length && m < 8; m++) {
      final meal = day.meals[m];
      final hits = [
        for (final i in meal.items)
          if (isFavourite(i, favourites)) i
      ];
      if (hits.isEmpty) continue;
      final (h, min) = _alertAt(meal.name, m);
      final name = meal.name.toLowerCase();
      final when = name.contains('dinner') ? 'tonight' : 'today';
      out.add(Reminder(
          920000 + d * 10 + m,
          DateTime(day.date.year, day.date.month, day.date.day, h, min),
          '${hits.first} at $name $when',
          hits.length == 1
              ? 'One of your favourites is on the menu.'
              : '${_list(hits)} are on the menu.',
          open: 'menu'));
    }
  }
  return out;
}
