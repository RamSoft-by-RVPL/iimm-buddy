// One-tap ratings of mess meals, counted for everyone.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'log.dart';
import 'menu.dart';

/// What everyone said about one meal, and what this phone said.
class MealRating {
  const MealRating(this.day, this.meal, this.count, this.average, this.mine);
  final DateTime day;
  final String meal;
  final int count;

  /// 1 (poor) to 3 (good).
  final double average;

  /// This phone's rating, if it gave one.
  final int? mine;
}

const scoreWords = ['Poor', 'Okay', 'Good'];

/// "Poor", "Okay" or "Good" for an average.
String scoreWord(double average) => average < 1.67
    ? scoreWords[0]
    : (average < 2.34 ? scoreWords[1] : scoreWords[2]);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<MealRating> decodeRatings(String? raw) {
  try {
    return [
      for (final r in (jsonDecode(raw ?? '') as Map)['ratings'] as List)
        MealRating(
            DateTime.parse('${r['d']}'),
            '${r['meal']}',
            (r['n'] as num).toInt(),
            (r['avg'] as num).toDouble(),
            (r['mine'] as num?)?.toInt())
    ];
  } catch (_) {
    return [];
  }
}

List<MealRating> ratingsOf(SharedPreferences prefs) =>
    decodeRatings(prefs.getString('ratings'));

MealRating? ratingFor(List<MealRating> all, DateTime day, String meal) {
  for (final r in all) {
    if (r.day == _day(day) && r.meal == meal) return r;
  }
  return null;
}

/// A meal can be rated from the moment the mess starts serving it until
/// the end of the next day.
bool canRate(MenuDay d, int index, DateTime now) {
  final today = _day(now);
  if (d.date == today) return mealBegun(d.meals[index].name, index, now);
  return d.date == today.subtract(const Duration(days: 1));
}

/// The meal the home screen asks about: the latest one the mess has begun
/// serving today. It stays there once rated, showing what everyone said.
/// Null before breakfast, or when today has no menu.
(MenuDay, int)? mealToRate(List<MenuDay> days, DateTime now) {
  final today = menuOn(days, now);
  if (today == null) return null;
  for (var i = today.meals.length - 1; i >= 0; i--) {
    if (canRate(today, i, now)) return (today, i);
  }
  return null;
}

/// The best and the worst rated meal of the last week, once at least two
/// meals have [minVotes] ratings each and they differ.
(MealRating, MealRating)? bestAndWorst(List<MealRating> all,
    {int minVotes = 3}) {
  final enough = [
    for (final r in all)
      if (r.count >= minVotes) r
  ]..sort((a, b) {
      final c = b.average.compareTo(a.average);
      return c != 0 ? c : b.count.compareTo(a.count);
    });
  if (enough.length < 2 || enough.first.average == enough.last.average) {
    return null;
  }
  return (enough.first, enough.last);
}

Future<void> pullRatings(SharedPreferences prefs) async {
  final (status, text) = await apiSend(
      'GET', Uri.parse('$apiBase/api/ratings?user=${installId(prefs)}'));
  if (status != 200) return;
  await prefs.setString('ratings', text);
  await prefs.setString('ratings_at', DateTime.now().toIso8601String());
}

/// [pullRatings], but at most every [every]: the regular checks call this.
Future<void> syncRatings(SharedPreferences prefs,
    {Duration every = const Duration(minutes: 30)}) async {
  final at = DateTime.tryParse(prefs.getString('ratings_at') ?? '');
  if (at != null && DateTime.now().difference(at) < every) return;
  await pullRatings(prefs);
}

/// Rates a meal 1 to 3 (again to change it). Throws with a sentence to show.
Future<void> rateMeal(
    SharedPreferences prefs, DateTime day, String meal, int score) async {
  final (status, text) =
      await apiSend('POST', Uri.parse('$apiBase/api/ratings'),
          body: jsonEncode({
            'action': 'rate',
            'user': installId(prefs),
            'd': _iso(day),
            'meal': meal,
            'score': score
          }));
  Map j;
  try {
    j = jsonDecode(text) as Map;
  } catch (_) {
    j = {};
  }
  if (status != 200) {
    throw Exception('${j['error'] ?? 'Could not rate ($status)'}');
  }
  await prefs.setString('ratings', jsonEncode({'ratings': j['ratings'] ?? []}));
}
