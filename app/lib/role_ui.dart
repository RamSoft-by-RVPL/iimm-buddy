// For students the admin made CR, mess secretary or hostel secretary: send
// notifications to the people their role covers and, for a CR, call off
// classes of their batch.

import 'package:flutter/material.dart';

import 'backend.dart';
import 'crony_ui.dart';
import 'mascot.dart';
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
            ? 'Post updates to ${r.audience}, or cancel a class'
            : 'Post updates to ${r.audience}'),
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
  final title = TextEditingController();
  final body = TextEditingController();
  DateTime? later;
  var busy = false;
  List<MyPost>? posts;
  int reach = 0;
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
    final coming = (widget.snap?.sessions ?? [])
        .where((s) => !s.cancelled && !s.date.isBefore(today))
        .map((s) => s.date)
        .toList()
      ..sort();
    return coming.isEmpty ? today : coming.first;
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
        for (final s in widget.snap?.sessions ?? <ClassSlot>[])
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
      await load();
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
    final names = {for (final c in widget.snap?.courses ?? <Course>[]) c.name}
        .toList()
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
            if (r.canCancel) ...[
              const SizedBox(height: 24),
              const FieldLabel('Cancel a class'),
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
                    ),
                ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : addExtra,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Class not listed'),
                ),
              ),
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
            const SizedBox(height: 24),
            const FieldLabel('Posted by you'),
            if (loadError != null)
              Text(loadError!, style: TextStyle(color: Tone.of(context).bad))
            else if (posts == null)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()))
            else if (posts!.isEmpty && cancelled.isEmpty)
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
                                await load();
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
