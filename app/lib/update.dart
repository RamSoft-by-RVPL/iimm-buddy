// In-app updates.
//
// The app is installed from a file, not from a store, so it looks after its
// own updates: it asks the server which build is newest, downloads the new
// file, checks it is the right one, and hands it to Android's installer.
// Android always asks the user to confirm the install; that cannot be skipped.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'log.dart';

class Update {
  Update(
      this.build, this.version, this.notes, this.apk, this.sha256, this.size);
  final int build;
  final String version;
  final String notes;

  /// Path on the app's server, for example "/IIMM-Buddy.apk".
  final String apk;
  final String sha256;
  final int size;
}

/// The newer build described by [raw], or null when this one is current.
Update? parseUpdate(String? raw, {int current = appBuild}) {
  try {
    final j = jsonDecode(raw!) as Map<String, dynamic>;
    final build = j['build'] as int;
    final apk = '${j['apk']}';
    final sha = '${j['sha256']}'.toLowerCase();
    if (build <= current ||
        !apk.startsWith('/') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
      return null;
    }
    return Update(build, '${j['version']}', '${j['notes'] ?? ''}', apk, sha,
        (j['size'] as num?)?.toInt() ?? 0);
  } catch (_) {
    return null;
  }
}

/// Built for Google Play (`--dart-define=PLAY_STORE=true`): Play installs
/// updates itself, and Play does not allow an app to update itself.
const playStore = bool.fromEnvironment('PLAY_STORE');

/// The update found by the last check, if it is still newer than this build.
Update? knownUpdate(SharedPreferences prefs) =>
    playStore ? null : parseUpdate(prefs.getString('upd'));

/// Compares two versions like "0.8.21": below 0, 0 or above 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// True when the admin has said this version may no longer be used. Only
/// what the server last said counts: with no answer yet, the app works.
bool tooOld(SharedPreferences prefs, {String current = appVersion}) {
  final min = prefs.getString('min_version') ?? '';
  return min.isNotEmpty && compareVersions(current, min) < 0;
}

/// Asks the server for the oldest version that may still be used.
Future<void> _checkMinVersion(SharedPreferences prefs) async {
  try {
    final (status, text) =
        await apiSend('GET', Uri.parse('$apiBase/api/app'));
    if (status != 200) return;
    final min = '${(jsonDecode(text) as Map)['min_version'] ?? ''}';
    if (min != (prefs.getString('min_version') ?? '')) {
      await prefs.setString('min_version', min);
      logEvent(prefs, 'min_version', min.isEmpty ? 'none' : min);
    }
  } catch (_) {
    // No connection: keep what the last check found.
  }
}

/// Asks the server which build is newest, and which is the oldest that may
/// still be used. Never throws.
Future<Update?> checkUpdate(SharedPreferences prefs) async {
  await _checkMinVersion(prefs);
  if (playStore) return null;
  try {
    final (status, text) =
        await apiSend('GET', Uri.parse('$apiBase/version.json'));
    if (status == 200) await prefs.setString('upd', text);
  } catch (_) {
    // No connection: keep what the last check found.
  }
  return knownUpdate(prefs);
}

/// Downloads the new build (unless it is already here) and checks it against
/// the fingerprint the server published.
Future<File> downloadUpdate(Update u, void Function(double) onProgress) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/update');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}/IIMM-Buddy-${u.build}.apk');
  Future<bool> good() async =>
      file.existsSync() &&
      (await sha256.bind(file.openRead()).first).toString() == u.sha256;
  if (await good()) return file;
  // Old downloads are no use any more.
  for (final f in dir.listSync().whereType<File>()) {
    f.deleteSync();
  }
  await apiDownload(Uri.parse('$apiBase${u.apk}'), file,
      expected: u.size, onProgress: onProgress);
  if (!await good()) {
    if (file.existsSync()) file.deleteSync();
    throw Exception('The download was damaged. Try again.');
  }
  return file;
}

/// The whole flow with a progress box: download, then Android's installer.
Future<void> runUpdate(
    BuildContext context, SharedPreferences prefs, Update u) async {
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Getting version ${u.version}'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p),
                const SizedBox(height: 12),
                Text(p == null
                    ? 'Starting...'
                    : '${(p * 100).round()}% downloaded'),
              ]),
        ),
      ),
    ),
  );
  String? problem;
  try {
    logEvent(prefs, 'update_start', 'to ${u.version}');
    final file = await downloadUpdate(u, (p) => progress.value = p);
    final r = await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) {
      problem = r.type == ResultType.permissionDenied
          ? 'Allow Crony to install apps when the phone asks, then '
              'press Update again.'
          : 'Could not open the installer.';
    }
  } catch (e) {
    problem = errorLine(e);
  }
  if (problem != null) logEvent(prefs, 'update_fail', problem);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (problem != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(problem)));
  }
}
