import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'crony_ui.dart';
import 'file_view.dart';
import 'moodle.dart';
import 'net.dart';
import 'notes_index.dart';
import 'theme.dart';
import 'motion.dart';
import 'glass.dart';

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
            ? const LoadingNote('Opening Moodle...')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                EmptyNote(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not open Moodle',
                    text: error),
                FilledButton(onPressed: load, child: const Text('Try again')),
              ]),
      );
    }
    final now = DateTime.now();
    final d = deadlines ?? [];
    final tone = Tone.of(context);
    return GlassRefresh(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search notes in all courses',
              filled: true,
              fillColor: t.colorScheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: t.colorScheme.primary, width: 1.5)),
            ),
            onChanged: (v) {
              setState(() => query = v.trim().toLowerCase());
              _searchNotes(query);
            },
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LiquidBar(height: 3),
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
              TiltCard(
                child: ListTile(
                  leading: Icon(Icons.task_alt, color: tone.good),
                  title: Text(deadlines == null && loading
                      ? 'Checking for deadlines...'
                      : 'Nothing due on Moodle'),
                ),
              ),
            if (d.isNotEmpty)
              _NextDue(
                  due: d.first,
                  info: moodle.assigns[linkId(d.first.url)],
                  now: now,
                  onTap: d.first.url.isEmpty ? null : () => _openDue(d.first)),
            if (d.length > 1) ...[
              const SizedBox(height: 8),
              GroupCard(children: [
                for (final e in d.skip(1)) _dueRow(context, e, now),
              ]),
            ],
            SectionTitle('Courses',
                trailing: Text('${c.length}',
                    style: TextStyle(
                        fontSize: 13, color: t.colorScheme.onSurfaceVariant))),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                for (final (n, x) in c.indexed)
                  _CourseTile(
                    code: codeOf(x.name),
                    name: x.name,
                    color: _courseColor(context, n),
                    files: [
                      for (final s in moodle.cachedSections(x.id) ??
                          const <MoodleSection>[])
                        for (final i in s.items)
                          if (i.isFile) i
                    ].length,
                    fresh: moodle.newCount(x.id),
                    due: d.where((e) => e.course == x.name).length,
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CourseScreen(moodle: moodle, course: x)));
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _openDue(Deadline e) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => WebPage(title: e.name, url: e.url, moodle: moodle)));

  Widget _dueRow(BuildContext context, Deadline e, DateTime now) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final a = moodle.assigns[linkId(e.url)];
    final h = e.due.difference(now).inHours;
    final soon = h < 48;
    final (n, unit) = h < 24
        ? ('${h < 1 ? 1 : h}', h <= 1 ? 'hour' : 'hours')
        : ('${(h / 24).ceil()}', (h / 24).ceil() == 1 ? 'day' : 'days');
    return InkWell(
      onTap: e.url.isEmpty ? null : () => _openDue(e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15)),
              const SizedBox(height: 2),
              Text(
                  [
                    codeOf(e.course),
                    if (a != null) a.label(now),
                    dueText(e.due, now).split(' · ').first,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: a?.submitted == true
                          ? tone.good
                          : soon
                              ? tone.bad
                              : t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(children: [
            Text(n,
                style: TextStyle(
                    fontFamily: 'Schoolbell',
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: soon ? tone.bad : null)),
            Text(unit,
                style: TextStyle(
                    fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
          ]),
        ]),
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
        const TiltCard(
          child: ListTile(
              leading: Icon(Icons.search_off), title: Text('No title matches')),
        )
      else
        GroupCard(children: [
          for (var n = 0; n < hits.length && n < 40; n++)
            ListTile(
              enabled: hits[n].$2.open,
              leading: IconTile(iconFor(hits[n].$2)),
              title: Text(hits[n].$2.name),
              subtitle: Text(codeOf(hits[n].$1.name)),
              onTap: () => openItem(context, moodle, hits[n].$1.id, hits[n].$2),
            ),
        ]),
      const SectionTitle('Inside your notes'),
      if (query.length < 3)
        const TiltCard(
          child: ListTile(
              leading: Icon(Icons.keyboard_outlined),
              title: Text('Type at least 3 letters to search inside notes')),
        )
      else if (indexing != null || noteHits == null)
        TiltCard(
          child: ListTile(
              leading: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              title: Text(indexing ?? 'Searching...')),
        )
      else if (inside.isEmpty)
        TiltCard(
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
        GroupCard(children: [
          for (var n = 0; n < inside.length; n++)
            ListTile(
              leading: const IconTile(Icons.find_in_page_outlined),
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
        ]),
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
      builder: (ctx) => Center(
            child: TiltCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(ctx).colorScheme.primary)),
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Getting the file',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          Text(i.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ]),
                  ),
                ]),
              ),
            ),
          ));
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

  /// Sections the student folded away on this visit.
  final closed = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = sections;
    final files = [
      for (final x in s ?? const <MoodleSection>[])
        for (final i in x.items)
          if (i.isFile) i
    ];
    final saved = files.where((i) => onPhone.contains(i.id)).length;
    final code = codeOf(widget.course.name);
    final now = DateTime.now();
    final pending = [
      for (final x in s ?? const <MoodleSection>[])
        for (final i in x.items)
          if (assigns[i.id] != null &&
              !assigns[i.id]!.submitted &&
              assigns[i.id]!.due != null &&
              assigns[i.id]!.due!.isAfter(now))
            i
    ]..sort((a, b) => assigns[a.id]!.due!.compareTo(assigns[b.id]!.due!));
    return Scaffold(
      appBar: AppBar(
        bottom: const LiquidEdge(),
        toolbarHeight: 76,
        titleSpacing: 0,
        title: BigTitle(code == widget.course.name ? 'Course' : code,
            subtitle: code == widget.course.name ? null : widget.course.name),
        actions: [
          IconButton(
            tooltip: 'Download all notes',
            onPressed: s == null || bulk != null ? null : downloadAll,
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      body: s == null
          ? Center(
              child: error == null
                  ? const LoadingNote('Opening the course...')
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      EmptyNote(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not open this course',
                          text: error),
                      FilledButton(
                          onPressed: () {
                            setState(() => error = null);
                            load(moodle.seen(cid));
                          },
                          child: const Text('Try again')),
                    ]))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text('Showing the saved list. $error',
                        style: t.textTheme.bodySmall),
                  ),
                _CourseSummary(
                  saved: saved,
                  files: files.length,
                  fresh: fresh.length,
                  bulk: bulk,
                  next: pending.isEmpty ? null : pending.first,
                  nextInfo: pending.isEmpty ? null : assigns[pending.first.id],
                  onDownload: bulk != null ? null : downloadAll,
                  onNext: pending.isEmpty ? null : () => open(pending.first),
                ),
                for (final x in s) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => closed.contains(x.title)
                        ? closed.remove(x.title)
                        : closed.add(x.title)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                      child: Row(children: [
                        Expanded(
                          child: Text(x.title,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3)),
                        ),
                        if (x.items.any((i) => fresh.contains(i.id)))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Pill('New', color: t.colorScheme.primary),
                          ),
                        Text('${x.items.length}',
                            style: TextStyle(
                                fontSize: 13,
                                color: t.colorScheme.onSurfaceVariant)),
                        Icon(
                            closed.contains(x.title)
                                ? Icons.expand_more
                                : Icons.expand_less,
                            size: 20,
                            color: t.colorScheme.onSurfaceVariant),
                      ]),
                    ),
                  ),
                  if (!closed.contains(x.title))
                    GroupCard(children: [
                      for (final i in x.items)
                        _ItemRow(
                          item: i,
                          saved: onPhone.contains(i.id),
                          fresh: fresh.contains(i.id),
                          progress: progress[i.id],
                          assign: assigns[i.id],
                          onTap: () => open(i),
                        ),
                    ]),
                ],
              ],
            ),
    );
  }
}

/// What a course page is for at a glance: how much of it is on the phone,
/// what is new, and the next piece of work due.
class _CourseSummary extends StatelessWidget {
  const _CourseSummary(
      {required this.saved,
      required this.files,
      required this.fresh,
      required this.bulk,
      required this.next,
      required this.nextInfo,
      required this.onDownload,
      required this.onNext});
  final int saved;
  final int files;
  final int fresh;
  final String? bulk;
  final MoodleItem? next;
  final AssignInfo? nextInfo;
  final VoidCallback? onDownload;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final all = files > 0 && saved == files;
    return TiltCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (files > 0) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$saved',
                  style: const TextStyle(
                      fontFamily: 'Schoolbell',
                      fontSize: 33,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0)),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text('of $files notes on this phone',
                    style: TextStyle(fontSize: 14, color: muted)),
              ),
            ]),
            const SizedBox(height: 10),
            LiquidBar(
                value: files == 0 ? 0 : saved / files,
                track: t.colorScheme.surfaceContainerHigh,
                color: all ? Tone.of(context).good : t.colorScheme.primary),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                    bulk ??
                        (all
                            ? 'Everything here opens without internet'
                            : 'Save them to read and search offline'),
                    style: TextStyle(fontSize: 13, color: muted)),
              ),
              if (!all)
                FilledButton.tonalIcon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download all')),
            ]),
          ],
          if (fresh > 0) ...[
            if (files > 0) const Divider(height: 26),
            Row(children: [
              Icon(Icons.fiber_new_outlined,
                  size: 20, color: t.colorScheme.primary),
              const SizedBox(width: 10),
              Text('$fresh new since you last looked',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ],
          if (next != null) ...[
            if (files > 0 || fresh > 0) const Divider(height: 26),
            InkWell(
              onTap: onNext,
              child: Row(children: [
                Icon(Icons.assignment_outlined, size: 20, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(next!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        assignLine(nextInfo!, t),
                      ]),
                ),
                Icon(Icons.chevron_right, size: 20, color: muted),
              ]),
            ),
          ],
          if (files == 0 && fresh == 0 && next == null)
            Text('Nothing to download in this course',
                style: TextStyle(fontSize: 13.5, color: muted)),
        ]),
      ),
    );
  }
}

/// The colour a kind of Moodle item is shown in.
Color _tint(BuildContext context, MoodleItem i) {
  final t = Theme.of(context);
  return switch (i.module) {
    'resource' || 'securepdf' => t.brightness == Brightness.dark
        ? Brand.onPinkMuted
        : t.colorScheme.primary,
    'assign' => const Color(0xFFB26A00),
    'quiz' => const Color(0xFF2F6FB0),
    'forum' => const Color(0xFF5E7A1F),
    _ => t.colorScheme.onSurfaceVariant,
  };
}

/// One item of a course: its kind as a tinted tile (ticked once it is on
/// the phone), its name, and what state it is in.
class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {required this.item,
      required this.saved,
      required this.fresh,
      required this.progress,
      required this.assign,
      required this.onTap});
  final MoodleItem item;
  final bool saved;
  final bool fresh;
  final double? progress;
  final AssignInfo? assign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final c = _tint(context, item);
    final note = !item.open
        ? 'Not available to you yet'
        : item.module == 'securepdf'
            ? 'Protected: opens in Moodle\'s viewer'
            : null;
    return Opacity(
      opacity: item.open ? 1 : 0.5,
      child: InkWell(
        onTap: item.open ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(iconFor(item), size: 21, color: c),
                ),
                if (saved)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                          color: t.colorScheme.surface, shape: BoxShape.circle),
                      child: Icon(Icons.check_circle,
                          size: 17, color: Tone.of(context).good),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (progress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LiquidBar(
                            value: progress == 0 ? null : progress, height: 4),
                      )
                    else if (assign != null)
                      DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 13),
                          child: assignLine(assign!, t))
                    else if (note != null)
                      Text(note, style: TextStyle(fontSize: 13, color: muted)),
                  ]),
            ),
            if (fresh)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                    color: t.colorScheme.primary, shape: BoxShape.circle),
              ),
            const SizedBox(width: 8),
            if (item.isFile && !saved)
              Icon(Icons.download_outlined, size: 20, color: muted)
            else if (!item.isFile)
              Icon(Icons.chevron_right, size: 20, color: muted),
          ]),
        ),
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
      appBar: AppBar(
          bottom: const LiquidEdge(),
          toolbarHeight: 76,
          titleSpacing: 0,
          title: BigTitle(widget.item.name,
              subtitle: l == null || l.isEmpty
                  ? null
                  : '${l.where((u) => have.contains(fileName(u))).length} of '
                      '${l.length} files saved on this phone')),
      body: l == null
          ? Center(
              child: error == null
                  ? const LoadingNote('Opening the folder...')
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      EmptyNote(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not open this folder',
                          text: error),
                      FilledButton(
                          onPressed: () {
                            setState(() => error = null);
                            load();
                          },
                          child: const Text('Try again')),
                    ]))
          : l.isEmpty
              ? const EmptyNote(
                  icon: Icons.folder_off_outlined,
                  title: 'This folder is empty')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                      GroupCard(children: [
                        for (final u in l)
                          _ItemRow(
                            item: MoodleItem(
                                0, fileName(u), 'resource', '', true),
                            saved: have.contains(fileName(u)),
                            fresh: false,
                            progress: busy == u.path ? 0 : null,
                            assign: null,
                            onTap: () => open(u),
                          ),
                      ]),
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
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2)),
        bottom: loading || fetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3), child: LiquidBar(height: 3))
            : null,
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}

const _courseHues = [
  Color(0xFFB8355A), Color(0xFF2F6FB0), Color(0xFF5E7A1F), //
  Color(0xFFB26A00), Color(0xFF7A3E8C), Color(0xFF1F7A72),
];
const _courseHuesDark = [
  Color(0xFFF4A3B9), Color(0xFF8DB8E8), Color(0xFFB9D46A), //
  Color(0xFFF2B45C), Color(0xFFD1A4E0), Color(0xFF7FD3C8),
];

Color _courseColor(BuildContext context, int n) =>
    (Theme.of(context).brightness == Brightness.dark
        ? _courseHuesDark
        : _courseHues)[n % _courseHues.length];

/// The nearest deadline, large, with how long is left.
class _NextDue extends StatelessWidget {
  const _NextDue(
      {required this.due,
      required this.info,
      required this.now,
      required this.onTap});
  final Deadline due;
  final AssignInfo? info;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final h = due.due.difference(now).inHours;
    final left = h < 1
        ? 'DUE WITHIN THE HOUR'
        : h < 24
            ? 'DUE IN $h ${h == 1 ? 'HOUR' : 'HOURS'}'
            : 'DUE IN ${(h / 24).ceil()} ${(h / 24).ceil() == 1 ? 'DAY' : 'DAYS'}';
    final done = info?.submitted == true;
    return Sticker(
        radius: 22,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(due.due.isBefore(now) ? 'OVERDUE' : left,
                            style: const TextStyle(
                                fontSize: 11.5,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                                color: Brand.onPink)),
                        const SizedBox(height: 6),
                        Text(due.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Schoolbell',
                                fontSize: 23,
                                height: 1.2,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                                color: Brand.onPink)),
                        const SizedBox(height: 4),
                        Text(
                            '${codeOf(due.course)} · '
                            '${dueText(due.due, now).split(' · ').first}',
                            style: TextStyle(
                                fontSize: 13.5,
                                color: Brand.onPink.withOpacity(0.72))),
                        if (info != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: done
                                    ? Brand.lemon
                                    : Brand.onPink.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(99)),
                            child: Text(info!.label(now),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Brand.onPink)),
                          ),
                        ],
                      ]),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right,
                      color: Brand.onPink.withOpacity(0.6)),
              ]),
            ),
          ),
        ));
  }
}

/// One course: its short name large, with what is waiting in it.
class _CourseTile extends StatelessWidget {
  const _CourseTile(
      {required this.code,
      required this.name,
      required this.color,
      required this.files,
      required this.fresh,
      required this.due,
      required this.onTap});
  final String code;
  final String name;
  final Color color;
  final int files;
  final int fresh;
  final int due;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    return TiltCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(3))),
              const Spacer(),
              if (fresh > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Brand.lemon,
                      border: Border.all(color: Brand.edge, width: 1.5),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text('$fresh new',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Brand.onPink)),
                ),
            ]),
            const SizedBox(height: 10),
            Text(code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Schoolbell',
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0)),
            if (code != name) ...[
              const SizedBox(height: 3),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.3, color: muted)),
            ],
            const Spacer(),
            Text(
                [
                  if (files > 0) '$files ${files == 1 ? 'file' : 'files'}',
                  if (due > 0) '$due due',
                ].join(' · '),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: due > 0 ? Tone.of(context).warn : muted)),
          ]),
        ),
      ),
    );
  }
}
