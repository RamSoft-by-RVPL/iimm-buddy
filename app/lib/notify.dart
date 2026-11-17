// Notifications: reminders before classes and before deadlines, and alerts
// for new Moodle items and attendance changes.

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _plugin = FlutterLocalNotificationsPlugin();

/// Where a tapped notification wants to go: "timetable", "course:12",
/// "moodle" or "home". The main screen listens and opens that place.
final notificationTaps = StreamController<String>.broadcast();
bool _ready = false;

const _channels = {
  'classes': ('Class reminders', 'A reminder before each class'),
  'moodle': ('Moodle updates', 'New notes, assignments and deadlines'),
  'attendance': ('Attendance alerts', 'Absences and low attendance'),
  'news': ('Messages', 'Messages from the people who run the app'),
};

Future<void> initNotifications() async {
  if (_ready) return;
  tzdata.initializeTimeZones();
  await _plugin.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat')),
      onDidReceiveNotificationResponse: (r) {
    if ((r.payload ?? '').isNotEmpty) notificationTaps.add(r.payload!);
  });
  // Make the channels now: a push that Android shows by itself needs the
  // Messages channel to exist already.
  final a = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  for (final e in _channels.entries) {
    await a?.createNotificationChannel(AndroidNotificationChannel(
        e.key, e.value.$1,
        description: e.value.$2, importance: Importance.high));
  }
  _ready = true;
}

/// Asks the user to allow notifications (Android 13 and later).
Future<void> askNotificationPermission() async {
  await initNotifications();
  final a = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await a?.requestNotificationsPermission();
}

NotificationDetails _details(String channel, {String? longText}) {
  final c = _channels[channel]!;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      channel,
      c.$1,
      channelDescription: c.$2,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation:
          longText == null ? null : BigTextStyleInformation(longText),
    ),
  );
}

Future<void> notify(int id, String title, String body, String channel,
    {String open = 'home'}) async {
  await initNotifications();
  await _plugin.show(id, title, body, _details(channel, longText: body),
      payload: open);
}

/// The place asked for by the notification that started the app, if a tap
/// on one is what opened it.
Future<String?> openedFromNotification() async {
  await initNotifications();
  final d = await _plugin.getNotificationAppLaunchDetails();
  if (d == null || !d.didNotificationLaunchApp) return null;
  final p = d.notificationResponse?.payload ?? '';
  return p.isEmpty ? null : p;
}

/// One reminder to be shown at a set time.
class Reminder {
  Reminder(this.id, this.at, this.title, this.body, {this.open = 'home'});
  final int id;

  /// Where tapping it leads (see [notificationTaps]).
  final String open;

  /// Wall-clock time in India.
  final DateTime at;
  final String title;
  final String body;
}

/// Replaces all reminders of one kind ([key]) with [items].
Future<void> scheduleReminders(SharedPreferences prefs, String key,
    String channel, List<Reminder> items) async {
  await initNotifications();
  for (final id in prefs.getStringList(key) ?? const <String>[]) {
    await _plugin.cancel(int.parse(id));
  }
  final india = tz.getLocation('Asia/Kolkata');
  final now = tz.TZDateTime.now(india);
  final ids = <String>[];
  for (final r in items) {
    final at = tz.TZDateTime(
        india, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute);
    if (!at.isAfter(now)) continue;
    try {
      await _plugin.zonedSchedule(
          r.id, r.title, r.body, at, _details(channel, longText: r.body),
          payload: r.open,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // Exact alarms not allowed on this phone: a few minutes late is fine.
      await _plugin.zonedSchedule(
          r.id, r.title, r.body, at, _details(channel, longText: r.body),
          payload: r.open,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
    ids.add('${r.id}');
  }
  await prefs.setStringList(key, ids);
}

Future<int> pendingReminders() async {
  await initNotifications();
  return (await _plugin.pendingNotificationRequests()).length;
}

/// Whether the phone will actually show reminders.
class NotifyState {
  NotifyState(this.allowed, this.exact, this.next);

  /// Notifications are allowed for the app.
  final bool allowed;

  /// The app may fire reminders at an exact minute.
  final bool exact;

  /// How many reminders are waiting.
  final int next;
}

Future<NotifyState> notifyState() async {
  await initNotifications();
  final a = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return NotifyState(
      await a?.areNotificationsEnabled() ?? true,
      await a?.canScheduleExactNotifications() ?? true,
      (await _plugin.pendingNotificationRequests()).length);
}

/// Sends the user to the "Alarms and reminders" switch for this app.
Future<void> askExactAlarms() async {
  await initNotifications();
  await _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestExactAlarmsPermission();
}
