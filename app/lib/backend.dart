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

import 'faculty.dart';
import 'log.dart';
import 'sheet.dart';
import 'site.dart' show Cancelled, ExtraClass;

/// The app's server. The release builds pass it in (the SITE_URL variable
/// of the GitHub repo), so moving to another domain needs no code change.
const apiBase = String.fromEnvironment('API_BASE',
    defaultValue: 'https://buddy.iimmumbai.in');

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
    {String? body, String? key, Map<String, String> headers = const {}}) async {
  Object? failure;
  for (final (address, link) in _routes(url)) {
    final client = address == null
        ? (HttpClient()..connectionTimeout = const Duration(seconds: 8))
        : _clientVia(address);
    try {
      final req = await client.openUrl(method, link);
      if (key != null) req.headers.set('Authorization', 'Bearer $key');
      headers.forEach(req.headers.set);
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
        {String? body, String? key, Map<String, String> headers = const {}}) =>
    apiSend(method, url, body: body, key: key, headers: headers);

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

/// Fetches the classes the admin has cancelled. True when the list changed.
Future<bool> pullCancelled(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary'));
  if (batch == null) return false;
  final (status, text) =
      await _send('GET', Uri.parse('$apiBase/api/cancelled?batch=$batch'));
  if (status != 200 || text == prefs.getString('cancelled')) return false;
  await prefs.setString('cancelled', text);
  return true;
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

/// Messages this phone had that were taken back: no longer among the
/// server's [live] ids although they are recent enough to be (the server
/// lists a week). Null [live] (an older server) means none.
List<Notice> takenBack(List<Notice> before, Set<int>? live, DateTime now) => [
      if (live != null)
        for (final n in before)
          if (!live.contains(n.id) &&
              now.difference(n.at) < const Duration(days: 6))
            n
    ];

/// Ids of messages taken back, with their titles, for [withdrawNotices].
const goneKey = 'notices_gone';

/// Fetches the messages and returns the ones to show as notifications.
Future<List<Notice>> pullNotices(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary')) ?? '';
  // The install id also brings messages sent to this phone alone.
  final (status, text) = await _send('GET',
      Uri.parse('$apiBase/api/notices?batch=$batch&user=${installId(prefs)}'));
  if (status != 200) return [];
  final all = decodeNotices(text);
  final fresh = newNotices(all, seenNotices(prefs), DateTime.now());
  Set<int>? live;
  try {
    final l = (jsonDecode(text) as Map)['live'];
    if (l is List) live = {for (final x in l) (x as num).toInt()};
  } catch (_) {}
  final gone = takenBack(
      decodeNotices(prefs.getString('notices')), live, DateTime.now());
  if (gone.isNotEmpty) {
    final old = prefs.getStringList(goneKey) ?? [];
    await prefs.setStringList(goneKey, [
      ...old,
      for (final n in gone) jsonEncode({'id': n.id, 'title': n.title})
    ]);
  }
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

// ---- Students the admin lets post: CR, mess and hostel secretaries.

/// This phone's role, given on the admin page. Null for most students.
class MyRole {
  MyRole(this.role, this.label, this.batch, this.token, this.canCancel,
      {this.canCalendar = false, this.canPoll = false, this.canUpload = false});
  final String role;

  /// "CR", "Mess Secretary", "Hostel Secretary".
  final String label;

  /// Who their posts go to ('' = everyone).
  final String batch;
  final String token;

  /// A CR: cancel, move and add classes of the batch.
  final bool canCancel;

  /// A CR: add and take out academic calendar dates.
  final bool canCalendar;
  final bool canPoll;

  /// A mess secretary: send in the menu file.
  final bool canUpload;

  String get audience => batch.isEmpty ? 'everyone' : batch;
}

MyRole? decodeRole(String? raw) {
  try {
    final j = jsonDecode(raw ?? '') as Map;
    if (j['role'] == null || '${j['token'] ?? ''}'.isEmpty) return null;
    final can = (j['can'] as Map?) ?? {};
    return MyRole('${j['role']}', '${j['label']}', '${j['batch'] ?? ''}',
        '${j['token']}', can['cancel'] == true,
        canCalendar: can['calendar'] == true,
        canPoll: can['poll'] == true,
        canUpload: can['upload'] == true);
  } catch (_) {
    return null;
  }
}

MyRole? myRole(SharedPreferences prefs) =>
    decodeRole(prefs.getString('my_role'));

/// Asks the server whether this phone has a role. True when it changed.
Future<bool> pullRole(SharedPreferences prefs) async {
  final (status, text) = await _send('POST', Uri.parse('$apiBase/api/roles'),
      body: jsonEncode({'action': 'me', 'user': installId(prefs)}));
  if (status != 200) return false;
  final before = prefs.getString('my_role');
  final now = decodeRole(text) == null ? '' : text;
  if ((before ?? '') == now) return false;
  await prefs.setString('my_role', now);
  return true;
}

Future<Map> _asRole(SharedPreferences prefs, String method, String path,
    [Object? body]) async {
  final r = myRole(prefs);
  if (r == null) throw Exception('You no longer have a role');
  final (status, text) = await _send(method, Uri.parse('$apiBase$path'),
      headers: {'X-Role': r.token},
      body: body == null ? null : jsonEncode(body));
  Map j;
  try {
    j = jsonDecode(text) as Map;
  } catch (_) {
    j = {};
  }
  if (status == 401) {
    await pullRole(prefs);
    throw Exception('Not allowed. Your role may have been taken away');
  }
  if (status != 200) {
    throw Exception('${j['error'] ?? 'The server refused it ($status)'}');
  }
  return j;
}

/// Sends a notification as the role holder, now or at [at].
/// Returns true when it was scheduled rather than sent.
Future<bool> postUpdate(SharedPreferences prefs, String title, String body,
    {DateTime? at}) async {
  final j = await _asRole(prefs, 'POST', '/api/notices', {
    'title': title,
    'body': body,
    if (at != null) 'send_at': at.toUtc().toIso8601String(),
  });
  return j['scheduled'] != null;
}

/// One message a role holder posted.
class MyPost {
  MyPost(this.id, this.title, this.body, this.at,
      {this.received = 0, this.audience = 0});
  final int id;
  final String title;
  final String body;
  final DateTime at;

  /// Phones that reported showing it, out of the phones it was for that
  /// were active in the last week.
  final int received;
  final int audience;
}

/// What the role holder posted, and what a new post would reach.
class MyPosts {
  MyPosts(this.posts, this.cancelled, this.cancelledIds, this.reach,
      {this.extra = const [], this.polls = const []});
  final List<MyPost> posts;
  final List<Cancelled> cancelled;
  final List<int> cancelledIds;

  /// Classes the CR added or moved.
  final List<ExtraClass> extra;
  final List<Poll> polls;

  /// Phones a new post goes to (active in the last week).
  final int reach;
}

/// What the role holder posted in the last two weeks, and (for a CR) the
/// classes of their batch called off.
Future<MyPosts> myPosts(SharedPreferences prefs) async {
  final j = await _asRole(prefs, 'POST', '/api/roles', {'action': 'mine'});
  final posts = [
    for (final n in (j['notices'] as List? ?? []))
      MyPost(n['id'] as int, '${n['title']}', '${n['body'] ?? ''}',
          DateTime.tryParse('${n['send_at']}')?.toLocal() ?? DateTime.now(),
          received: (n['received'] as num?)?.toInt() ?? 0,
          audience: (n['audience'] as num?)?.toInt() ?? 0)
  ];
  final rows = (j['cancelled'] as List? ?? []);
  final cancelled = Cancelled.decode(jsonEncode({'classes': rows}));
  return MyPosts(
      posts,
      cancelled,
      [for (final c in rows) (c['id'] as num).toInt()],
      (j['reach'] as num?)?.toInt() ?? 0,
      extra: ExtraClass.decode(jsonEncode({'classes': j['extra'] ?? []})),
      polls: decodePolls(jsonEncode({'polls': j['polls'] ?? []})));
}

Future<void> takeBackPost(SharedPreferences prefs, int id) =>
    _asRole(prefs, 'DELETE', '/api/notices?id=$id');

/// A CR calls off classes of their batch: each is (date, start, course).
Future<void> cancelClasses(SharedPreferences prefs,
    List<(DateTime, String, String)> classes, String why,
    {bool notice = false}) {
  final r = myRole(prefs)!;
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return _asRole(prefs, 'POST', '/api/cancelled?batch=${r.batch}', {
    'classes': [
      for (final (d, s, c) in classes) {'d': day(d), 's': s, 'c': c}
    ],
    'why': why,
    'notice': notice,
  });
}

Future<void> putBackClass(SharedPreferences prefs, int id) => _asRole(
    prefs, 'DELETE', '/api/cancelled?batch=${myRole(prefs)!.batch}&id=$id');

/// Fetches the classes the CR or admin added or moved. True when they changed.
Future<bool> pullExtra(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary'));
  if (batch == null) return false;
  final (status, text) =
      await _send('GET', Uri.parse('$apiBase/api/extra?batch=$batch'));
  if (status != 200) return false;
  if (text == prefs.getString('extra_classes')) return false;
  await prefs.setString('extra_classes', text);
  return true;
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A CR adds a class, or with [from] (date, start, course) moves one.
Future<void> addClass(SharedPreferences prefs, DateTime day, String start,
    String end, String course,
    {String room = '',
    String why = '',
    (DateTime, String, String)? from,
    int? addedId}) {
  final r = myRole(prefs)!;
  return _asRole(prefs, 'POST', '/api/extra?batch=${r.batch}', {
    if (addedId != null) 'id': addedId,
    'd': _day(day),
    's': start,
    'e': end,
    'c': course,
    'room': room,
    'why': why,
    if (from != null && addedId == null)
      'move': {'d': _day(from.$1), 's': from.$2, 'c': from.$3},
  });
}

Future<void> removeAddedClass(SharedPreferences prefs, int id) =>
    _asRole(prefs, 'DELETE', '/api/extra?batch=${myRole(prefs)!.batch}&id=$id');

/// A CR sends the batch's academic calendar again with dates added or
/// taken out.
Future<void> saveCalendar(SharedPreferences prefs, String title,
    List<Map<String, String>> events) async {
  final r = myRole(prefs)!;
  await _asRole(prefs, 'POST', '/api/calendar?batch=${r.batch}',
      {'title': title, 'events': events});
  // Fetch it back as every phone does, so this phone shows it at once.
  await prefs.remove('acal_remote');
  await pullCalendar(prefs);
}

// ---- Polls.

class Poll {
  Poll(this.id, this.question, this.options, this.votes, this.open, this.closes,
      {this.mine, this.from = ''});
  final int id;
  final String question;
  final List<String> options;
  final List<int> votes;
  final bool open;
  final DateTime closes;

  /// The answer this phone picked, if any.
  final int? mine;

  /// "CR", "Mess Secretary", or '' from the admin.
  final String from;

  int get total => votes.fold(0, (a, b) => a + b);
}

List<Poll> decodePolls(String? raw) {
  try {
    return [
      for (final p in (jsonDecode(raw ?? '') as Map)['polls'] as List)
        Poll(
          (p['id'] as num).toInt(),
          '${p['question']}',
          [for (final o in p['options'] as List) '$o'],
          [for (final v in (p['votes'] as List? ?? [])) (v as num).toInt()],
          p['open'] == true,
          DateTime.tryParse('${p['closes']}')?.toLocal() ?? DateTime.now(),
          mine: (p['mine'] as num?)?.toInt(),
          from: '${p['from'] ?? ''}',
        )
    ];
  } catch (_) {
    return [];
  }
}

/// This phone's polls (open ones and the last two weeks'), also kept for
/// showing without a connection.
Future<List<Poll>> pullPolls(SharedPreferences prefs) async {
  final batch = batchKey(prefs.getString('summary')) ?? '';
  final (status, text) = await _send('GET',
      Uri.parse('$apiBase/api/polls?batch=$batch&user=${installId(prefs)}'));
  if (status != 200) return decodePolls(prefs.getString('polls'));
  await prefs.setString('polls', text);
  return decodePolls(text);
}

Future<List<Poll>> vote(SharedPreferences prefs, int poll, int choice) async {
  final (status, text) = await _send('POST', Uri.parse('$apiBase/api/polls'),
      body: jsonEncode({
        'action': 'vote',
        'poll': poll,
        'user': installId(prefs),
        'choice': choice
      }));
  Map j;
  try {
    j = jsonDecode(text) as Map;
  } catch (_) {
    j = {};
  }
  if (status != 200) {
    throw Exception('${j['error'] ?? 'Could not vote ($status)'}');
  }
  final raw = jsonEncode({'polls': j['polls'] ?? []});
  await prefs.setString('polls', raw);
  return decodePolls(raw);
}

/// A role holder asks the people their role covers.
Future<void> createPoll(SharedPreferences prefs, String question,
        List<String> options, int hours) =>
    _asRole(prefs, 'POST', '/api/polls', {
      'action': 'create',
      'question': question,
      'options': options,
      'hours': hours,
    });

Future<void> closePoll(SharedPreferences prefs, int id) =>
    _asRole(prefs, 'POST', '/api/polls', {'action': 'close', 'poll': id});

/// A mess secretary sends in the menu file for the admin to publish.
Future<void> uploadMenu(SharedPreferences prefs, String name, String mime,
        List<int> bytes, String note) =>
    _asRole(prefs, 'POST', '/api/uploads', {
      'name': name,
      'mime': mime,
      'data': base64Encode(bytes),
      'note': note,
    });

/// Fetches the teachers' email directory. True when it changed.
Future<bool> pullFaculty(SharedPreferences prefs) async {
  final (status, text) = await _send('GET', Uri.parse('$apiBase/api/faculty'));
  if (status != 200) return false;
  teacherDirectory = decodeTeachers(text);
  if (text == prefs.getString('faculty')) return false;
  await prefs.setString('faculty', text);
  return true;
}
