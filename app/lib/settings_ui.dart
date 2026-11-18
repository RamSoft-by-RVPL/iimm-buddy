import 'dart:convert';

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';

import 'backend.dart';
import 'background.dart';
import 'crony_ui.dart';
import 'health.dart';
import 'leave_ui.dart';
import 'log.dart';
import 'notify.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'update.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
      {super.key,
      required this.store,
      required this.onChanged,
      required this.onSignOut});
  final Store store;
  final Future<void> Function() onChanged;
  final Future<void> Function() onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  int? pending;
  (NotifyState, List<Problem>)? health;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's Settings: look again.
    if (state == AppLifecycleState.resumed) _count();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _count();
  }

  Future<void> _count() async {
    try {
      final n = await pendingReminders();
      if (mounted) setState(() => pending = n);
      final h = await checkHealth();
      if (mounted) setState(() => health = h);
    } catch (_) {}
  }

  Future<void> changed(void Function() change) async {
    setState(change);
    await widget.onChanged();
    await _count();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final update = knownUpdate(store.prefs);
    final last = DateTime.tryParse(store.prefs.getString('bg_last') ?? '');
    final sheetAt = DateTime.tryParse(store.prefs.getString('tt_at') ?? '');
    final publisher = (store.prefs.getString('pub_key') ?? '').isNotEmpty;

    Widget group(List<Widget> rows) => Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(indent: 72),
              rows[i],
            ],
          ]),
        );
    Widget pick(IconData icon, String title, String value, VoidCallback onTap,
            {bool enabled = true}) =>
        ListTile(
          enabled: enabled,
          leading: IconTile(icon),
          title: Text(title),
          subtitle: Text(value),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    Widget toggle(IconData icon, String title, String? about, bool value,
            ValueChanged<bool> onChanged) =>
        SwitchListTile(
          secondary: IconTile(icon),
          title: Text(title),
          subtitle: about == null ? null : Text(about),
          value: value,
          onChanged: onChanged,
        );
    void say(String text) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));

    final (name, roll) = _student(store.prefs.getString('summary'));
    final batch = batchKey(store.prefs.getString('summary'));

    return Scaffold(
      appBar: screenBar('Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
        children: [
          _Profile(
            name: name,
            line: [
              if (roll.isNotEmpty) roll,
              if (batch != null) batch.toUpperCase(),
            ].join(' · '),
            version: update == null
                ? 'Version $appVersion'
                : 'Version ${update.version} is ready',
            action: playStore
                ? null
                : update == null
                    ? 'Check'
                    : 'Update',
            onAction: () async {
              if (update != null) {
                return runUpdate(context, store.prefs, update);
              }
              final u = await checkUpdate(store.prefs);
              if (!context.mounted) return;
              setState(() {});
              if (u == null) say('You have the newest version');
            },
          ),
          if (health != null)
            HealthCard(
                state: health!.$1, problems: health!.$2, onFixed: _count),
          SectionTitle('Alerts',
              trailing: Text(
                  '${[
                    store.remindClasses,
                    store.warnChanges,
                    store.warnAttendance,
                    store.notifyMoodle,
                    store.dishAlerts,
                    store.calendarSync,
                  ].where((on) => on).length} of 6 on',
                  style: TextStyle(
                      fontSize: 13, color: t.colorScheme.onSurfaceVariant))),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: [
              _AlertTile(
                  icon: Icons.alarm_outlined,
                  title: 'Classes',
                  note: '${store.leadMinutes} min before each',
                  on: store.remindClasses,
                  onTap: () => changed(
                      () => store.remindClasses = !store.remindClasses)),
              _AlertTile(
                  icon: Icons.swap_horiz,
                  title: 'Class changes',
                  note: 'Moved or cancelled',
                  on: store.warnChanges,
                  onTap: () =>
                      changed(() => store.warnChanges = !store.warnChanges)),
              _AlertTile(
                  icon: Icons.notification_important_outlined,
                  title: 'Attendance',
                  note: 'Absent, or below ${store.minPct}%',
                  on: store.warnAttendance,
                  onTap: () => changed(
                      () => store.warnAttendance = !store.warnAttendance)),
              _AlertTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Moodle',
                  note: 'New notes and deadlines',
                  on: store.notifyMoodle,
                  onTap: () =>
                      changed(() => store.notifyMoodle = !store.notifyMoodle)),
              _AlertTile(
                  icon: Icons.favorite_border,
                  title: 'Favourite dishes',
                  note: store.favDishes.isEmpty
                      ? 'Heart dishes in the menu'
                      : store.favDishes.length == 1
                          ? store.favDishes.first
                          : '${store.favDishes.first} and '
                              '${store.favDishes.length - 1} more',
                  on: store.dishAlerts,
                  onTap: () =>
                      changed(() => store.dishAlerts = !store.dishAlerts)),
              _AlertTile(
                  icon: Icons.calendar_month_outlined,
                  title: 'Phone calendar',
                  note: 'Classes and deadlines',
                  on: store.calendarSync,
                  onTap: () async {
                    final v = !store.calendarSync;
                    if (v && !await askCalendar()) {
                      if (context.mounted) {
                        say('Calendar access was not allowed');
                      }
                      return;
                    }
                    if (!v) await removeCalendar().catchError((_) {});
                    changed(() => store.calendarSync = v);
                  }),
            ],
          ),
          const SectionTitle('Attendance'),
          group([
            pick(Icons.flag_outlined, 'Minimum attendance',
                '${store.minPct}% in every course', () async {
              final n = await askNumber(context,
                  title: 'Minimum attendance %',
                  initial: store.minPct,
                  min: 1,
                  max: 100,
                  help: 'The app warns you before a course falls below this.');
              if (n != null) changed(() => store.minPct = n);
            }),
            pick(
                Icons.mail_outline,
                'Send corrections to',
                store.fixEmail.isEmpty
                    ? 'Not set: you type the address each time'
                    : store.fixEmail, () async {
              final v = await askText(context,
                  title: 'Send corrections to',
                  keyboard: TextInputType.emailAddress,
                  initial: store.fixEmail,
                  help: 'For example the programme office. When a class shows '
                      'absent or not marked, tap it and the app writes the '
                      'email to this address. Leave empty to choose each '
                      'time.');
              if (v != null) changed(() => store.fixEmail = v);
            }),
          ]),
          const SectionTitle('Classes'),
          group([
            pick(Icons.timer_outlined, 'Remind me',
                '${store.leadMinutes} minutes before each class', () async {
              final n = await askNumber(context,
                  title: 'Minutes before class',
                  initial: store.leadMinutes,
                  min: 1,
                  max: 180);
              if (n != null) changed(() => store.leadMinutes = n);
            }, enabled: store.remindClasses),
            ListTile(
              leading: const IconTile(Icons.table_chart_outlined),
              title: const Text('Weekly timetable'),
              subtitle: Text(sheetAt == null
                  ? 'Not received yet. It arrives by itself when your '
                      'batch\'s timetable is published.'
                  : '${store.sheetClasses.length} classes, updated '
                      '${shortDate(sheetAt)}, ${clock(sheetAt)}. Adds classes '
                      'the attendance portal does not list yet.'),
            ),
          ]),
          const SectionTitle('Moodle'),
          group([
            pick(Icons.assignment_late_outlined, 'Assignment reminders',
                dueSummary(store.dueHours), () async {
              if (await askDueTimes(context, store)) changed(() {});
            }, enabled: store.notifyMoodle),
            toggle(
                Icons.download_for_offline_outlined,
                'Download new notes on Wi-Fi',
                'Saves every course file to the phone in the background',
                store.autoDownload,
                (v) => changed(() => store.autoDownload = v)),
          ]),
          const SectionTitle('Privacy'),
          group([
            ListTile(
              leading: const IconTile(Icons.privacy_tip_outlined),
              title: const Text('What the app does with your data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrivacyScreen())),
            ),
            toggle(
                Icons.bug_report_outlined,
                'Send diagnostics',
                'A log of what the app does, with your name and roll number, '
                    'goes to the maker of the app so problems can be fixed',
                diagnosticsOn(store.prefs), (v) async {
              await store.prefs.setBool('diag', v);
              if (!v) await store.prefs.remove('log_q');
              if (mounted) setState(() {});
            }),
          ]),
          const SectionTitle('Help and testing'),
          Card(
            child: Theme(
              data: t.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const IconTile(Icons.build_outlined),
                title: const Text('Troubleshooting'),
                subtitle: Text(last == null
                    ? 'Background check has not run yet'
                    : 'Last background check: ${shortDate(last)}, '
                        '${clock(last)}'
                        '${pending == null ? '' : ' · $pending reminders set'}'),
                children: [
                  ListTile(
                    leading: const IconTile(Icons.sync),
                    title: const Text('Run a background check now'),
                    subtitle: const Text(
                        'Checks attendance and Moodle the way the app does '
                        'on its own'),
                    // Long press: run it in one minute, with the app closed.
                    onLongPress: () =>
                        runBackgroundNow(delay: const Duration(minutes: 1)),
                    onTap: () async {
                      await runBackgroundNow();
                      if (!context.mounted) return;
                      say('Started. Alerts appear if anything is new.');
                      await Future<void>.delayed(const Duration(seconds: 20));
                      await store.prefs.reload();
                      if (mounted) setState(() {});
                    },
                  ),
                  ListTile(
                    leading: const IconTile(Icons.badge_outlined),
                    title: const Text('Support ID'),
                    subtitle: Text(installId(store.prefs)),
                  ),
                  ListTile(
                    leading: const IconTile(Icons.key_outlined),
                    title: const Text('Publisher key'),
                    subtitle: Text(publisher
                        ? 'Set. Opening the mailed timetable sheet with this '
                            'app sends it to the whole class.'
                        : 'Only for the student who publishes the timetable'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final v = await askText(context,
                          title: 'Publisher key',
                          initial: store.prefs.getString('pub_key') ?? '',
                          help: 'Leave empty unless you publish the timetable '
                              'for your batch.');
                      if (v == null) return;
                      await store.prefs.setString('pub_key', v);
                      if (v.isNotEmpty && store.sheetClasses.isNotEmpty) {
                        String msg;
                        try {
                          msg = '${await publishTimetable(store.prefs)} '
                              'classes sent to the whole class';
                        } catch (e) {
                          msg = '$e'.replaceFirst('Exception: ', '');
                        }
                        if (context.mounted) say(msg);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: tone.bad,
                side: BorderSide(color: tone.bad.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text(
                      'Your sign-in and the Moodle files saved on this phone '
                      'will be removed. Your settings and leave log stay.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign out')),
                  ],
                ),
              );
              if (yes == true) {
                await widget.onSignOut();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 12),
          Text(
              'Crony is made by a student. It is not an official app of '
              'IIM Mumbai.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The student's name and roll number from the attendance site's answer.
(String, String) _student(String? raw) {
  try {
    final st = ((jsonDecode(raw!) as Map)['data'] as Map)['student'] as Map;
    return ('${st['name'] ?? ''}'.trim(), '${st['roll_number'] ?? ''}'.trim());
  } catch (_) {
    return ('', '');
  }
}

String _initials(String name) {
  final w = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (w.isEmpty) return 'C';
  return (w.first[0] + (w.length > 1 ? w.last[0] : '')).toUpperCase();
}

/// Who is signed in, and which version this is.
class _Profile extends StatelessWidget {
  const _Profile(
      {required this.name,
      required this.line,
      required this.version,
      required this.action,
      required this.onAction});
  final String name;
  final String line;
  final String version;
  final String? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const ink = Brand.wineInk;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
          color: Brand.wine, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: Brand.lime, shape: BoxShape.circle),
            child: Text(_initials(name),
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Brand.wine)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? 'Crony' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleMedium?.copyWith(
                      color: ink, fontWeight: FontWeight.w700, height: 1.2)),
              if (line.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(line,
                    style: TextStyle(
                        fontSize: 13,
                        color: ink.withOpacity(0.7),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Divider(height: 1, color: ink.withOpacity(0.14)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.system_update_outlined,
              size: 18, color: ink.withOpacity(0.7)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(version, style: const TextStyle(fontSize: 13.5, color: ink))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: Brand.lime),
              child: Text(action!),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Updates through Google Play',
                  style: TextStyle(fontSize: 12, color: ink.withOpacity(0.6))),
            ),
        ]),
      ]),
    );
  }
}

/// One kind of alert, on or off at a tap.
class _AlertTile extends StatelessWidget {
  const _AlertTile(
      {required this.icon,
      required this.title,
      required this.note,
      required this.on,
      required this.onTap});
  final IconData icon;
  final String title;
  final String note;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final bg = on
        ? (dark ? Brand.wineDark : Brand.wine)
        : t.cardTheme.color ?? t.colorScheme.surface;
    final fg = on ? Brand.wineInk : t.colorScheme.onSurface;
    final sub =
        on ? Brand.wineInk.withOpacity(0.72) : t.colorScheme.onSurfaceVariant;
    return Semantics(
      toggled: on,
      button: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 22, color: on ? Brand.lime : sub),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 34,
                  height: 20,
                  padding: const EdgeInsets.all(3),
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: on
                          ? Brand.lime
                          : t.colorScheme.outlineVariant.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10)),
                  child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: on ? Brand.wine : t.colorScheme.surface,
                          shape: BoxShape.circle)),
                ),
              ]),
              const Spacer(),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 2),
              Text(on ? note : 'Off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: sub)),
            ]),
          ),
        ),
      ),
    );
  }
}
