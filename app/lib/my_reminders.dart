// Reminders the student sets for themselves: once, every day or every week.
// Kept on the phone (and in its backup); the coming ones are scheduled
// again after every refresh, so repeating ones never run out.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'crony_ui.dart';
import 'notify.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';

const repeatKinds = ['Once', 'Every day', 'Every week'];

class MyReminder {
  MyReminder(this.id, this.title, this.at, this.repeat);

  /// Made from the time it was added; also numbers its notifications.
  final int id;
  final String title;

  /// The first time it goes off.
  final DateTime at;

  /// One of [repeatKinds].
  final String repeat;

  Map<String, dynamic> toJson() =>
      {'id': id, 't': title, 'a': at.toIso8601String(), 'r': repeat};

  static MyReminder fromJson(Map<String, dynamic> j) => MyReminder(
      j['id'] as int,
      '${j['t']}',
      DateTime.parse('${j['a']}'),
      repeatKinds.contains(j['r']) ? '${j['r']}' : repeatKinds.first);

  /// The next times it goes off after [now], at most [most].
  List<DateTime> nextTimes(DateTime now, {int most = 14}) {
    if (repeat == 'Once') return at.isAfter(now) ? [at] : [];
    final step = repeat == 'Every day' ? 1 : 7;
    var t = at;
    if (t.isBefore(now)) {
      final days = now.difference(t).inDays ~/ step * step;
      t = DateTime(t.year, t.month, t.day + days, t.hour, t.minute);
      while (!t.isAfter(now)) {
        t = DateTime(t.year, t.month, t.day + step, t.hour, t.minute);
      }
    }
    return [
      for (var i = 0; i < most; i++)
        DateTime(t.year, t.month, t.day + i * step, t.hour, t.minute)
    ];
  }

  /// Still has a time to come.
  bool live(DateTime now) => nextTimes(now, most: 1).isNotEmpty;
}

List<MyReminder> decodeMyReminders(String? raw) {
  try {
    return [
      for (final j in jsonDecode(raw ?? '[]') as List)
        MyReminder.fromJson((j as Map).cast<String, dynamic>())
    ];
  } catch (_) {
    return [];
  }
}

String encodeMyReminders(List<MyReminder> l) =>
    jsonEncode([for (final r in l) r.toJson()]);

extension MyReminderStore on Store {
  List<MyReminder> get myReminders =>
      decodeMyReminders(prefs.getString('my_rem'));
  set myReminders(List<MyReminder> v) =>
      prefs.setString('my_rem', encodeMyReminders(v));
}

/// The notifications for [list]: each coming time, up to two weeks of a
/// daily one and eight weeks of a weekly one.
List<Reminder> myReminderAlerts(List<MyReminder> list, DateTime now) => [
      for (final r in list)
        for (final (k, t) in r
            .nextTimes(now, most: r.repeat == 'Every week' ? 8 : 14)
            .indexed)
          Reminder(
              2000000 + (r.id % 50000) * 20 + k,
              t,
              r.title,
              r.repeat == 'Once'
                  ? 'Your reminder'
                  : 'Your reminder · ${r.repeat.toLowerCase()}',
              open: 'home')
    ];

Future<void> scheduleMyReminders(Store store) => scheduleReminders(store.prefs,
    'rem_mine', 'mine', myReminderAlerts(store.myReminders, DateTime.now()));

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// When it goes off next, in words: "Tomorrow, 08:00 · every day".
String reminderWhen(MyReminder r, DateTime now) {
  final next = r.nextTimes(now, most: 1);
  final t = next.isEmpty ? r.at : next.first;
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(t.year, t.month, t.day).difference(today).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => fmtDate(t),
  };
  return [
    '$day, ${_hm(t)}',
    if (r.repeat != 'Once') r.repeat.toLowerCase(),
  ].join(' · ');
}

/// Add or change one reminder. Returns true when something was saved.
Future<bool> editMyReminder(BuildContext context, Store store,
    {MyReminder? reminder}) async {
  final title = TextEditingController(text: reminder?.title ?? '');
  var repeat = reminder?.repeat ?? repeatKinds.first;
  final soon = DateTime.now().add(const Duration(hours: 1));
  var at = reminder?.at ?? DateTime(soon.year, soon.month, soon.day, soon.hour);

  final result = await showModalBottomSheet<String>(
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
                SheetHead(reminder == null ? 'Add a reminder' : 'Change',
                    subtitle: 'Crony reminds you at that time'),
                TextField(
                  controller: title,
                  autofocus: reminder == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Remind me to',
                      hintText: 'Submit the lab file, call home, gym'),
                ),
                const SizedBox(height: 16),
                const FieldLabel('When'),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(fmtDate(at)),
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: at,
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 1)),
                            lastDate:
                                DateTime.now().add(const Duration(days: 400)));
                        if (d != null) {
                          set(() => at = DateTime(
                              d.year, d.month, d.day, at.hour, at.minute));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(_hm(at)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(at));
                        if (t != null) {
                          set(() => at = DateTime(
                              at.year, at.month, at.day, t.hour, t.minute));
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const FieldLabel('Repeat'),
                Segmented(
                    options: repeatKinds,
                    selected: repeatKinds.indexOf(repeat).clamp(0, 9),
                    onChanged: (i) => set(() => repeat = repeatKinds[i])),
                const SizedBox(height: 18),
                Row(children: [
                  if (reminder != null)
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                        child: Text('Remove',
                            style: TextStyle(color: Tone.of(ctx).bad))),
                  const Spacer(),
                  FilledButton(
                      onPressed: () {
                        if (title.text.trim().isEmpty) return;
                        if (repeat == 'Once' && !at.isAfter(DateTime.now())) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Pick a time that is still to come')));
                          return;
                        }
                        Navigator.pop(ctx, 'save');
                      },
                      child: const Text('Save')),
                ]),
              ]),
        ),
      ),
    ),
  );
  if (result == null) return false;
  final all = [
    for (final r in store.myReminders)
      if (r.id != reminder?.id) r
  ];
  if (result == 'save') {
    all.add(MyReminder(
        reminder?.id ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.text.trim(),
        at,
        repeat));
  }
  store.myReminders = all;
  try {
    await scheduleMyReminders(store);
  } catch (_) {}
  return true;
}

/// "Your reminders" on the home screen: the coming ones, soonest first.
class MyRemindersCard extends StatelessWidget {
  const MyRemindersCard(
      {super.key, required this.store, required this.onChanged});
  final Store store;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final coming = [
      for (final r in store.myReminders)
        if (r.live(now)) r
    ]..sort((a, b) => a
        .nextTimes(now, most: 1)
        .first
        .compareTo(b.nextTimes(now, most: 1).first));
    Future<void> edit([MyReminder? r]) async {
      if (await editMyReminder(context, store, reminder: r)) onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Your reminders',
          trailing: InkWell(
            onTap: edit,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Add',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.primary)),
            ),
          )),
      coming.isEmpty
          ? TiltCard(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
                leading: const IconTile(Icons.alarm_add_outlined),
                title: const Text('No reminders yet',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Add anything you must not forget, once or every day or week'),
                onTap: edit,
              ),
            )
          : GroupCard(children: [
              for (final r in coming)
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                  leading:
                      IconTile(r.repeat == 'Once' ? Icons.alarm : Icons.repeat),
                  title: Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(reminderWhen(r, now)),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => edit(r),
                ),
            ]),
    ]);
  }
}
