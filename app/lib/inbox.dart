// The list behind the bell: every notification the app has shown, newest
// first, kept on the phone for a few weeks.
//
// Three sources:
//  - notifications shown straight away ([notify]) are written here as they
//    are shown, from the app or from the background check;
//  - reminders scheduled for later (classes, deadlines, exams, calendar) are
//    saved when they are scheduled and count once their time has passed;
//  - messages from the admin page, which Android may show by itself, come
//    from the saved message list.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

class InboxItem {
  InboxItem(
      {required this.key,
      required this.at,
      required this.title,
      required this.body,
      required this.channel,
      this.open = 'home'});

  /// Same key means the same notification (never listed twice).
  final String key;
  final DateTime at;
  final String title;
  final String body;

  /// "classes", "moodle", "attendance" or "news".
  final String channel;

  /// Where tapping it leads, as for a tapped notification.
  final String open;

  Map<String, Object> toJson() => {
        'k': key,
        'at': at.millisecondsSinceEpoch,
        't': title,
        'b': body,
        'c': channel,
        'o': open,
      };

  static InboxItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'];
    if (at is! int || j['k'] is! String) return null;
    return InboxItem(
        key: j['k'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(at),
        title: '${j['t'] ?? ''}',
        body: '${j['b'] ?? ''}',
        channel: '${j['c'] ?? 'news'}',
        open: '${j['o'] ?? 'home'}');
  }
}

const _listKey = 'inbox';
const _seenKey = 'inbox_seen';
const _clearedKey = 'inbox_cleared';

/// How long items are kept, and at most how many.
const inboxDays = 30;
const inboxMax = 200;

List<InboxItem> _decode(String? raw) {
  try {
    return [
      for (final j in jsonDecode(raw ?? '[]') as List)
        if (InboxItem.fromJson(j) case final i?) i
    ];
  } catch (_) {
    return [];
  }
}

/// Keeps the newest [inboxMax] items of the last [inboxDays] days, one per
/// key, newest first.
List<InboxItem> _tidy(Iterable<InboxItem> items, DateTime now) {
  final cut = now.subtract(const Duration(days: inboxDays));
  final seen = <String>{};
  final out = [
    for (final i in [...items]..sort((a, b) => b.at.compareTo(a.at)))
      if (i.at.isAfter(cut) && seen.add(i.key)) i
  ];
  return out.length > inboxMax ? out.sublist(0, inboxMax) : out;
}

/// Adds items to the saved list.
Future<void> inboxAdd(SharedPreferences prefs, List<InboxItem> items,
    {DateTime? now}) async {
  if (items.isEmpty) return;
  final t = now ?? DateTime.now();
  final list = _tidy([...items, ..._decode(prefs.getString(_listKey))], t);
  await prefs.setString(
      _listKey, jsonEncode([for (final i in list) i.toJson()]));
}

/// The saved form of reminders scheduled under [key] (see
/// [scheduledItems]).
String scheduledKey(String key) => 'sched_$key';

/// Reminders saved under one kind, as they will appear once shown.
List<InboxItem> scheduledItems(SharedPreferences prefs, String key) =>
    _decode(prefs.getString(scheduledKey(key)));

/// Everything to list at [now]: saved items, reminders whose time has
/// passed and messages from the admin page. Newest first.
List<InboxItem> inboxItems(SharedPreferences prefs, DateTime now) {
  final cleared = prefs.getInt(_clearedKey) ?? 0;
  final all = <InboxItem>[
    ..._decode(prefs.getString(_listKey)),
    for (final k in prefs.getKeys())
      if (k.startsWith('sched_'))
        for (final i in _decode(prefs.getString(k)))
          if (!i.at.isAfter(now)) i,
    for (final n in decodeNotices(prefs.getString('notices')))
      InboxItem(
          key: 'notice:${n.id}',
          at: n.at,
          title: n.title,
          body: n.body,
          channel: 'news'),
  ];
  return [
    for (final i in _tidy(all, now))
      if (i.at.millisecondsSinceEpoch > cleared && !i.at.isAfter(now)) i
  ];
}

/// How many items came after the list was last opened.
int inboxUnread(SharedPreferences prefs, DateTime now) {
  final seen = prefs.getInt(_seenKey) ?? 0;
  return inboxItems(prefs, now)
      .where((i) => i.at.millisecondsSinceEpoch > seen)
      .length;
}

/// The time the list was last opened, before [inboxMarkSeen] moves it on.
DateTime inboxSeenAt(SharedPreferences prefs) =>
    DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_seenKey) ?? 0);

Future<void> inboxMarkSeen(SharedPreferences prefs, DateTime now) =>
    prefs.setInt(_seenKey, now.millisecondsSinceEpoch);

/// Empties the list. Reminders still to come stay scheduled and appear when
/// their time comes.
Future<void> inboxClear(SharedPreferences prefs, DateTime now) async {
  await prefs.setInt(_clearedKey, now.millisecondsSinceEpoch);
  await prefs.setInt(_seenKey, now.millisecondsSinceEpoch);
  await prefs.remove(_listKey);
}
