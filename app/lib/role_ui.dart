// For students the admin made CR, mess secretary or hostel secretary: send
// notifications and polls to the people their role covers. A CR also runs
// the batch's timetable (cancel, move and add classes) and academic
// calendar; a mess secretary sends in the menu.

import 'package:cookie_bridge/cookie_bridge.dart' show pickFile;
import 'package:flutter/material.dart';

import 'acal.dart';

import 'backend.dart';
import 'crony_ui.dart';
import 'mascot.dart';
import 'polls_ui.dart';
import 'push.dart' show pushArrived;
import 'planner.dart' show Course;
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';

/// Ready-made starts for the usual posts, by role: (title, message).
const roleTemplates = <String, List<(String, String)>>{
  'cr': [
    ('Class moved to Room ', ''),
    ('Class starts 15 minutes late', ''),
    ('Bring your laptops to class', ''),
    ('Assignment deadline extended', 'New deadline: '),
    ('Extra class', 'Day, time and room: '),
  ],
  'mess': [
    ('Menu change today', ''),
    ('Special dinner tonight', ''),
    ('Mess timings changed', 'New timings: '),
    ('Mess feedback', 'Tell us how the food was: '),
  ],
  'hostel': [
    ('Water supply off', 'From '),
    ('Power cut', 'From '),
    ('Room inspection', 'On '),
    ('Hostel meeting', 'Time and place: '),
  ],
};

/// The server's id of a class the CR added (see [Snapshot.withExtra]), or
/// null for any other class.
int? addedIdOf(ClassSlot s) => s.id <= -(1 << 40) ? -(1 << 40) - s.id : null;

/// "seen on 5 of 8 phones", or nothing when nobody could be counted.
String seenLine(MyPost p, DateTime now) {
  if (p.at.isAfter(now) || p.audience == 0) return '';
  return 'seen on ${p.received} of ${p.audience} '
      '${p.audience == 1 ? 'phone' : 'phones'}';
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// On the home screen, only for role holders.
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.store, this.snap});
  final Store store;
  final Snapshot? snap;

  @override
  Widget build(BuildContext context) {
    final r = myRole(store.prefs);
    if (r == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        leading: const IconTile(Icons.campaign_outlined),
        title: Text('You are ${r.label}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(r.canCancel
            ? 'Updates and polls for ${r.audience}; run its timetable and calendar'
            : r.canUpload
                ? 'Updates and polls for ${r.audience}; send in the menu'
                : 'Updates and polls for ${r.audience}'),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RoleScreen(store: store, snap: snap))),
      ),
    );
  }
}

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.store, this.snap});
  final Store store;
  final Snapshot? snap;

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  Store get store => widget.store;

  /// The timetable as this phone has it; fetched again after each change.
  late Snapshot? snap = widget.snap;
  final title = TextEditingController();
  final body = TextEditingController();
  DateTime? later;
  var busy = false;
  List<MyPost>? posts;
  int reach = 0;
  List<ExtraClass> added = [];
  List<Poll> myPolls = [];
  final titleFocus = FocusNode();
  final bodyFocus = FocusNode();
  List<Cancelled> cancelled = [];
  List<int> cancelledIds = [];
  String? loadError;

  // Cancelling a class (CR).
  late DateTime day = _firstClassDay();
  final picked = <String>{};

  /// Classes not on this phone's timetable yet: (start, course or '').
  final extra = <(String, String)>[];
  final why = TextEditingController();
  var notice = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  DateTime _firstClassDay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final coming = (snap?.sessions ?? [])
        .where((s) => !s.cancelled && !s.date.isBefore(today))
        .map((s) => s.date)
        .toList()
      ..sort();
    return coming.isEmpty ? today : coming.first;
  }

  /// After a change to the timetable: this phone fetches it at once and the
  /// home screen redraws, as other phones do when the push arrives.
  Future<void> afterChange() async {
    try {
      await pullCancelled(store.prefs);
      await pullExtra(store.prefs);
    } catch (_) {}
    final fresh = store.cached;
    if (fresh != null && mounted) setState(() => snap = fresh);
    pushArrived.value++;
    await load();
  }

  Future<void> load() async {
    try {
      final m = await myPosts(store.prefs);
      if (!mounted) return;
      setState(() {
        posts = m.posts;
        cancelled = m.cancelled;
        cancelledIds = m.cancelledIds;
        reach = m.reach;
        added = m.extra;
        myPolls = m.polls;
        loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loadError = '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  void say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> sure(String head, String text, String yes) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(head),
          content: Text(text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Back')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      ) ??
      false;

  Future<void> send(MyRole r) async {
    final t = title.text.trim();
    if (t.isEmpty) return say('Write a title first');
    if (later != null && !later!.isAfter(DateTime.now())) {
      return say('That time has already passed');
    }
    final whom =
        r.batch.isEmpty ? 'everyone using Crony' : 'everyone in ${r.batch}';
    if (!await sure(
        later == null
            ? 'Send now?'
            : 'Send at ${fmtDate(later!)}, ${_hm(later!)}?',
        '"${r.label}: $t" goes to $whom as a notification. '
            'You can take it back, but phones that already showed it keep it.',
        'Send')) {
      return;
    }
    setState(() => busy = true);
    try {
      final scheduled =
          await postUpdate(store.prefs, t, body.text.trim(), at: later);
      title.clear();
      body.clear();
      setState(() => later = null);
      say(scheduled ? 'Scheduled' : 'Sent to $whom');
      await load();
    } catch (e) {
      say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<ClassSlot> get dayClasses => [
        for (final s in snap?.sessions ?? <ClassSlot>[])
          if (DateUtils.isSameDay(s.date, day) && !s.cancelled) s
      ]..sort((a, b) => a.start.compareTo(b.start));

  Future<void> cancel() async {
    final list = [
      for (final s in dayClasses)
        if (picked.contains(s.slotKey)) (s.date, s.start, s.course),
      for (final (start, course) in extra) (day, start, course),
    ];
    if (list.isEmpty) return say('Tick the classes to cancel');
    if (!await sure(
        'Cancel ${list.length == 1 ? 'this class' : '${list.length} classes'}?',
        '${fmtDate(day)}\n${list.map((x) => '${x.$2} ${x.$3.isEmpty ? 'every class then' : x.$3}').join('\n')}\n\n'
            'Everyone\'s timetable shows it as Cancelled, reminders stop and '
            'it does not count in attendance. You can put it back.',
        'Cancel class')) {
      return;
    }
    setState(() => busy = true);
    try {
      await cancelClasses(store.prefs, list, why.text.trim(), notice: notice);
      picked.clear();
      extra.clear();
      why.clear();
      say('Cancelled. Phones are updating now.');
      await afterChange();
    } catch (e) {
      say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _t(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _tod(String hm) {
    final p = hm.split(':');
    return TimeOfDay(
        hour: int.tryParse(p.first) ?? 9,
        minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  List<String> get courseNames =>
      {for (final c in snap?.courses ?? <Course>[]) c.name}.toList()..sort();

  /// Add a class, or with [moving] move that class to a new day or time.
  Future<void> classSheet({ClassSlot? moving}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var on = moving?.date ?? day;
    var start = _tod(moving?.start ?? '09:00');
    var end = _tod(moving?.end ?? '10:30');
    String? course = moving?.course;
    final room = TextEditingController(text: moving?.room ?? '');
    final reason = TextEditingController();
    final now = DateTime.now();
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SheetHead(moving == null ? 'Add a class' : 'Move this class',
                      subtitle: moving == null
                          ? 'An extra class on everyone\'s timetable, with reminders'
                          : '${moving.course}\nNow ${fmtDate(moving.date)}, ${moving.start}'),
                  if (moving == null) ...[
                    const FieldLabel('Course'),
                    DropdownButtonFormField<String>(
                      value: course,
                      isExpanded: true,
                      hint: const Text('Pick the course'),
                      items: [
                        for (final n in courseNames)
                          DropdownMenuItem(
                              value: n,
                              child: Text(n, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (v) => set(() => course = v),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FieldLabel(moving == null ? 'When' : 'New day and time'),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text(fmtDate(on)),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: ctx,
                          initialDate: on,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: now.add(const Duration(days: 60)));
                      if (d != null) set(() => on = d);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: ctx,
                              helpText: 'Starts',
                              initialTime: start);
                          if (t != null) {
                            set(() {
                              // Keep the same length when the start moves.
                              final len = (end.hour * 60 + end.minute) -
                                  (start.hour * 60 + start.minute);
                              start = t;
                              final e =
                                  t.hour * 60 + t.minute + (len > 0 ? len : 90);
                              if (e < 24 * 60) {
                                end = TimeOfDay(hour: e ~/ 60, minute: e % 60);
                              }
                            });
                          }
                        },
                        child: Text('Starts ${_t(start)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: ctx, helpText: 'Ends', initialTime: end);
                          if (t != null) set(() => end = t);
                        },
                        child: Text('Ends ${_t(end)}'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: room,
                    maxLength: 40,
                    decoration: const InputDecoration(
                        labelText: 'Room (optional)', hintText: '404'),
                  ),
                  TextField(
                    controller: reason,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                        labelText: 'Note (optional)',
                        hintText: moving == null
                            ? 'Make-up class for 12 Nov'
                            : 'Faculty asked to shift it'),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                        onPressed: () {
                          if (course == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Pick the course')));
                            return;
                          }
                          if (moving != null &&
                              DateUtils.isSameDay(on, moving.date) &&
                              _t(start) == moving.start) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Pick a new day or time')));
                            return;
                          }
                          if (end.hour * 60 + end.minute <=
                              start.hour * 60 + start.minute) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('It has to end after it starts')));
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child:
                            Text(moving == null ? 'Add class' : 'Move class')),
                  ),
                ]),
          ),
        ),
      ),
    );
    if (go != true || course == null) return;
    setState(() => busy = true);
    try {
      await addClass(store.prefs, on, _t(start), _t(end), course!,
          room: room.text.trim(),
          why: reason.text.trim(),
          from: moving == null
              ? null
              : (moving.date, moving.start, moving.course),
          addedId: moving == null ? null : addedIdOf(moving));
      say(moving == null
          ? 'Added. Everyone\'s timetable is updating.'
          : 'Moved. Everyone\'s timetable is updating.');
      await afterChange();
    } catch (e) {
      say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---- Academic calendar (CR).

  static const kinds = {
    'exam': 'Exam',
    'holiday': 'Holiday',
    'break': 'Break',
    'info': 'Other date'
  };

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> _event(TermEvent e) => {
        'title': e.title,
        'from': _iso(e.from),
        'to': _iso(e.to),
        'kind': e.kind,
        'group': e.group,
      };

  Future<void> saveDates(List<Map<String, String>> events, String done) async {
    setState(() => busy = true);
    try {
      await saveCalendar(
          store.prefs, store.prefs.getString('acal_title') ?? '', events);
      say(done);
    } catch (e) {
      say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = TextEditingController();
    var kind = 'exam';
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, now.day + 1);
    var to = from;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHead('Add a date',
                    subtitle: 'On everyone\'s academic calendar and timetable'),
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'What', hintText: 'LAC mid-term exam'),
                ),
                const FieldLabel('Kind'),
                Segmented(
                    options: kinds.values.toList(),
                    selected: kinds.keys.toList().indexOf(kind),
                    onChanged: (i) => set(() => kind = kinds.keys.toList()[i])),
                const SizedBox(height: 14),
                const FieldLabel('Dates'),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: from,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 2));
                        if (d != null) {
                          set(() {
                            from = d;
                            if (to.isBefore(d)) to = d;
                          });
                        }
                      },
                      child: Text('From ${fmtDate(from)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: to,
                            firstDate: from,
                            lastDate: DateTime(now.year + 2));
                        if (d != null) set(() => to = d);
                      },
                      child: Text('To ${fmtDate(to)}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                    kind == 'info'
                        ? 'Classes go on as usual on these days.'
                        : 'No regular classes on these days: the leave planner '
                            'and long weekends take that into account.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                      onPressed: () {
                        if (name.text.trim().isEmpty) return;
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Add date')),
                ),
              ]),
        ),
      ),
    );
    if (go != true) return;
    await saveDates([
      for (final e in store.calendar) _event(e),
      {
        'title': name.text.trim(),
        'from': _iso(from),
        'to': _iso(to),
        'kind': kind,
        'group': '',
      }
    ], 'Added to everyone\'s calendar');
  }

  // ---- Menu (mess secretary).

  Future<void> sendMenu() async {
    (String, String, List<int>)? file;
    try {
      file = await pickFile(['image/*', 'application/pdf']);
    } catch (e) {
      return say('That file is too big (over 10 MB) or cannot be read');
    }
    if (file == null || !mounted) return;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send this menu?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '${file!.$1} (${(file.$3.length / 1024).round()} KB) goes to the '
              'admin, who puts the menu on everyone\'s app.'),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', hintText: 'Menu from Mon 30 Nov'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      var mime = file.$2;
      if (mime.isEmpty) {
        mime = file.$1.toLowerCase().endsWith('.pdf')
            ? 'application/pdf'
            : 'image/jpeg';
      }
      await uploadMenu(store.prefs, file.$1, mime, file.$3, note.text.trim());
      say('Sent. The admin will put it up for everyone.');
    } catch (e) {
      say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// A class the timetable does not show yet: its start time and course.
  Future<void> addExtra() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final t = await showTimePicker(
        context: context,
        helpText: 'When does the class start?',
        initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (t == null || !mounted) return;
    final names = {for (final c in snap?.courses ?? <Course>[]) c.name}.toList()
      ..sort();
    final course = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Which course?'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Every class at that time')),
          for (final n in names)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, n), child: Text(n)),
        ],
      ),
    );
    if (course == null) return;
    final start =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (!extra.contains((start, course))) extra.add((start, course));
    });
  }

  Future<void> pickLater() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: later ?? now,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 7)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay.fromDateTime(later ?? now.add(const Duration(hours: 1))));
    if (t == null) return;
    setState(() => later = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final r = myRole(store.prefs);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    if (r == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Post an update')),
          body: const EmptyNote(
              icon: Icons.lock_outline,
              title: 'You no longer have a role',
              text: 'Ask the admin if this is wrong.'));
    }
    final now = DateTime.now();
    final classes = dayClasses;

    return Scaffold(
      appBar: AppBar(title: const Text('Post an update')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
                'You are ${r.label}. What you send goes to '
                '${r.batch.isEmpty ? 'everyone using Crony' : 'everyone in ${r.batch}'}'
                '${reach > 0 ? ' ($reach ${reach == 1 ? 'phone' : 'phones'} active this week)' : ''} '
                'as a notification, starting with "${r.label}:". At most 10 a day.',
                style: t.textTheme.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 16),
            const FieldLabel('Send a notification'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (head, start)
                    in roleTemplates[r.role] ?? const <(String, String)>[])
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 10),
                    child: ActionChip(
                      label: Text(head.trim()),
                      onPressed: () => setState(() {
                        title.text = head;
                        title.selection =
                            TextSelection.collapsed(offset: head.length);
                        if (body.text.trim().isEmpty) body.text = start;
                        // Straight on to what is left to fill in.
                        if (head.endsWith(' ')) {
                          titleFocus.requestFocus();
                        } else if (start.isNotEmpty) {
                          bodyFocus.requestFocus();
                          body.selection =
                              TextSelection.collapsed(offset: body.text.length);
                        }
                      }),
                    ),
                  ),
              ]),
            ),
            TextField(
              controller: title,
              focusNode: titleFocus,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'Dinner at 8:30 today'),
            ),
            TextField(
              controller: body,
              focusNode: bodyFocus,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Message (optional)'),
            ),
            ValueListenableBuilder(
              valueListenable: title,
              builder: (context, _, __) => ValueListenableBuilder(
                valueListenable: body,
                builder: (context, _, __) => title.text.trim().isEmpty
                    ? const SizedBox.shrink()
                    : _Preview(
                        '${r.label}: ${title.text.trim()}', body.text.trim()),
              ),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(later == null ? Icons.schedule : Icons.event),
                  label: Text(later == null
                      ? 'Send now'
                      : '${fmtDate(later!)}, ${_hm(later!)}'),
                  onPressed: busy ? null : pickLater,
                ),
              ),
              if (later != null)
                IconButton(
                    tooltip: 'Send now instead',
                    onPressed: () => setState(() => later = null),
                    icon: const Icon(Icons.close)),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: busy ? null : () => send(r),
                icon: const Icon(Icons.send),
                label: Text(later == null ? 'Send' : 'Schedule'),
              ),
            ]),
            if (r.canPoll) ...[
              const SizedBox(height: 24),
              const FieldLabel('Ask a poll'),
              OutlinedButton.icon(
                icon: const Icon(Icons.how_to_vote_outlined),
                label: const Text('New poll'),
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          if (await askPoll(context, store, r)) {
                            say('Poll sent to ${r.audience}');
                            await load();
                          }
                        } catch (e) {
                          say('$e'.replaceFirst('Exception: ', ''));
                        }
                      },
              ),
            ],
            if (r.canCancel) ...[
              const SizedBox(height: 24),
              const FieldLabel('Change the timetable'),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(fmtDate(day)),
                onPressed: busy
                    ? null
                    : () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final d = await showDatePicker(
                            context: context,
                            initialDate: day,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: now.add(const Duration(days: 60)));
                        if (d != null) {
                          setState(() {
                            day = d;
                            picked.clear();
                            extra.clear();
                          });
                        }
                      },
              ),
              const SizedBox(height: 6),
              if (classes.isEmpty && extra.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      'No classes on the timetable that day yet. '
                      'Add the class below.',
                      style: t.textTheme.bodyMedium?.copyWith(color: muted)),
                )
              else
                GroupCard(children: [
                  for (final (start, course) in extra)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: true,
                      onChanged: (_) =>
                          setState(() => extra.remove((start, course))),
                      title: Text(
                          course.isEmpty ? 'Every class at $start' : course,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('$start · added by you'),
                    ),
                  for (final s in classes)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: picked.contains(s.slotKey),
                      onChanged: (v) => setState(() => v!
                          ? picked.add(s.slotKey)
                          : picked.remove(s.slotKey)),
                      title: Text(s.course,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        '${s.start} to ${s.end}',
                        if (s.faculty.isNotEmpty) s.faculty,
                      ].join(' · ')),
                      secondary: IconButton(
                        tooltip: 'Move to another time',
                        icon: const Icon(Icons.edit_calendar_outlined),
                        onPressed: busy ? null : () => classSheet(moving: s),
                      ),
                    ),
                ]),
              if (classes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Tick classes to cancel them, or tap the calendar icon to '
                      'move one.',
                      style: t.textTheme.bodySmall?.copyWith(color: muted)),
                ),
              Wrap(spacing: 4, children: [
                TextButton.icon(
                  onPressed: busy ? null : addExtra,
                  icon: const Icon(Icons.event_busy, size: 18),
                  label: const Text('Cancel one not listed'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => classSheet(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a class'),
                ),
              ]),
              TextField(
                controller: why,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'Faculty unwell, moved to Saturday'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: notice,
                onChanged: (v) => setState(() => notice = v!),
                title: const Text('Also send a notification'),
                subtitle: const Text(
                    'Crony already tells everyone a class is cancelled. Tick this '
                    'for classmates on an old version of the app.'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed:
                      busy || (picked.isEmpty && extra.isEmpty) ? null : cancel,
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Cancel class'),
                ),
              ),
            ],
            if (r.canCalendar) ...[
              const SizedBox(height: 24),
              const FieldLabel('Academic calendar'),
              Builder(builder: (context) {
                final all = store.calendar;
                final today = DateTime(now.year, now.month, now.day);
                final coming = [
                  for (final e in all)
                    if (!e.to.isBefore(today)) e
                ]..sort((a, b) => a.from.compareTo(b.from));
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (coming.isEmpty)
                        Text('No dates coming up.',
                            style:
                                t.textTheme.bodyMedium?.copyWith(color: muted))
                      else
                        GroupCard(children: [
                          for (final e in coming.take(12))
                            ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.fromLTRB(14, 0, 4, 0),
                              title: Text(e.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                kinds[e.kind] ?? e.kind,
                                e.oneDay
                                    ? fmtDate(e.from)
                                    : '${fmtDate(e.from)} to ${fmtDate(e.to)}',
                              ].join(' · ')),
                              trailing: IconButton(
                                tooltip: 'Take out',
                                icon: const Icon(Icons.close),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        if (!await sure(
                                            'Take out "${e.title}"?',
                                            'It goes from everyone\'s calendar.',
                                            'Take out')) {
                                          return;
                                        }
                                        await saveDates([
                                          for (final x in all)
                                            if (!identical(x, e)) _event(x)
                                        ], 'Taken out');
                                      },
                              ),
                            ),
                        ]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy ? null : addDate,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add a date'),
                        ),
                      ),
                    ]);
              }),
            ],
            if (r.canUpload) ...[
              const SizedBox(height: 24),
              const FieldLabel('Mess menu'),
              Text(
                  'Send the week\'s menu as a photo or PDF. The admin puts it '
                  'on everyone\'s app.',
                  style: t.textTheme.bodyMedium?.copyWith(color: muted)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Send the menu'),
                onPressed: busy ? null : sendMenu,
              ),
            ],
            const SizedBox(height: 24),
            const FieldLabel('Posted by you'),
            if (loadError != null)
              Text(loadError!, style: TextStyle(color: Tone.of(context).bad))
            else if (posts == null)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()))
            else if (posts!.isEmpty &&
                cancelled.isEmpty &&
                added.isEmpty &&
                myPolls.isEmpty)
              Text('Nothing in the last two weeks.',
                  style: t.textTheme.bodyMedium?.copyWith(color: muted))
            else
              GroupCard(children: [
                for (final p in posts!)
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    leading: IconTile(p.at.isAfter(now)
                        ? Icons.schedule_send_outlined
                        : Icons.notifications_outlined),
                    title: Text(p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      '${p.at.isAfter(now) ? 'Goes out' : 'Sent'} ${fmtDate(p.at)}, ${_hm(p.at)}',
                      if (seenLine(p, now).isNotEmpty) seenLine(p, now),
                    ].join(' · ')),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!await sure(
                                  'Take it back?',
                                  'Phones that already showed it keep it.',
                                  'Take back')) {
                                return;
                              }
                              try {
                                await takeBackPost(store.prefs, p.id);
                                await load();
                              } catch (e) {
                                say('$e'.replaceFirst('Exception: ', ''));
                              }
                            },
                      child: Text(p.at.isAfter(now) ? 'Cancel' : 'Take back'),
                    ),
                  ),
                for (final p in myPolls)
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    leading: const IconTile(Icons.how_to_vote_outlined),
                    title: Text(p.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${pollWhen(p, now)} · ${p.total} ${p.total == 1 ? 'vote' : 'votes'}\n${pollSummary(p)}'),
                    isThreeLine: true,
                    trailing: p.open
                        ? TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    try {
                                      await closePoll(store.prefs, p.id);
                                      await load();
                                    } catch (e) {
                                      say('$e'.replaceFirst('Exception: ', ''));
                                    }
                                  },
                            child: const Text('Close'))
                        : null,
                  ),
                for (final x in added)
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    leading: Icon(x.moved
                        ? Icons.edit_calendar_outlined
                        : Icons.event_available),
                    title: Text(x.course,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      '${x.moved ? 'Moved to' : 'Added'} ${fmtDate(x.date)}, ${x.start} to ${x.end}',
                      if (x.room.isNotEmpty) 'Room ${x.room}',
                      if (x.why.isNotEmpty) x.why,
                    ].join(' · ')),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await removeAddedClass(store.prefs, x.id);
                                say(x.moved
                                    ? 'Back at its old time'
                                    : 'Taken off the timetable');
                                await afterChange();
                              } catch (e) {
                                say('$e'.replaceFirst('Exception: ', ''));
                              }
                            },
                      child: Text(x.moved ? 'Undo' : 'Remove'),
                    ),
                  ),
                for (final (i, c) in cancelled.indexed)
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    leading: const IconTile(Icons.event_busy),
                    title: Text(
                        c.course.isEmpty
                            ? 'Every class at ${c.start}'
                            : c.course,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      'Cancelled · ${fmtDate(c.date)}, ${c.start}',
                      if (c.why.isNotEmpty) c.why,
                    ].join(' · ')),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await putBackClass(
                                    store.prefs, cancelledIds[i]);
                                say('Put back. Phones are updating now.');
                                await afterChange();
                              } catch (e) {
                                say('$e'.replaceFirst('Exception: ', ''));
                              }
                            },
                      child: const Text('Put back'),
                    ),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// How the notification will look on phones.
class _Preview extends StatelessWidget {
  const _Preview(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Crony(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Crony · now · preview',
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (body.isNotEmpty)
                Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
