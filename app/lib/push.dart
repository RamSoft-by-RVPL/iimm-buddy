// Instant delivery through Firebase Cloud Messaging.
//
// The server pushes a small message the moment something changes (a message
// from the admin, a new timetable, a new app version). The phone then does
// what it would have done at its next regular check, only at once. If push
// is not available on a phone (no Google services), nothing breaks: the
// regular checks still bring everything, a little later.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'background.dart';
import 'log.dart';
import 'notify.dart';
import 'site.dart';
import 'update.dart';

/// Changes whenever a push was handled while the app is open, so the screen
/// can show the new data.
final pushArrived = ValueNotifier<int>(0);

/// Acts on one push. [shown] is true when Android has already displayed the
/// message itself (the app was not in front).
Future<void> handlePush(SharedPreferences prefs, Map<String, dynamic> data,
    {required bool shown}) async {
  final type = '${data['type'] ?? ''}';
  logEvent(prefs, 'push_in', type);
  final store = Store(prefs);
  try {
    if (type == 'notice') {
      final id = int.tryParse('${data['id']}');
      if (shown && id != null && !(seenNotices(prefs)?.contains(id) ?? false)) {
        // Android showed it already: do not show it a second time later.
        await markNoticesSeen(prefs, [id]);
        logEvent(prefs, 'notice_got', '#$id');
      }
      for (final n in await pullNotices(prefs)) {
        await notify(900000 + n.id % 90000, n.title, n.body, 'news',
            key: 'notice:${n.id}');
        logEvent(prefs, 'notice_got', '#${n.id}');
      }
    } else if (type == 'timetable' ||
        type == 'menu' ||
        type == 'exams' ||
        type == 'calendar') {
      final old = store.cached;
      if (old != null) {
        final merged = await withSharedTimetable(store, old, alert: true);
        await afterSync(store, old, merged, alert: false);
      }
    } else if (type == 'update') {
      final u = await checkUpdate(prefs);
      if (u != null && prefs.getInt('upd_told') != u.build) {
        await prefs.setInt('upd_told', u.build);
        await notify(
            5,
            'IIMM Buddy ${u.version} is ready',
            u.notes.isEmpty ? 'Open the app and press Update.' : u.notes,
            'news',
            key: 'update:${u.build}');
      }
    }
  } catch (e) {
    logEvent(prefs, 'push_fail', errorLine(e));
  }
  await flushLogs(prefs);
}

/// Runs when a push arrives and the app is closed or in the background.
@pragma('vm:entry-point')
Future<void> onBackgroundPush(RemoteMessage m) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await handlePush(prefs, m.data, shown: m.notification != null);
}

/// The topics a phone listens to: everyone, and its own batch once known.
List<String> pushTopics(String? batch) =>
    ['all', if (batch != null) 'batch-$batch'];

/// Starts push. Safe to call again: it only changes topics when the batch
/// becomes known. Never throws.
Future<void> initPush(SharedPreferences prefs) {
  // One at a time: a second call waits for the first, then looks again.
  final run = _pushSetup.then((_) => _initPush(prefs));
  _pushSetup = run;
  return run;
}

Future<void> _pushSetup = Future.value();

Future<void> _initPush(SharedPreferences prefs) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(onBackgroundPush);
      // A push that Android showed by itself was tapped.
      String place(RemoteMessage m) =>
          m.data['type'] == 'timetable' || m.data['type'] == 'calendar'
              ? 'timetable'
              : 'home';
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => notificationTaps.add(place(m)));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) notificationTaps.add(place(first));
      FirebaseMessaging.onMessage.listen((m) async {
        // App in front: Android shows nothing by itself.
        await prefs.reload();
        await handlePush(prefs, m.data, shown: false);
        pushArrived.value++;
      });
    }
    final want = pushTopics(batchKey(prefs.getString('summary')));
    final have = prefs.getStringList('push_topics') ?? const [];
    if (want.join(',') == have.join(',')) return;
    final fm = FirebaseMessaging.instance;
    for (final t in have.where((t) => !want.contains(t))) {
      await fm.unsubscribeFromTopic(t);
    }
    for (final t in want) {
      await fm.subscribeToTopic(t);
    }
    await prefs.setStringList('push_topics', want);
    logEvent(prefs, 'push_ready', want.join(', '));
  } catch (e) {
    if (prefs.getString('push_err') != '$e') {
      await prefs.setString('push_err', '$e');
      logEvent(prefs, 'push_fail', 'setup: ${errorLine(e)}');
    }
  }
}
