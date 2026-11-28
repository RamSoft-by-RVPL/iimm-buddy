// Free time between classes, and friends who share theirs with a code.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'log.dart';
import 'site.dart';

/// A stretch of time in class. This is all a friend ever sees: no course,
/// no room, no attendance.
class Busy {
  const Busy(this.from, this.to);
  final DateTime from;
  final DateTime to;
}

/// A break shorter than this is a walk to the next room, not free time.
const shortBreak = Duration(minutes: 15);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Classes from the start of [from]'s day for [days] days, oldest first,
/// with back-to-back classes joined into one stretch.
List<Busy> busyOf(Iterable<ClassSlot> sessions, DateTime from,
    {int days = 14}) {
  final first = _day(from), last = first.add(Duration(days: days));
  final slots = [
    for (final s in sessions)
      if (!s.cancelled &&
          !s.date.isBefore(first) &&
          s.date.isBefore(last) &&
          s.endsAt.isAfter(s.startsAt))
        Busy(s.startsAt, s.endsAt)
  ]..sort((a, b) => a.from.compareTo(b.from));
  return joined(slots);
}

/// [slots] (sorted) with those that touch, overlap or sit a short break
/// apart on the same day made into one.
List<Busy> joined(List<Busy> slots) {
  final out = <Busy>[];
  for (final s in slots) {
    if (out.isNotEmpty &&
        _day(out.last.from) == _day(s.from) &&
        s.from.difference(out.last.to) < shortBreak) {
      final last = out.removeLast();
      out.add(Busy(last.from, s.to.isAfter(last.to) ? s.to : last.to));
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Where someone's day stands at one moment.
class FreeNow {
  const FreeNow(
      {required this.inClass,
      required this.classesToday,
      this.until,
      this.then});

  /// In a class right now.
  final bool inClass;

  /// Whether the day has any class at all.
  final bool classesToday;

  /// In class: when it lets out. Free: when the next class today starts
  /// (null when there is none left).
  final DateTime? until;

  /// In class: when the break after it ends (null: nothing more today).
  final DateTime? then;

  /// Free with nothing more today.
  bool get done => !inClass && until == null;
}

FreeNow freeAt(List<Busy> busy, DateTime now) {
  final today = [
    for (final b in busy)
      if (_day(b.from) == _day(now)) b
  ];
  for (final (i, b) in today.indexed) {
    if (!now.isBefore(b.from) && now.isBefore(b.to)) {
      return FreeNow(
          inClass: true,
          classesToday: true,
          until: b.to,
          then: i + 1 < today.length ? today[i + 1].from : null);
    }
  }
  for (final b in today) {
    if (b.from.isAfter(now)) {
      return FreeNow(inClass: false, classesToday: true, until: b.from);
    }
  }
  return FreeNow(inClass: false, classesToday: today.isNotEmpty);
}

/// "14:30".
String clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "45 min", "1 h", "2 h 15 min".
String span(Duration d) {
  final m = d.inMinutes < 1 ? 1 : d.inMinutes;
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

/// The headline and the line under it for the Today card.
(String, String) freeWords(FreeNow f, DateTime now) {
  if (f.inClass) {
    return (
      'In class till ${clock(f.until!)}',
      f.then == null
          ? 'Then you are done for the day'
          : 'Then free till ${clock(f.then!)}, ${span(f.then!.difference(f.until!))}'
    );
  }
  if (f.until != null) {
    return (
      'Free till ${clock(f.until!)}',
      '${span(f.until!.difference(now))} to yourself'
    );
  }
  return f.classesToday
      ? ('Done for the day', 'No more classes today')
      : ('No classes today', 'The whole day is yours');
}

// ---- friends

/// Someone whose code was added on this phone.
class Friend {
  const Friend(this.code, this.name, this.busy, this.updated);
  final String code;
  final String name;
  final List<Busy> busy;
  final DateTime updated;

  /// Their phone has not sent a timetable for a while: say nothing about
  /// where they are, it would be a guess.
  bool stale(DateTime now) => now.difference(updated).inDays >= 4;
}

DateTime? _at(String d, String t) {
  final a = d.split('-'), b = t.split(':');
  if (a.length != 3 || b.length != 2) return null;
  final n = [...a, ...b].map(int.tryParse).toList();
  if (n.contains(null)) return null;
  return DateTime(n[0]!, n[1]!, n[2]!, n[3]!, n[4]!);
}

/// [raw] is the server's answer to a request for some codes.
List<Friend> decodeFriends(String? raw) {
  try {
    return [
      for (final f in (jsonDecode(raw ?? '') as Map)['friends'] as List)
        Friend(
            '${f['code']}',
            '${f['name'] ?? ''}'.trim().isEmpty ? 'A friend' : '${f['name']}',
            joined([
              for (final b in (f['busy'] as List? ?? []))
                if (_at('${b['d']}', '${b['s']}') != null &&
                    _at('${b['d']}', '${b['e']}') != null)
                  Busy(_at('${b['d']}', '${b['s']}')!,
                      _at('${b['d']}', '${b['e']}')!)
            ]..sort((a, b) => a.from.compareTo(b.from))),
            DateTime.tryParse('${f['updated']}')?.toLocal() ?? DateTime(2000))
    ];
  } catch (_) {
    return [];
  }
}

/// What to say about a friend, and whether both are free right now.
(String, bool) friendWords(Friend f, List<Busy> mine, DateTime now) {
  if (f.stale(now)) return ('No timetable from their phone lately', false);
  final theirs = freeAt(f.busy, now), me = freeAt(mine, now);
  if (theirs.inClass) return ('In class till ${clock(theirs.until!)}', false);
  if (me.inClass) {
    return (
      theirs.until == null
          ? 'Free for the rest of the day'
          : 'Free till ${clock(theirs.until!)}',
      false
    );
  }
  final ends = [
    if (theirs.until != null) theirs.until!,
    if (me.until != null) me.until!
  ]..sort();
  return (
    ends.isEmpty
        ? 'Free with you for the rest of the day'
        : 'Free with you till ${clock(ends.first)}',
    true
  );
}

/// Letters and digits that are hard to mix up when read out.
const codeLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A typed or pasted code as the server knows it, or null when it cannot
/// be one.
String? cleanCode(String typed) {
  final c = typed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (c.length != 8) return null;
  for (final ch in c.split('')) {
    if (!codeLetters.contains(ch)) return null;
  }
  return c;
}

/// "ABCD-EFGH", easier to read out.
String showCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

String _two(int n) => n.toString().padLeft(2, '0');

/// What this phone sends when sharing is on: a first name and time blocks.
String sharePayload(String user, String studentName, List<Busy> busy) =>
    jsonEncode({
      'action': 'share',
      'user': user,
      'name': studentName.trim().split(RegExp(r'\s+')).first,
      'busy': [
        for (final b in busy.take(200))
          {
            'd': '${b.from.year}-${_two(b.from.month)}-${_two(b.from.day)}',
            's': clock(b.from),
            'e': clock(b.to)
          }
      ]
    });

/// This phone's code while it shares its free time, else null.
String? myCode(SharedPreferences prefs) => prefs.getString('free_code');

List<String> friendCodes(SharedPreferences prefs) =>
    prefs.getStringList('friend_codes') ?? const [];

/// Friends as last fetched, in the order they were added. A friend who
/// stopped sharing is no longer in the server's answer and drops out.
List<Friend> friendsOf(SharedPreferences prefs) {
  final got = {
    for (final f in decodeFriends(prefs.getString('friends'))) f.code: f
  };
  return [
    for (final c in friendCodes(prefs))
      if (got[c] != null) got[c]!
  ];
}

Map _json(String text) {
  try {
    return jsonDecode(text) as Map;
  } catch (_) {
    return {};
  }
}

/// Turns sharing on (or sends a changed timetable). Returns the code.
Future<String> shareFree(SharedPreferences prefs, Snapshot snap) async {
  final body = sharePayload(installId(prefs), snap.studentName,
      busyOf(snap.sessions, DateTime.now()));
  final (status, text) =
      await apiSend('POST', Uri.parse('$apiBase/api/free'), body: body);
  final j = _json(text);
  if (status != 200 || cleanCode('${j['code']}') == null) {
    throw Exception('${j['error'] ?? 'Could not share ($status)'}');
  }
  await prefs.setString('free_code', '${j['code']}');
  await prefs.setString('free_sent', body);
  return '${j['code']}';
}

/// Removes this phone's timetable from the server; the code stops working.
Future<void> stopSharing(SharedPreferences prefs) async {
  final (status, text) = await apiSend('POST', Uri.parse('$apiBase/api/free'),
      body: jsonEncode({'action': 'stop', 'user': installId(prefs)}));
  if (status != 200) {
    throw Exception('${_json(text)['error'] ?? 'Could not stop ($status)'}');
  }
  await prefs.remove('free_code');
  await prefs.remove('free_sent');
}

/// Fetches every added friend's time blocks, kept for showing offline.
Future<void> pullFriends(SharedPreferences prefs) async {
  final codes = friendCodes(prefs);
  if (codes.isEmpty) return;
  final (status, text) = await apiSend(
      'GET', Uri.parse('$apiBase/api/free?codes=${codes.join(',')}'));
  if (status != 200) return;
  await prefs.setString('friends', text);
  await prefs.setString('friends_at', DateTime.now().toIso8601String());
}

/// Adds a friend by their code. Throws with a sentence to show when the
/// code is not one, is this phone's own, or is not shared any more.
Future<Friend> addFriend(SharedPreferences prefs, String typed) async {
  final code = cleanCode(typed);
  if (code == null) {
    throw Exception('A code is 8 letters and digits, like ABCD-EF23.');
  }
  if (code == myCode(prefs)) throw Exception('That is your own code.');
  final codes = friendCodes(prefs);
  if (codes.contains(code)) throw Exception('Already added.');
  if (codes.length >= 30) throw Exception('30 friends at most.');
  final (status, text) =
      await apiSend('GET', Uri.parse('$apiBase/api/free?codes=$code'));
  if (status != 200) {
    throw Exception('${_json(text)['error'] ?? 'Could not check ($status)'}');
  }
  final found = decodeFriends(text);
  if (found.isEmpty) {
    throw Exception('No one is sharing with that code right now.');
  }
  await prefs.setStringList('friend_codes', [...codes, code]);
  final old =
      (_json(prefs.getString('friends') ?? '')['friends'] as List? ?? [])
          .where((f) => '${(f as Map)['code']}' != code);
  await prefs.setString(
      'friends',
      jsonEncode({
        'friends': [...old, ...(_json(text)['friends'] as List)]
      }));
  return found.first;
}

Future<void> removeFriend(SharedPreferences prefs, String code) =>
    prefs.setStringList('friend_codes', [
      for (final c in friendCodes(prefs))
        if (c != code) c
    ]);

/// After each refresh: sends this phone's time blocks when they changed,
/// and brings friends' up to date (at most every [every]).
Future<void> syncFree(SharedPreferences prefs, Snapshot snap,
    {Duration every = const Duration(minutes: 30)}) async {
  if (myCode(prefs) != null) {
    final body = sharePayload(installId(prefs), snap.studentName,
        busyOf(snap.sessions, DateTime.now()));
    if (body != prefs.getString('free_sent')) {
      try {
        await shareFree(prefs, snap);
      } catch (_) {}
    }
  }
  final at = DateTime.tryParse(prefs.getString('friends_at') ?? '');
  if (friendCodes(prefs).isNotEmpty &&
      (at == null || DateTime.now().difference(at) >= every)) {
    try {
      await pullFriends(prefs);
    } catch (_) {}
  }
}
