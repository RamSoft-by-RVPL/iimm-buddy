// The shared class timetable.
//
// The attendance site lists some classes only after they are over, and no
// app may read the institute mail where the full timetable arrives. So one
// student (the publisher) opens the mailed sheet in the app, the app sends
// the classes to a small server, and every classmate's app fetches them.
// The server stores class timings only; the app sends it the batch name and
// nothing about the student.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';
import 'sheet.dart';

const apiBase = 'https://buddy.iimmumbai.in';

/// Other names of the same server, tried when the custom domain fails:
/// Cloudflare's own name for the site, then the first address (Vercel),
/// which forwards to it.
const _pagesHost = 'iimm-buddy.pages.dev';
const _oldHost = 'iimm-buddy-api.vercel.app';

/// The batch a student belongs to, as the server names it ("bs-2026-2030").
/// Read from the attendance site's answer; null before the first refresh.
String? batchKey(String? rawSummary) {
  try {
    final data = (jsonDecode(rawSummary!) as Map)['data'] as Map;
    final m = (data['modules'] as List).first as Map;
    final key = '${m['programme_code'] ?? ''}-${m['batch_year'] ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return key.length < 2
        ? null
        : (key.length > 40 ? key.substring(0, 40) : key);
  } catch (_) {
    return null;
  }
}

/// Addresses known to answer for those names. Some networks (the campus
/// Wi-Fi among them) cannot look up or reach every address, so when the
/// normal way fails the app connects to these directly.
const _pagesAddresses = ['172.66.44.94', '172.66.47.162'];
const _oldAddresses = ['76.76.21.21', '64.29.17.3'];

/// A client that connects to [address] while still checking the server's
/// certificate against its real name.
HttpClient _clientVia(String address) => HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..connectionFactory = (Uri url, String? proxyHost, int? proxyPort) {
    Socket? raw;
    final secure =
        Socket.connect(address, url.port, timeout: const Duration(seconds: 8))
            .then((s) {
      raw = s;
      return SecureSocket.secure(s, host: url.host);
    });
    return Future.value(
        ConnectionTask.fromSocket(secure, () => raw?.destroy()));
  };

/// Ways to reach the server, in order: (address to connect to or null for
/// the normal way, the link to ask for).
List<(String?, Uri)> _routes(Uri url) {
  final pages = url.replace(host: _pagesHost);
  final old = url.replace(host: _oldHost);
  return [
    (null, url),
    if (url.host != _pagesHost) (null, pages),
    for (final a in _pagesAddresses) (a, pages),
    if (url.host != _oldHost) (null, old),
    for (final a in _oldAddresses) (a, old),
  ];
}

/// One request to the app's server: (status, body). Tries the normal way
/// first, then each known address, then the server's old name.
Future<(int, String)> apiSend(String method, Uri url,
    {String? body, String? key}) async {
  Object? failure;
  for (final (address, link) in _routes(url)) {
    final client = address == null
        ? (HttpClient()..connectionTimeout = const Duration(seconds: 8))
        : _clientVia(address);
    try {
      final req = await client.openUrl(method, link);
      if (key != null) req.headers.set('Authorization', 'Bearer $key');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      return (res.statusCode, await utf8.decodeStream(res));
    } on SocketException catch (e) {
      failure = e;
    } on HandshakeException catch (e) {
      failure = e;
    } on TimeoutException catch (e) {
      failure = e;
    } finally {
      client.close(force: true);
    }
  }
  throw failure ?? const SocketException('Cannot reach the server');
}

/// Downloads [url] from the app's server into [target], trying the normal
/// way first and then each known address. [expected] is the size in bytes
/// when known, used for progress.
Future<void> apiDownload(Uri url, File target,
    {int expected = 0, void Function(double)? onProgress}) async {
  Object? failure;
  for (final (address, link) in _routes(url)) {
    final client = address == null
        ? (HttpClient()..connectionTimeout = const Duration(seconds: 8))
        : _clientVia(address);
    final part = File('${target.path}.part');
    try {
      final req = await client.getUrl(link);
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('The server answered ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : expected;
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 40))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call((got / total).clamp(0, 1));
        }
      } finally {
        await sink.close();
      }
      await part.rename(target.path);
      return;
    } on HttpException {
      rethrow;
    } on SocketException catch (e) {
      failure = e;
    } on HandshakeException catch (e) {
      failure = e;
    } on TimeoutException catch (e) {
      failure = e;
    } finally {
      client.close(force: true);
      if (part.existsSync()) part.deleteSync();
    }
  }
  throw failure ?? const SocketException('Cannot reach the server');
}

Future<(int, String)> _send(String method, Uri url,
        {String? body, String? key}) =>
    apiSend(method, url, body: body, key: key);

/// Fetches the batch timetable. Returns the classes when the server has a
/// newer one than this phone (and stores them), otherwise null.
Future<List<SheetClass>?> pullTimetable(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary'));
  if (batch == null) return null;
  final (status, text) =
      await _send('GET', Uri.parse('$apiBase/api/timetable?batch=$batch'));
  if (status != 200) return null;
  final j = jsonDecode(text) as Map<String, dynamic>;
  final updated = j['updated'];
  if (updated is! String || updated == prefs.getString('tt_remote')) {
    return null;
  }
  final classes = decodeSheet(jsonEncode(j['classes']));
  if (classes.isEmpty) return null;
  await prefs.setString('tt_sheet', encodeSheet(classes));
  await prefs.setString('tt_remote', updated);
  await prefs.setString('tt_at', DateTime.now().toIso8601String());
  return classes;
}

/// Sends this phone's timetable to the server for the whole batch.
/// Only works with the publisher key. Returns how many classes were sent.
Future<int> publishTimetable(SharedPreferences prefs) async {
  final key = prefs.getString('pub_key') ?? '';
  final batch = batchKey(prefs.getString('summary'));
  if (key.isEmpty) throw Exception('No publisher key on this phone');
  if (batch == null) throw Exception('Refresh attendance once first');
  final classes = decodeSheet(prefs.getString('tt_sheet'));
  if (classes.isEmpty) throw Exception('No timetable to publish');
  final (status, text) =
      await _send('POST', Uri.parse('$apiBase/api/timetable?batch=$batch'),
          key: key,
          body: jsonEncode({
            'classes': [for (final c in classes) c.toJson()]
          }));
  if (status == 401) throw Exception('The publisher key is wrong');
  if (status != 200) throw Exception('The server refused it ($status)');
  final updated = (jsonDecode(text) as Map)['updated'];
  if (updated is String) await prefs.setString('tt_remote', updated);
  return classes.length;
}

/// A message the people who run the app sent to every phone.
class Notice {
  Notice(this.id, this.title, this.body, this.at);
  final int id;
  final String title;
  final String body;
  final DateTime at;
}

List<Notice> decodeNotices(String? raw) {
  try {
    return [
      for (final n in (jsonDecode(raw ?? '{}') as Map)['notices'] as List)
        Notice(n['id'] as int, '${n['title']}', '${n['body'] ?? ''}',
            DateTime.tryParse('${n['created']}')?.toLocal() ?? DateTime.now())
    ];
  } catch (_) {
    return [];
  }
}

/// The messages this phone has not shown yet, oldest first.
/// [seen] holds the ids already shown. It is null on a new install or
/// straight after updating: then only messages from the last hour are
/// shown, so old ones are not replayed but one just sent still arrives.
/// (Ids are checked one by one, not "higher than the last": a message
/// written earlier but set to go out later has a lower id.)
List<Notice> newNotices(List<Notice> all, Set<int>? seen, DateTime now) => all
    .where((n) => seen == null
        ? now.difference(n.at) < const Duration(hours: 1)
        : !seen.contains(n.id))
    .toList()
  ..sort((a, b) => a.at.compareTo(b.at));

/// Ids of messages already shown on this phone (null = never checked).
Set<int>? seenNotices(SharedPreferences prefs) {
  final l = prefs.getStringList('notice_ids');
  if (l != null) return l.map(int.parse).toSet();
  // Before version 0.7 only the highest id was kept.
  final top = prefs.getInt('notice_seen');
  return top == null ? null : {for (var i = 1; i <= top; i++) i};
}

Future<void> markNoticesSeen(SharedPreferences prefs, Iterable<int> ids) async {
  final all = {...?seenNotices(prefs), ...ids}.toList()..sort();
  // The server only offers the last week's messages, so a short list will do.
  await prefs.setStringList('notice_ids', [
    for (final i in all.skip(all.length > 200 ? all.length - 200 : 0)) '$i'
  ]);
}

/// Fetches the messages and returns the ones to show as notifications.
Future<List<Notice>> pullNotices(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary')) ?? '';
  // The install id also brings messages sent to this phone alone.
  final (status, text) = await _send('GET',
      Uri.parse('$apiBase/api/notices?batch=$batch&user=${installId(prefs)}'));
  if (status != 200) return [];
  final all = decodeNotices(text);
  final fresh = newNotices(all, seenNotices(prefs), DateTime.now());
  await prefs.setString('notices', text);
  await markNoticesSeen(prefs, all.map((n) => n.id));
  return fresh;
}

/// The newest message of the last two days, unless the user closed it.
Notice? currentNotice(SharedPreferences prefs, DateTime now) {
  final all = decodeNotices(prefs.getString('notices'));
  if (all.isEmpty) return null;
  final n = all.reduce((a, b) => a.id > b.id ? a : b);
  if (now.difference(n.at) > const Duration(days: 2)) return null;
  return prefs.getInt('notice_closed') == n.id ? null : n;
}

/// Fetches the batch's academic calendar. True when it changed on this phone.
Future<bool> pullCalendar(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary'));
  if (batch == null) return false;
  final (status, text) =
      await _send('GET', Uri.parse('$apiBase/api/calendar?batch=$batch'));
  if (status != 200) return false;
  final j = jsonDecode(text) as Map<String, dynamic>;
  final updated = '${j['updated'] ?? ''}';
  if (updated == (prefs.getString('acal_remote') ?? '')) return false;
  await prefs.setString('acal', jsonEncode(j['events'] ?? []));
  await prefs.setString('acal_title', '${j['title'] ?? ''}');
  await prefs.setString('acal_remote', updated);
  return true;
}

/// Fetches the mess menu (the same for everyone). True when it changed.
Future<bool> pullMenu(SharedPreferences prefs) async {
  final (status, text) = await _send('GET', Uri.parse('$apiBase/api/menu'));
  if (status != 200) return false;
  // Weeks drop off the answer as they pass, so compare the whole answer.
  if (text == prefs.getString('menu')) return false;
  await prefs.setString('menu', text);
  return true;
}

/// Fetches the batch's exam timetable. True when it changed on this phone.
Future<bool> pullExams(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary'));
  if (batch == null) return false;
  final (status, text) =
      await _send('GET', Uri.parse('$apiBase/api/exams?batch=$batch'));
  if (status != 200) return false;
  final updated = '${(jsonDecode(text) as Map)['updated'] ?? ''}';
  if (updated == (prefs.getString('exams_remote') ?? '')) return false;
  await prefs.setString('exams_pub', text);
  await prefs.setString('exams_remote', updated);
  return true;
}
