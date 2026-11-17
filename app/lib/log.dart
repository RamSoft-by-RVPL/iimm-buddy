// The app's diagnostic log.
//
// Short notes about what the app did (refreshed, failed, set reminders) are
// kept in a queue on the phone and sent to the maker's server, with the
// student's name and roll number, so problems can be found and fixed and
// users can be counted. No attendance figures, no Moodle content and no
// sign-in details are ever put in the log. It can be switched off in
// Settings.

import 'dart:convert';
import 'dart:math';

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// Keep in step with `version:` in pubspec.yaml (a test checks it).
const appVersion = '0.8.3';
const appBuild = 15;

bool diagnosticsOn(SharedPreferences prefs) => prefs.getBool('diag') ?? true;

/// A random name for this copy of the app, made once.
String installId(SharedPreferences prefs) {
  var id = prefs.getString('install_id');
  if (id == null) {
    final r = Random.secure();
    id = [for (var i = 0; i < 16; i++) r.nextInt(16).toRadixString(16)].join();
    prefs.setString('install_id', id);
  }
  return id;
}

/// An error as one short line without web addresses' details.
String errorLine(Object e) => '$e'
    .replaceFirst(RegExp(r'^\w*Exception: '), '')
    .replaceAll(RegExp(r'\?[^\s]*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Notes one thing the app did. [kind] is lower case with underscores;
/// kinds ending in "_fail" are shown as errors on the server.
void logEvent(SharedPreferences prefs, String kind, [String detail = '']) {
  if (!diagnosticsOn(prefs)) return;
  final q = prefs.getStringList('log_q') ?? [];
  q.add(jsonEncode({
    't': DateTime.now().toUtc().toIso8601String(),
    'k': kind,
    'd': detail.length > 300 ? detail.substring(0, 300) : detail,
  }));
  if (q.length > 300) q.removeRange(0, q.length - 300);
  prefs.setStringList('log_q', q);
}

/// The body sent to the server (separate so it can be tested).
Map<String, dynamic> logBody(SharedPreferences prefs, List<String> queue) {
  var name = '', roll = '';
  try {
    final st = ((jsonDecode(prefs.getString('summary')!) as Map)['data']
        as Map)['student'] as Map;
    name = '${st['name'] ?? ''}';
    roll = '${st['roll_number'] ?? ''}';
  } catch (_) {
    // Not signed in yet.
  }
  return {
    'id': installId(prefs),
    'name': name,
    'roll': roll,
    'batch': batchKey(prefs.getString('summary')) ?? '',
    'version': appVersion,
    'device': prefs.getString('log_device') ?? '',
    'health': prefs.getString('log_health') ?? '',
    'events': [for (final e in queue) jsonDecode(e)],
  };
}

/// Sends the queue. In the background ([force] false) it goes at most every
/// ten minutes unless something failed. Never throws.
Future<void> flushLogs(SharedPreferences prefs, {bool force = false}) async {
  try {
    if (!diagnosticsOn(prefs)) {
      await prefs.remove('log_q');
      return;
    }
    final q = prefs.getStringList('log_q') ?? [];
    if (q.isEmpty) return;
    final last = DateTime.tryParse(prefs.getString('log_sent') ?? '');
    final failed = q.any((e) => e.contains('_fail"'));
    if (!force &&
        !failed &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    if (prefs.getString('log_device') == null) {
      try {
        await prefs.setString('log_device', await deviceName());
      } catch (_) {}
    }
    final (status, _) = await apiSend('POST', Uri.parse('$apiBase/api/log'),
        body: jsonEncode(logBody(prefs, q)));
    if (status != 200) return;
    // Keep anything noted while the request was on its way.
    final now = prefs.getStringList('log_q') ?? [];
    await prefs.setStringList(
        'log_q', now.length > q.length ? now.sublist(q.length) : []);
    await prefs.setString('log_sent', DateTime.now().toIso8601String());
  } catch (_) {
    // No connection: try again next time.
  }
}
