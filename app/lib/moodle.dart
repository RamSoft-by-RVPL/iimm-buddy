// Reads courses, notes and deadlines from Moodle.
//
// The site has web services switched off, so this uses the same internal
// calls the Moodle web pages use, with the signed-in session.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo.dart';
import 'net.dart';
import 'notes_index.dart';

class MoodleCourse {
  MoodleCourse(this.id, this.name);
  final int id;
  final String name;
}

class MoodleItem {
  MoodleItem(this.id, this.name, this.module, this.url, this.open);
  final int id;
  final String name;

  /// Moodle activity type: resource, folder, assign, forum, securepdf...
  final String module;
  final String url;

  /// False when the teacher has restricted it.
  final bool open;

  bool get isFile => module == 'resource';
  bool get isFolder => module == 'folder';
}

class MoodleSection {
  MoodleSection(this.title, this.items);
  final String title;
  final List<MoodleItem> items;
}

class Deadline {
  Deadline(this.id, this.name, this.due, this.course, this.url, this.action);
  final int id;
  final String name;
  final DateTime due;
  final String course;
  final String url;
  final String action;
}

/// Where one assignment stands for the signed-in student.
class AssignInfo {
  AssignInfo(this.status, this.graded, this.due, this.checked);

  /// "submitted", "draft" or "none".
  final String status;
  final bool graded;
  final DateTime? due;
  final DateTime checked;

  bool get submitted => status == 'submitted';

  /// Short text for lists.
  String label(DateTime now) {
    if (submitted) return 'Submitted';
    final late = due != null && due!.isBefore(now);
    if (status == 'draft') {
      return late ? 'Draft only, overdue' : 'Draft saved, not submitted';
    }
    return late ? 'Not submitted, overdue' : 'Not submitted';
  }

  Map<String, dynamic> toJson() => {
        's': status,
        'g': graded,
        'd': due?.toIso8601String(),
        't': checked.toIso8601String(),
      };

  static AssignInfo fromJson(Map<String, dynamic> j) => AssignInfo(
      '${j['s']}',
      j['g'] == true,
      DateTime.tryParse('${j['d']}'),
      DateTime.tryParse('${j['t']}') ?? DateTime(2000));
}

const _monthsLong = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december'
];

/// Reads the status table and the due date of an assignment page.
AssignInfo parseAssign(String html, DateTime now) {
  final st =
      RegExp(r'class="[^"]*\bsubmissionstatus(submitted|draft|new|reopened)\b')
          .firstMatch(html)
          ?.group(1);
  final graded = RegExp(r'class="[^"]*\bsubmissiongraded\b').hasMatch(html);
  DateTime? due;
  final m = RegExp(
          r'Due:(?:\s|<[^>]+>)*\w+,\s*(\d{1,2})\s+(\w+)\s+(\d{4}),\s*(\d{1,2}):(\d{2})\s*(AM|PM)?',
          caseSensitive: false)
      .firstMatch(html);
  if (m != null) {
    final month = _monthsLong.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month > 0) {
      var h = int.parse(m.group(4)!);
      final ap = m.group(6)?.toUpperCase();
      if (ap == 'PM' && h < 12) h += 12;
      if (ap == 'AM' && h == 12) h = 0;
      due = DateTime(int.parse(m.group(3)!), month, int.parse(m.group(1)!), h,
          int.parse(m.group(5)!));
    }
  }
  return AssignInfo(
      st == 'submitted' ? 'submitted' : (st == 'draft' ? 'draft' : 'none'),
      graded,
      due,
      now);
}

/// The activity id inside a Moodle link ("...view.php?id=4182").
int? linkId(String url) =>
    int.tryParse(Uri.tryParse(url)?.queryParameters['id'] ?? '');

/// Sections of a course from the answer of `core_courseformat_get_state`.
List<MoodleSection> parseState(String raw) {
  final st = jsonDecode(raw) as Map<String, dynamic>;
  final cms = <String, Map<String, dynamic>>{
    for (final c in (st['cm'] as List? ?? []))
      '${c['id']}': c as Map<String, dynamic>
  };
  final out = <MoodleSection>[];
  for (final s in (st['section'] as List? ?? [])) {
    final items = <MoodleItem>[];
    for (final id in (s['cmlist'] as List? ?? [])) {
      final c = cms['$id'];
      if (c == null || c['visible'] == false) continue;
      items.add(MoodleItem(
        int.parse('${c['id']}'),
        '${c['name']}',
        '${c['module'] ?? c['modname']}',
        '${c['url'] ?? ''}',
        c['uservisible'] != false && '${c['url'] ?? ''}'.isNotEmpty,
      ));
    }
    if (items.isNotEmpty) out.add(MoodleSection('${s['title']}', items));
  }
  return out;
}

final _fileLink = RegExp(r'''https?://[^"'\s<>]+/pluginfile\.php/[^"'\s<>]+''');

/// Links to stored files inside a Moodle page.
List<Uri> fileLinks(String html, {String? mustContain}) {
  final seen = <String>{};
  final out = <Uri>[];
  for (final m in _fileLink.allMatches(html)) {
    final link = m.group(0)!.replaceAll('&amp;', '&');
    if (mustContain != null && !link.contains(mustContain)) continue;
    final u = Uri.tryParse(link);
    if (u == null) continue;
    // Skip theme images and icons.
    if (u.path.contains('/theme_') || u.path.contains('/core_admin/')) continue;
    if (seen.add(u.path)) out.add(u);
  }
  return out;
}

/// True for a link to a file stored on Moodle (not a page).
bool isMoodleFile(Uri u) =>
    u.host == moodleHost &&
    u.path.contains('/pluginfile.php/') &&
    !u.path.contains('/theme_') &&
    // Protected PDFs are left in Moodle's own viewer: the teacher chose
    // that they are not to be downloaded.
    !u.path.contains('/mod_securepdf/');

String fileName(Uri u) {
  final seg = u.pathSegments.isEmpty ? 'file' : u.pathSegments.last;
  final name = seg.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
  return name.isEmpty ? 'file' : name;
}

class Moodle {
  Moodle(this.prefs, {this.onScreen});

  /// Last resort when the silent sign-in fails: a sign-in on screen.
  /// Null in background checks.
  final Future<bool> Function()? onScreen;
  final SharedPreferences prefs;
  String? _sesskey;
  Directory? _root;

  /// GET a Moodle page, signing in again if the session has expired.
  Future<HttpReply> _get(Uri url) async {
    if (demoMode) throw Exception(demoNote);
    var r = await httpSend(url);
    if (r.url.host != moodleHost || r.url.path.startsWith('/login')) {
      await r.response.drain<void>();
      _sesskey = null;
      if (!await httpSsoMoodle() && !(onScreen != null && await onScreen!())) {
        throw NotSignedIn();
      }
      r = await httpSend(url);
      if (r.url.host != moodleHost || r.url.path.startsWith('/login')) {
        await r.response.drain<void>();
        throw Exception('Moodle did not accept the sign-in');
      }
    }
    return r;
  }

  Future<String> _key() async {
    if (_sesskey != null) return _sesskey!;
    final html = await (await _get(Uri.parse('$moodleBase/my/'))).text();
    final m = RegExp(r'"sesskey":"([^"]+)"').firstMatch(html);
    if (m == null) throw Exception('Could not read the Moodle session');
    return _sesskey = m.group(1)!;
  }

  Future<dynamic> _ajax(String method, Map<String, dynamic> args,
      {bool retry = true}) async {
    if (demoMode) return demoAjax(method, args, DateTime.now());
    final key = await _key();
    final r = await httpSend(
        Uri.parse('$moodleBase/lib/ajax/service.php?sesskey=$key&info=$method'),
        jsonBody: jsonEncode([
          {'index': 0, 'methodname': method, 'args': args}
        ]));
    final decoded = jsonDecode(await r.text());
    final res = decoded is List ? decoded.first : decoded;
    if (res is Map && (res['error'] == true || res['error'] is String)) {
      final code =
          '${res['exception']?['errorcode'] ?? res['errorcode'] ?? ''}';
      if (retry &&
          (code.contains('login') ||
              code.contains('sesskey') ||
              code.isEmpty)) {
        _sesskey = null;
        // Opening a page signs in again if needed.
        await _key();
        return _ajax(method, args, retry: false);
      }
      throw Exception(res['exception']?['message'] ?? 'Moodle error ($method)');
    }
    return (res as Map)['data'];
  }

  // ---- lists (each is cached so the screen fills at once and works offline)

  List<MoodleCourse> _courses(String raw) => [
        for (final c in jsonDecode(raw) as List)
          MoodleCourse(c['id'] as int, '${c['fullname']}')
      ];

  List<MoodleCourse>? get cachedCourses {
    final raw = prefs.getString('m_courses');
    return raw == null ? null : _courses(raw);
  }

  Future<List<MoodleCourse>> courses() async {
    final data = await _ajax(
        'core_course_get_enrolled_courses_by_timeline_classification',
        {'classification': 'all', 'limit': 0, 'offset': 0, 'sort': 'fullname'});
    final raw = jsonEncode([
      for (final c in data['courses'] as List)
        {'id': c['id'], 'fullname': c['fullname']}
    ]);
    await prefs.setString('m_courses', raw);
    return _courses(raw);
  }

  List<MoodleSection>? cachedSections(int courseId) {
    final raw = prefs.getString('m_state_$courseId');
    try {
      return raw == null ? null : parseState(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<MoodleSection>> sections(int courseId) async {
    final raw =
        await _ajax('core_courseformat_get_state', {'courseid': courseId});
    final out = parseState(raw as String);
    await prefs.setString('m_state_$courseId', raw);
    return out;
  }

  List<Deadline> _deadlines(String raw) => [
        for (final e in jsonDecode(raw) as List)
          Deadline(
            e['id'] as int,
            '${e['name']}'.replaceFirst(RegExp(r' is due$'), ''),
            DateTime.fromMillisecondsSinceEpoch((e['timesort'] as int) * 1000),
            '${e['course']?['fullname'] ?? ''}',
            '${e['url'] ?? ''}',
            '${e['action']?['name'] ?? ''}',
          )
      ];

  List<Deadline>? get cachedDeadlines {
    final raw = prefs.getString('m_deadlines');
    try {
      return raw == null ? null : _deadlines(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<Deadline>> deadlines() async {
    final from = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400;
    final data = await _ajax('core_calendar_get_action_events_by_timesort',
        {'limitnum': 30, 'timesortfrom': from});
    final raw = jsonEncode([
      for (final e in data['events'] as List)
        {
          'id': e['id'],
          'name': e['name'],
          'timesort': e['timesort'],
          'course': {'fullname': e['course']?['fullname']},
          'url': e['url'],
          'action': {'name': e['action']?['name']},
        }
    ]);
    await prefs.setString('m_deadlines', raw);
    return _deadlines(raw);
  }

  // ---- assignments

  Map<int, AssignInfo> get assigns {
    try {
      final raw = jsonDecode(prefs.getString('m_assign') ?? '{}') as Map;
      return {
        for (final e in raw.entries)
          int.parse('${e.key}'):
              AssignInfo.fromJson((e.value as Map).cast<String, dynamic>())
      };
    } catch (_) {
      return {};
    }
  }

  /// Reads the status of the given assignment items again when the saved
  /// answer is old: hourly while not submitted, twice a day once submitted,
  /// never again after marks are posted. Returns the ones that changed, as
  /// (item, before, now).
  Future<List<(MoodleItem, AssignInfo?, AssignInfo)>> refreshAssigns(
      List<MoodleItem> items,
      {bool force = false}) async {
    final all = assigns;
    final changed = <(MoodleItem, AssignInfo?, AssignInfo)>[];
    final now = DateTime.now();
    for (final i in items) {
      if (i.module != 'assign' || !i.open) continue;
      final old = all[i.id];
      if (old != null && !force) {
        if (old.graded) continue;
        final age = now.difference(old.checked);
        if (age <
            (old.submitted
                ? const Duration(hours: 12)
                : const Duration(minutes: 55))) {
          continue;
        }
      } else if (old != null && old.graded) {
        continue;
      }
      try {
        final html = await (await _get(
                Uri.parse('$moodleBase/mod/assign/view.php?id=${i.id}')))
            .text();
        final info = parseAssign(html, now);
        all[i.id] = info;
        if (old == null ||
            old.status != info.status ||
            old.graded != info.graded) {
          changed.add((i, old, info));
        }
      } on NotSignedIn {
        rethrow;
      } catch (_) {}
    }
    await prefs.setString(
        'm_assign',
        jsonEncode(
            {for (final e in all.entries) '${e.key}': e.value.toJson()}));
    return changed;
  }

  /// Tells Moodle the user is still here, so the session does not time out.
  Future<void> touch() => _ajax('core_session_touch', {});

  /// Remembers that the user has been told about everything in [sections].
  Future<void> markNotified(int courseId, List<MoodleSection> sections) =>
      prefs.setStringList('m_note_$courseId', [
        for (final x in sections)
          for (final i in x.items) '${i.id}'
      ]);

  /// Item ids the user has already been told about (null = never checked).
  Set<int>? notified(int courseId) =>
      prefs.getStringList('m_note_$courseId')?.map(int.parse).toSet();

  // ---- what the user has already seen, to mark new items

  Set<int>? seen(int courseId) {
    final l = prefs.getStringList('m_seen_$courseId');
    return l?.map(int.parse).toSet();
  }

  Future<void> markSeen(int courseId, List<MoodleSection> sections) =>
      prefs.setStringList('m_seen_$courseId', [
        for (final s in sections)
          for (final i in s.items) '${i.id}'
      ]);

  int newCount(int courseId) {
    final s = seen(courseId);
    final secs = cachedSections(courseId);
    if (s == null || secs == null) return 0;
    return secs.expand((x) => x.items).where((i) => !s.contains(i.id)).length;
  }

  // ---- files

  Future<Directory> _dir(int courseId, int itemId) async {
    _root ??=
        Directory('${(await getApplicationDocumentsDirectory()).path}/moodle');
    return Directory('${_root!.path}/$courseId/$itemId');
  }

  /// Files of an item that are already on the phone.
  Future<List<File>> saved(int courseId, int itemId) async {
    final d = await _dir(courseId, itemId);
    if (!d.existsSync()) return [];
    return d.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  Future<File> _download(Uri url, Directory dir,
      {void Function(double)? onProgress, bool allowPage = true}) async {
    final r = await _get(url);
    if (r.contentType == 'text/html' &&
        !r.url.path.contains('/pluginfile.php')) {
      // A page that wraps the file: find the file inside it.
      final html = await r.text();
      if (!allowPage) throw Exception('No file found');
      final links = fileLinks(html, mustContain: 'mod_resource/content');
      final all =
          links.isNotEmpty ? links : fileLinks(html, mustContain: '/mod_');
      if (all.isEmpty) throw Exception('No file found in this item');
      return _download(all.first, dir,
          onProgress: onProgress, allowPage: false);
    }
    if (r.status != 200) {
      await r.response.drain<void>();
      throw Exception('Download failed (${r.status})');
    }
    dir.createSync(recursive: true);
    final target = File('${dir.path}/${fileName(r.url)}');
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    final total = r.response.contentLength;
    var got = 0;
    try {
      await for (final chunk in r.response) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
    return part.rename(target.path);
  }

  /// Downloads a file item unless it is already on the phone.
  Future<File> fileFor(int courseId, MoodleItem item,
      {void Function(double)? onProgress}) async {
    final have = await saved(courseId, item.id);
    if (have.isNotEmpty) return have.first;
    return _download(Uri.parse(item.url), await _dir(courseId, item.id),
        onProgress: onProgress);
  }

  /// A file that a Moodle page links to (an assignment's attachment, a file
  /// inside a page), downloaded unless it is already on the phone.
  Future<File> linkedFile(Uri link) async {
    _root ??=
        Directory('${(await getApplicationDocumentsDirectory()).path}/moodle');
    final dir = Directory('${_root!.path}/links/${link.path.hashCode.abs()}');
    final have = File('${dir.path}/${fileName(link)}');
    if (have.existsSync()) return have;
    return _download(link, dir, allowPage: false);
  }

  /// Links to the files inside a folder item.
  Future<List<Uri>> folderLinks(MoodleItem item) async {
    final html = await (await _get(Uri.parse(item.url))).text();
    return fileLinks(html, mustContain: 'mod_folder/content');
  }

  Future<File> folderFile(int courseId, MoodleItem item, Uri link,
      {void Function(double)? onProgress}) async {
    final dir = await _dir(courseId, item.id);
    final f = File('${dir.path}/${fileName(link)}');
    if (f.existsSync()) return f;
    return _download(link, dir, onProgress: onProgress, allowPage: false);
  }

  /// Downloads every file and folder of a course that is not on the phone yet.
  /// Returns how many files were fetched and how many failed.
  Future<(int, int)> downloadAll(int courseId, List<MoodleSection> sections,
      void Function(int done, int total) onStep) async {
    final items = [
      for (final s in sections)
        for (final i in s.items)
          if (i.open && (i.isFile || i.isFolder)) i
    ];
    var fetched = 0, failed = 0;
    for (var n = 0; n < items.length; n++) {
      onStep(n, items.length);
      final i = items[n];
      try {
        if (i.isFile) {
          if ((await saved(courseId, i.id)).isEmpty) {
            await fileFor(courseId, i);
            fetched++;
          }
        } else {
          for (final link in await folderLinks(i)) {
            final dir = await _dir(courseId, i.id);
            if (!File('${dir.path}/${fileName(link)}').existsSync()) {
              await folderFile(courseId, i, link);
              fetched++;
            }
          }
        }
      } on NotSignedIn {
        rethrow;
      } catch (_) {
        failed++;
      }
    }
    onStep(items.length, items.length);
    return (fetched, failed);
  }

  Future<void> clear() async {
    for (final k in prefs.getKeys().where((k) => k.startsWith('m_')).toList()) {
      await prefs.remove(k);
    }
    _sesskey = null;
    _root ??=
        Directory('${(await getApplicationDocumentsDirectory()).path}/moodle');
    if (_root!.existsSync()) _root!.deleteSync(recursive: true);
    await NotesIndex().clear();
  }
}
