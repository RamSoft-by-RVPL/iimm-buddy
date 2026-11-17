import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';

import 'backend.dart';
import 'background.dart';
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
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(indent: 56),
              rows[i],
            ],
          ]),
        );
    Widget pick(IconData icon, String title, String value, VoidCallback onTap,
            {bool enabled = true}) =>
        ListTile(
          enabled: enabled,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(value),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    Widget toggle(IconData icon, String title, String? about, bool value,
            ValueChanged<bool> onChanged) =>
        SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: about == null ? null : Text(about),
          value: value,
          onChanged: onChanged,
        );
    void say(String text) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
        children: [
          if (update != null)
            Strip(
              inset: false,
              icon: Icons.system_update_outlined,
              text: 'Version ${update.version} is ready. You have $appVersion.',
              action: 'Update',
              filled: true,
              onAction: () => runUpdate(context, store.prefs, update),
            ),
          if (health != null)
            HealthCard(
                state: health!.$1, problems: health!.$2, onFixed: _count),
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
            toggle(
                Icons.notification_important_outlined,
                'Attendance alerts',
                'When you are marked absent or a course drops below the '
                    'minimum',
                store.warnAttendance,
                (v) => changed(() => store.warnAttendance = v)),
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
          const SectionTitle('Class reminders'),
          group([
            toggle(
                Icons.alarm_outlined,
                'Remind me before each class',
                null,
                store.remindClasses,
                (v) => changed(() => store.remindClasses = v)),
            pick(Icons.timer_outlined, 'How early',
                '${store.leadMinutes} minutes before', () async {
              final n = await askNumber(context,
                  title: 'Minutes before class',
                  initial: store.leadMinutes,
                  min: 1,
                  max: 180);
              if (n != null) changed(() => store.leadMinutes = n);
            }, enabled: store.remindClasses),
            toggle(
                Icons.calendar_month_outlined,
                'Add classes to my phone calendar',
                'A calendar named IIMM Buddy with coming classes and Moodle '
                    'deadlines, kept up to date',
                store.calendarSync, (v) async {
              if (v && !await askCalendar()) {
                if (context.mounted) say('Calendar access was not allowed');
                return;
              }
              if (!v) await removeCalendar().catchError((_) {});
              changed(() => store.calendarSync = v);
            }),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
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
            toggle(
                Icons.notifications_outlined,
                'Moodle alerts',
                'New notes and assignments, and reminders before each '
                    'deadline',
                store.notifyMoodle,
                (v) => changed(() => store.notifyMoodle = v)),
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
          const SectionTitle('About'),
          group([
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text(update == null
                  ? 'Version $appVersion'
                  : 'Version ${update.version} is ready'),
              subtitle: Text(update == null
                  ? 'Tap to check for a newer version'
                  : 'You have $appVersion. Tap to update.'),
              onTap: () async {
                if (update != null) {
                  return runUpdate(context, store.prefs, update);
                }
                final u = await checkUpdate(store.prefs);
                if (!context.mounted) return;
                setState(() {});
                if (u == null) say('You have the newest version');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy'),
              subtitle: const Text('What the app does with your data'),
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
                leading: const Icon(Icons.build_outlined),
                title: const Text('Troubleshooting'),
                subtitle: Text(last == null
                    ? 'Background check has not run yet'
                    : 'Last background check: ${shortDate(last)}, '
                        '${clock(last)}'
                        '${pending == null ? '' : ' · $pending reminders set'}'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync),
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
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Support ID'),
                    subtitle: Text(installId(store.prefs)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
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
              'IIMM Buddy is made by a student. It is not an official app of '
              'IIM Mumbai.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
