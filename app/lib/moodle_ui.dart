import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'file_view.dart';
import 'moodle.dart';
import 'net.dart';
import 'notes_index.dart';
import 'theme.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dueText(DateTime d, DateTime now) {
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final date =
      '${_dayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}, $time';
  final left = d.difference(now);
  if (left.isNegative) return '$date · overdue';
  if (left.inHours < 24) return '$date · in ${left.inHours} h';
  return '$date · in ${left.inDays} ${left.inDays == 1 ? 'day' : 'days'}';
}

/// "in 3 h", "in 2 days", "overdue".
String dueShort(DateTime d, DateTime now) {
  final left = d.difference(now);
  if (left.isNegative) return 'Overdue';
  if (left.inHours < 1) return 'Due in ${left.inMinutes} min';
  if (left.inHours < 24) return 'Due in ${left.inHours} h';
  return 'Due in ${left.inDays} ${left.inDays == 1 ? 'day' : 'days'}';
}

String errorText(Object e) => e is SocketException || e is HttpException
    ? 'No connection'
    : '$e'.replaceFirst('Exception: ', '');

/// Status line under an assignment: green once handed in, red when late.
Widget assignLine(AssignInfo a, ThemeData t) {
  final now = DateTime.now();
  final late = !a.submitted && a.due != null && a.due!.isBefore(now);
  return Text(
      '${a.label(now)}${a.due == null ? '' : ' · due ${dueText(a.due!, now).split(' · ').first}'}',
      style: TextStyle(
          color: a.submitted
              ? (t.brightness == Brightness.dark
                  ? const Color(0xFF7FCB8A)
                  : const Color(0xFF1F7A36))
              : (late ? t.colorScheme.error : null)));
}

IconData iconFor(MoodleItem i) => switch (i.module) {
      'resource' || 'securepdf' => Icons.description_outlined,
      'folder' => Icons.folder_outlined,
      'assign' => Icons.assignment_outlined,
      'forum' => Icons.forum_outlined,
      'quiz' => Icons.quiz_outlined,
      'url' => Icons.link,
      _ => Icons.article_outlined,
    };

class MoodleTab extends StatefulWidget {
  const MoodleTab({super.key, required this.moodle});
  final Moodle moodle;

  @override
  State<MoodleTab> createState() => MoodleTabState();
}

class MoodleTabState extends State<MoodleTab> {
  List<MoodleCourse>? courses;
  List<Deadline>? deadlines;
  String query = '';
  final notes = NotesIndex();
  Timer? _typing;
  List<NoteHit>? noteHits;
  String? indexing; // "Reading 3 of 12 files"
  int searchable = -1;

  /// Looks inside the saved notes for what was typed (after a short pause).
  void _searchNotes(String q) {
    _typing?.cancel();
    if (q.length < 3) {
      setState(() => noteHits = null);
      return;
    }
    _typing = Timer(const Duration(milliseconds: 450), () async {
      try {
        final n = await notes.build(onProgress: (done, total) {
          if (mounted && done < total) {
            setState(() => indexing = 'Reading $done of $total files...');
          }
        });
        final hits = await notes.search(q);
        if (!mounted || q != query) return;
        setState(() {
          searchable = n;
          indexing = null;
          noteHits = hits;
        });
      } catch (_) {
        if (mounted) setState(() => indexing = null);
      }
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  String? error;
  bool loading = false;

  Moodle get moodle => widget.moodle;

  @override
  void initState() {
    super.initState();
    courses = moodle.cachedCourses;
    deadlines = moodle.cachedDeadlines;
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = await moodle.courses();
      if (mounted) setState(() => courses = c);
      final d = await moodle.deadlines();
      if (mounted) setState(() => deadlines = d);
      // Refresh each course's contents so new items can be counted.
      await Future.wait([
        for (final x in c)
          moodle.sections(x.id).then((s) async {
            if (moodle.seen(x.id) == null) await moodle.markSeen(x.id, s);
          })
      ]);
      if (mounted) setState(() {});
    } on NotSignedIn {
      // The sign-in screen takes over.
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = courses;
    if (c == null) {
      return Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(error!),
                const SizedBox(height: 12),
                FilledButton(onPressed: load, child: const Text('Try again')),
              ]),
      );
    }
    final now = DateTime.now();
    final d = deadlines ?? [];
    final tone = Tone.of(context);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search notes in all courses',
              isDense: true,
            ),
            onChanged: (v) {
              setState(() => query = v.trim().toLowerCase());
              _searchNotes(query);
            },
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (query.isNotEmpty) ...searchResults(context, c),
          if (query.isEmpty) ...[
            if (error != null)
              Strip(
                inset: false,
                icon: Icons.cloud_off_outlined,
                color: tone.warn,
                text: 'Showing the saved list. Could not refresh: $error',
                action: 'Retry',
                onAction: load,
              ),
            const SectionTitle('Due soon'),
            if (d.isEmpty)
              Card(
                child: ListTile(
                  leading: Icon(Icons.task_alt, color: tone.good),
                  title: Text(deadlines == null && loading
                      ? 'Checking for deadlines...'
                      : 'Nothing due on Moodle'),
                ),
              ),
            for (final e in d)
              Card(
                child: InkWell(
                  onTap: e.url.isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => WebPage(
                                  title: e.name, url: e.url, moodle: moodle))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name, style: t.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(e.course,
                              style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            Pill(dueShort(e.due, now),
                                icon: Icons.schedule,
                                color: e.due.difference(now).inHours < 48
                                    ? tone.bad
                                    : tone.warn),
                            if (moodle.assigns[linkId(e.url)] != null)
                              Pill(moodle.assigns[linkId(e.url)]!.label(now),
                                  color:
                                      moodle.assigns[linkId(e.url)]!.submitted
                                          ? tone.good
                                          : null),
                            Pill(dueText(e.due, now).split(' · ').first,
                                outlined: true),
                          ]),
                        ]),
                  ),
                ),
              ),
            const SectionTitle('Courses'),
            Card(
              child: Column(children: [
                for (var i = 0; i < c.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(c[i].name),
                    trailing: moodle.newCount(c[i].id) > 0
                        ? Pill('${moodle.newCount(c[i].id)} new',
                            color: t.colorScheme.primary)
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CourseScreen(moodle: moodle, course: c[i])));
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> searchResults(BuildContext context, List<MoodleCourse> c) {
    final t = Theme.of(context);
    final hits = <(MoodleCourse, MoodleItem)>[];
    final names = <String, String>{}; // "course/item" -> item name
    final courseNames = {for (final x in c) '${x.id}': x.name};
    for (final x in c) {
      for (final s in moodle.cachedSections(x.id) ?? const <MoodleSection>[]) {
        for (final i in s.items) {
          names['${x.id}/${i.id}'] = i.name;
          if (i.name.toLowerCase().contains(query)) hits.add((x, i));
        }
      }
    }
    final inside = noteHits ?? const <NoteHit>[];
    return [
      const SectionTitle('Titles'),
      if (hits.isEmpty)
        const Card(
          child: ListTile(
              leading: Icon(Icons.search_off), title: Text('No title matches')),
        )
      else
        Card(
          child: Column(children: [
            for (var n = 0; n < hits.length && n < 40; n++) ...[
              if (n > 0) const Divider(indent: 56),
              ListTile(
                enabled: hits[n].$2.open,
                leading: Icon(iconFor(hits[n].$2)),
                title: Text(hits[n].$2.name),
                subtitle: Text(hits[n].$1.name),
                onTap: () =>
                    openItem(context, moodle, hits[n].$1.id, hits[n].$2),
              ),
            ],
          ]),
        ),
      const SectionTitle('Inside your notes'),
      if (query.length < 3)
        const Card(
          child: ListTile(
              leading: Icon(Icons.keyboard_outlined),
              title: Text('Type at least 3 letters to search inside notes')),
        )
      else if (indexing != null || noteHits == null)
        Card(
          child: ListTile(
              leading: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              title: Text(indexing ?? 'Searching...')),
        )
      else if (inside.isEmpty)
        Card(
          child: ListTile(
            leading: const Icon(Icons.find_in_page_outlined),
            title: Text(searchable == 0
                ? 'No notes are saved on the phone yet'
                : 'Not found in your $searchable saved files'),
            subtitle: const Text(
                'Only notes saved on the phone are searched. Open a course '
                'and press the download button at the top to save all of '
                'its notes.'),
          ),
        )
      else ...[
        Card(
          child: Column(children: [
            for (var n = 0; n < inside.length; n++) ...[
              if (n > 0) const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.find_in_page_outlined),
                title: Text(
                    names['${inside[n].folders[0]}/${inside[n].folders[1]}'] ??
                        inside[n].fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${inside[n].snippet}\n'
                    '${[
                      courseNames[inside[n].folders[0]] ?? 'Linked file',
                      inside[n].fileName,
                      if (inside[n].page > 0) 'page ${inside[n].page}'
                    ].join(' · ')}',
                    style: t.textTheme.bodySmall),
                isThreeLine: true,
                onTap: () => openFile(context, File(inside[n].path),
                    page: inside[n].page < 1 ? 1 : inside[n].page),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
              'Searched $searchable files saved on the phone. Notes you have '
              'not downloaded are not included.',
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
      ],
    ];
  }
}

/// Opens one Moodle item from anywhere: files are downloaded (with a small
/// progress box) and opened, folders and other items get their own screen.
Future<void> openItem(
    BuildContext context, Moodle moodle, int courseId, MoodleItem i) async {
  if (!i.open) return;
  if (i.isFolder) {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                FolderScreen(moodle: moodle, courseId: courseId, item: i)));
    return;
  }
  if (!i.isFile) {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                WebPage(title: i.name, url: i.url, moodle: moodle)));
    return;
  }
  showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()));
  try {
    final f = await moodle.fileFor(courseId, i);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await openFile(context, f);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorText(e))));
  }
}

class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key, required this.moodle, required this.course});
  final Moodle moodle;
  final MoodleCourse course;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  List<MoodleSection>? sections;
  Set<int> fresh = {};
  Set<int> onPhone = {};
  Map<int, AssignInfo> assigns = {};
  final progress = <int, double>{};
  String? error;
  String? bulk;

  Moodle get moodle => widget.moodle;
  int get cid => widget.course.id;

  @override
  void initState() {
    super.initState();
    final before = moodle.seen(cid);
    sections = moodle.cachedSections(cid);
    assigns = moodle.assigns;
    _mark(before);
    load(before);
  }

  void _mark(Set<int>? before) {
    final s = sections;
    if (s == null || before == null) return;
    fresh = {
      for (final x in s)
        for (final i in x.items)
          if (!before.contains(i.id)) i.id
    };
  }

  Future<void> _scanPhone() async {
    final s = sections;
    if (s == null) return;
    final have = <int>{};
    for (final x in s) {
      for (final i in x.items) {
        if ((i.isFile || i.isFolder) &&
            (await moodle.saved(cid, i.id)).isNotEmpty) {
          have.add(i.id);
        }
      }
    }
    if (mounted) setState(() => onPhone = have);
  }

  Future<void> load(Set<int>? before) async {
    await _scanPhone();
    try {
      final s = await moodle.sections(cid);
      if (!mounted) return;
      setState(() {
        sections = s;
        _mark(before);
        error = null;
      });
      await moodle.markSeen(cid, s);
      await _scanPhone();
      // Fresh submission status for this course's assignments.
      await moodle.refreshAssigns([for (final x in s) ...x.items], force: true);
      if (mounted) setState(() => assigns = moodle.assigns);
    } on NotSignedIn {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  void _fail(Object e) {
    if (e is NotSignedIn) {
      Navigator.popUntil(context, (r) => r.isFirst);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorText(e))));
  }

  Future<void> open(MoodleItem i) async {
    if (!i.open) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not available to you yet')));
      return;
    }
    if (i.isFolder) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  FolderScreen(moodle: moodle, courseId: cid, item: i)));
      _scanPhone();
      return;
    }
    if (!i.isFile) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  WebPage(title: i.name, url: i.url, moodle: moodle)));
      return;
    }
    if (progress.containsKey(i.id)) return;
    setState(() => progress[i.id] = 0);
    try {
      final f = await moodle.fileFor(cid, i, onProgress: (p) {
        if (mounted) setState(() => progress[i.id] = p);
      });
      if (!mounted) return;
      setState(() => onPhone.add(i.id));
      await openFile(context, f);
    } catch (e) {
      if (mounted) _fail(e);
    } finally {
      if (mounted) setState(() => progress.remove(i.id));
    }
  }

  Future<void> downloadAll() async {
    final s = sections;
    if (s == null || bulk != null) return;
    setState(() => bulk = 'Starting...');
    try {
      final (fetched, failed) = await moodle.downloadAll(cid, s, (done, total) {
        if (mounted) setState(() => bulk = 'Downloading $done of $total items');
      });
      await _scanPhone();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(fetched == 0 && failed == 0
              ? 'Everything is already on the phone'
              : '$fetched ${fetched == 1 ? 'file' : 'files'} downloaded'
                  '${failed > 0 ? ', $failed could not be downloaded' : ''}')));
    } catch (e) {
      if (mounted) _fail(e);
    } finally {
      if (mounted) setState(() => bulk = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = sections;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        actions: [
          IconButton(
            tooltip: 'Download all notes',
            onPressed: s == null || bulk != null ? null : downloadAll,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
        bottom: bulk == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(bulk!, style: t.textTheme.bodySmall),
                ),
              ),
      ),
      body: s == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Showing the saved list. $error',
                        style: t.textTheme.bodySmall),
                  ),
                for (final x in s) ...[
                  SectionTitle(x.title),
                  Card(
                    child: Column(children: [
                      for (var n = 0; n < x.items.length; n++) ...[
                        if (n > 0) const Divider(indent: 56),
                        Builder(builder: (context) {
                          final i = x.items[n];
                          return ListTile(
                            enabled: i.open,
                            leading: Icon(iconFor(i)),
                            title: Text(i.name),
                            subtitle: progress.containsKey(i.id)
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                        value: progress[i.id] == 0
                                            ? null
                                            : progress[i.id]),
                                  )
                                : assigns[i.id] != null
                                    ? assignLine(assigns[i.id]!, t)
                                    : !i.open
                                        ? const Text('Not available to you yet')
                                        : i.module == 'securepdf'
                                            ? const Text(
                                                'Protected: opens in Moodle\'s viewer')
                                            : null,
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (fresh.contains(i.id))
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child:
                                      Pill('New', color: t.colorScheme.primary),
                                ),
                              onPhone.contains(i.id)
                                  ? Icon(Icons.offline_pin,
                                      color: Tone.of(context).good)
                                  : i.isFile
                                      ? const Icon(Icons.download_outlined)
                                      : const Icon(Icons.chevron_right),
                            ]),
                            onTap: () => open(i),
                          );
                        }),
                      ],
                    ]),
                  ),
                ],
              ],
            ),
    );
  }
}

class FolderScreen extends StatefulWidget {
  const FolderScreen(
      {super.key,
      required this.moodle,
      required this.courseId,
      required this.item});
  final Moodle moodle;
  final int courseId;
  final MoodleItem item;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Uri>? links;
  Set<String> have = {};
  String? busy;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final saved = await widget.moodle.saved(widget.courseId, widget.item.id);
      final l = await widget.moodle.folderLinks(widget.item);
      if (!mounted) return;
      setState(() {
        links = l;
        have = {for (final f in saved) f.uri.pathSegments.last};
      });
    } on NotSignedIn {
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> open(Uri link) async {
    if (busy != null) return;
    setState(() => busy = link.path);
    try {
      final f =
          await widget.moodle.folderFile(widget.courseId, widget.item, link);
      if (!mounted) return;
      setState(() => have.add(fileName(link)));
      await openFile(context, f);
    } on NotSignedIn {
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e))));
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = links;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: l == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!))
          : l.isEmpty
              ? const Center(child: Text('This folder is empty'))
              : ListView(children: [
                  for (final u in l)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(fileName(u)),
                      subtitle: busy == u.path
                          ? const LinearProgressIndicator()
                          : null,
                      trailing: have.contains(fileName(u))
                          ? const Icon(Icons.offline_pin, color: Colors.green)
                          : const Icon(Icons.download_outlined),
                      onTap: () => open(u),
                    ),
                ]),
    );
  }
}

/// Shows a Moodle page (assignment, forum, protected PDF...) inside the app,
/// using the signed-in session.
class WebPage extends StatefulWidget {
  const WebPage(
      {super.key, required this.title, required this.url, this.moodle});
  final String title;
  final String url;

  /// When given, files linked from the page are downloaded and opened in
  /// the app instead of being shown inside the page.
  final Moodle? moodle;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController controller;
  bool loading = true;
  bool fetching = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => loading = true),
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          if (widget.moodle == null ||
              u == null ||
              !r.isMainFrame ||
              !isMoodleFile(u)) {
            return NavigationDecision.navigate;
          }
          _fetch(u);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  /// Downloads a file the page links to and opens it in the app.
  Future<void> _fetch(Uri link) async {
    if (fetching) return;
    setState(() => fetching = true);
    try {
      final f = await widget.moodle!.linkedFile(link);
      if (mounted) await openFile(context, f);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e))));
      }
    } finally {
      if (mounted) setState(() => fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: loading || fetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
