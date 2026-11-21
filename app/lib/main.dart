import 'dart:async';

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'attendance_ui.dart';
import 'backend.dart';
import 'crony_ui.dart';
import 'background.dart';
import 'exams_ui.dart';
import 'faculty.dart';
import 'gate_mail_ui.dart';
import 'polls_ui.dart';
import 'role_ui.dart';
import 'my_reminders.dart';
import 'health.dart';
import 'inbox.dart';
import 'inbox_ui.dart';
import 'leave.dart';
import 'leave_ui.dart';
import 'log.dart';
import 'mascot.dart';
import 'menu_ui.dart';
import 'moodle.dart';
import 'moodle_ui.dart';
import 'notify.dart';
import 'plan_ui.dart';
import 'push.dart';
import 'session.dart';
import 'settings_ui.dart';
import 'theme.dart';
import 'site.dart';
import 'timetable_ui.dart';
import 'ui_common.dart';
import 'update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store(await SharedPreferences.getInstance());
  teacherDirectory = decodeTeachers(store.prefs.getString('faculty'));
  final session = Session();
  try {
    await initNotifications();
    await registerBackground();
    unawaited(initPush(store.prefs));
  } catch (_) {
    // The app still works without reminders and background checks.
  }
  runApp(AttendanceApp(
      store: store,
      session: session,
      moodle: Moodle(store.prefs, onScreen: session.ensureMoodle)));
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp(
      {super.key,
      required this.store,
      required this.session,
      required this.moodle});
  final Moodle moodle;
  final Store store;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crony',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: Root(store: store, session: session, moodle: moodle),
    );
  }
}

class Root extends StatefulWidget {
  const Root(
      {super.key,
      required this.store,
      required this.session,
      required this.moodle});
  final Moodle moodle;
  final Store store;
  final Session session;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  /// Crony's first-visit note for each tab.
  static const _tips = [
    "I keep count so you don't have to. Your next class and anything that "
        'needs you sit right here.',
    'Each bar is one class. The lime ones at the end are classes you can '
        'still miss.',
    "Tap any upcoming class and I'll show you what skipping it does.",
    "Tap days on the calendar. I'll check them against every course.",
    'Search reads inside every saved PDF and slide, not just the file names.',
  ];

  Snapshot? snap;
  String? error;
  bool syncing = false;
  int tab = 0;
  List<Problem> problems = const [];
  Timer? _tick;
  int _unread = 0;
  final moodleKey = GlobalKey<MoodleTabState>();

  Store get store => widget.store;
  Session get session => widget.session;
  Moodle get moodle => widget.moodle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    snap = store.cached;
    session.addListener(_onSession);
    pushArrived.addListener(_onPush);
    refresh();
    _taps = notificationTaps.stream.listen(_openFrom);
    openedFromNotification().then((p) {
      if (p != null) _openFrom(p);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takeSheet();
      _recount();
    });
    // Reminders shown while the app is open, and the background check,
    // add to the bell's count: look again every minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      store.prefs.reload().then((_) => _recount());
    });
  }

  /// Rebuilds when the number on the bell changes.
  void _recount() {
    if (!mounted) return;
    final n = inboxUnread(store.prefs, DateTime.now());
    if (n != _unread) setState(() => _unread = n);
  }

  Future<void> _openInbox() async {
    final place = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => InboxScreen(prefs: store.prefs)));
    _recount();
    if (place != null) _openFrom(place);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_onSession);
    pushArrived.removeListener(_onPush);
    _taps?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// A timetable sheet opened with, or shared to, the app.
  Future<void> _takeSheet() async {
    try {
      final f = await takeSharedFile();
      if (f == null || !mounted) return;
      final found = await store.importSheet(f.$2);
      logEvent(store.prefs, 'sheet_import', '${found.length} classes');
      final old = snap;
      final s = store.cached;
      if (!mounted) return;
      setState(() {
        snap = s ?? snap;
        tab = 2;
      });
      if (s != null) await afterSync(store, old, s, alert: false);
      // The publisher's phone passes it on to the whole batch.
      var sent = '';
      if ((store.prefs.getString('pub_key') ?? '').isNotEmpty) {
        try {
          await publishTimetable(store.prefs);
          sent = ' Sent to the whole class.';
          logEvent(store.prefs, 'publish_ok', '${found.length} classes');
        } catch (e) {
          sent = ' Not sent to the class: ${errorText(e)}.';
          logEvent(store.prefs, 'publish_fail', errorLine(e));
        }
      }
      final first =
          found.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Timetable added: ${found.length} classes from '
              '${shortDate(first)}. Reminders are set.$sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not read that file as a timetable. '
              '${errorText(e)}')));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _takeSheet();
    // Background checks may have saved newer data while the app was away.
    _checkHealth();
    store.prefs.reload().then((_) {
      if (!mounted) return;
      setState(() => snap = store.cached ?? snap);
      _recount();
      if (session.state == SessionState.needsLogin) return;
      if (snap == null ||
          DateTime.now().difference(snap!.syncedAt).inMinutes >= 15) {
        refresh();
      } else {
        _quickPull();
      }
    });
  }

  StreamSubscription<String>? _taps;

  /// Goes where a tapped notification points: "timetable", "course:12",
  /// "moodle" or "home".
  void _openFrom(String place) {
    if (!mounted) return;
    logEvent(store.prefs, 'opened_from', place);
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (place == 'timetable') {
      setState(() => tab = 2);
    } else if (place == 'menu') {
      setState(() => tab = 0);
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => MenuScreen(store: store)));
    } else if (place == 'moodle') {
      setState(() => tab = 4);
    } else if (place.startsWith('course:')) {
      setState(() => tab = 4);
      final id = int.tryParse(place.substring(7));
      MoodleCourse? course;
      for (final c in moodle.cachedCourses ?? const <MoodleCourse>[]) {
        if (c.id == id) course = c;
      }
      if (course != null) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CourseScreen(moodle: moodle, course: course!)));
      }
    } else {
      setState(() => tab = 0);
    }
  }

  /// A push was handled while the app is open: show what it brought.
  void _onPush() {
    store.prefs.reload().then((_) {
      if (mounted) setState(() => snap = store.cached ?? snap);
      _recount();
    });
  }

  /// Every time the app comes to the front: messages, the shared timetable
  /// and updates from the server, without waiting for the next full refresh.
  Future<void> _quickPull() async {
    final s = snap;
    if (s == null) return;
    try {
      final merged = await withSharedTimetable(store, s, alert: false);
      await checkUpdate(store.prefs);
      if (!mounted) return;
      setState(() => snap = merged);
      if (!identical(merged, s)) {
        await afterSync(store, s, merged, alert: false);
      }
    } catch (_) {}
  }

  SessionState? _last;
  void _onSession() {
    final s = session.state;
    if (s == SessionState.signedIn && _last == SessionState.needsLogin) {
      logEvent(store.prefs, 'signed_in');
      refresh(); // the user has just signed in on screen
    }
    _last = s;
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    if (syncing) return;
    setState(() {
      syncing = true;
      error = null;
    });
    logEvent(store.prefs, 'refresh', 'version $appVersion');
    try {
      final old = snap;
      var s = await store.sync(session.api);
      if (mounted) setState(() => snap = s);
      s = await withSharedTimetable(store, s, alert: false);
      if (mounted) setState(() => snap = s);
      await afterSync(store, old, s, alert: false);
      logEvent(store.prefs, 'sync_ok', '${s.next.length} classes ahead');
      unawaited(initPush(store.prefs)); // the batch is known now
      unawaited(checkUpdate(store.prefs).then((_) {
        if (mounted) setState(() {});
      }));
      await _askPermissionOnce();
      // Once: how the student wants assignment reminders.
      if (mounted &&
          store.prefs.getBool('setup_done') == true &&
          store.prefs.getBool('asked_due') != true) {
        await store.prefs.setBool('asked_due', true);
        if (mounted) await askDueTimes(context, store);
      }
      // Moodle in the same pass: deadlines for the timetable, reminders,
      // and it keeps the Moodle session alive.
      // With alerts: something added to Moodle is announced even when it is
      // found while the app is open.
      unawaited(checkMoodle(store, moodle, alert: true).then((_) {
        logEvent(store.prefs, 'moodle_ok');
        if (mounted) setState(() {});
        _recount();
      }).catchError((Object e) {
        logEvent(store.prefs, e is NotSignedIn ? 'need_login' : 'moodle_fail',
            e is NotSignedIn ? 'moodle' : errorLine(e));
      }).whenComplete(() => flushLogs(store.prefs, force: true)));
    } on NotSignedIn {
      // The sign-in screen takes over.
      logEvent(store.prefs, 'need_login', 'attendance');
    } catch (e) {
      logEvent(store.prefs, 'sync_fail', errorLine(e));
      if (mounted) setState(() => error = errorText(e));
      unawaited(flushLogs(store.prefs, force: true));
    } finally {
      if (mounted) setState(() => syncing = false);
      _recount();
    }
  }

  Future<void> _askPermissionOnce() => _checkHealth();

  /// Looks for phone settings that would stop reminders.
  Future<void> _checkHealth() async {
    try {
      final (_, p) = await checkHealth();
      final health = [for (final x in p) x.code].join(', ');
      if (store.prefs.getString('log_health') != health) {
        await store.prefs.setString('log_health', health);
        logEvent(store.prefs, 'health', health.isEmpty ? 'all fine' : health);
      }
      if (mounted) setState(() => problems = p);
    } catch (_) {}
  }

  /// Settings changed: recompute what depends on them.
  Future<void> settingsChanged() async {
    final s = store.cached ?? snap;
    setState(() => snap = s);
    if (s != null) await afterSync(store, s, s, alert: false);
    unawaited(checkMoodle(store, moodle, alert: true).catchError((_) {}));
  }

  Future<void> signOut() async {
    await store.clear();
    await moodle.clear();
    await removeCalendar().catchError((_) {});
    store.calendarSync = false;
    setState(() => snap = null);
    await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // Straight after installing: the permissions reminders depend on.
    if (store.prefs.getBool('setup_done') != true) {
      return SetupScreen(onDone: () async {
        await store.prefs.setBool('setup_done', true);
        logEvent(store.prefs, 'setup_done');
        await _checkHealth();
        if (mounted) setState(() {});
      });
    }
    if (session.state == SessionState.needsLogin) {
      return LoginScreen(session: session);
    }
    final s = snap;
    final notice = currentNotice(store.prefs, DateTime.now());
    final update = knownUpdate(store.prefs);
    Widget needData(Widget Function(Snapshot) build) => s == null
        ? Center(
            child: error != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    EmptyNote(
                        icon: Icons.cloud_off_outlined,
                        title: 'Could not load your attendance',
                        text: error),
                    FilledButton(
                        onPressed: refresh, child: const Text('Try again')),
                  ])
                : const LoadingNote('Getting your attendance...'),
          )
        : Column(children: [
            if (update != null)
              Strip(
                icon: Icons.system_update_outlined,
                text: 'Version ${update.version} is ready.'
                    '${update.notes.isEmpty ? '' : ' ${update.notes}'}',
                action: 'Update',
                filled: true,
                onAction: () => runUpdate(context, store.prefs, update),
              ),
            if (notice != null)
              Strip(
                icon: Icons.campaign_outlined,
                text: notice.body.isEmpty
                    ? notice.title
                    : '${notice.title}\n${notice.body}',
                action: 'Close',
                onAction: () async {
                  await store.prefs.setInt('notice_closed', notice.id);
                  if (mounted) setState(() {});
                },
              ),
            if (problems.isNotEmpty &&
                (store.remindClasses || store.notifyMoodle))
              Strip(
                icon: Icons.notifications_off_outlined,
                color: Tone.of(context).bad,
                text: problems.length == 1
                    ? '${problems.first.title}. Reminders may not arrive.'
                    : 'Reminders may not arrive: ${problems.length} phone '
                        'settings need a change.',
                action: 'Fix',
                onAction: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                              store: store,
                              onChanged: settingsChanged,
                              onSignOut: signOut)));
                  _checkHealth();
                },
              ),
            if (error != null)
              Strip(
                icon: Icons.cloud_off_outlined,
                color: Tone.of(context).warn,
                text: 'Showing saved data. Could not refresh: $error',
                action: 'Retry',
                onAction: refresh,
              ),
            Expanded(child: build(s)),
          ]);

    final now = DateTime.now();
    final shown = snap;
    final synced = shown?.syncedAt;
    final (title, subtitle) = switch (tab) {
      0 => (
          longDay(now),
          syncing
              ? 'Updating from the portal'
              : synced == null
                  ? null
                  : 'Updated ${DateUtils.isSameDay(synced, now) ? '' : '${fmtDate(synced)}, '}${hhmm(synced)} from the portal'
        ),
      1 => ('Register', '${store.minPct}% needed in every course'),
      2 => ('Timetable', null),
      3 => ('Plan leave', null),
      _ => ('Moodle', null),
    };
    final below = shown != null &&
        shown.courses.any((c) => statusColor(c, store.minPct) == bad);
    final tight = shown != null &&
        shown.courses.any((c) => statusColor(c, store.minPct) == warn);

    Widget attendance(Snapshot s, {bool register = false}) => AttendanceTab(
          register: register,
          snap: s,
          minPct: store.minPct,
          onRefresh: refresh,
          fixEmail: store.fixEmail,
          leaveCount:
              absences(s).where((x) => store.leaves.containsKey(x.id)).length,
          onOpenTimetable: () => setState(() => tab = 2),
          onOpenRegister: () => setState(() => tab = 1),
          exams:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RoleCard(store: store, snap: s),
            PollsCard(store: store),
            MenuCard(
                store: store,
                onChanged: () {
                  if (mounted) setState(() {});
                }),
            ExamsCard(
                store: store,
                snap: s,
                onChanged: () {
                  if (mounted) setState(() {});
                }),
            MyRemindersCard(
                store: store,
                onChanged: () {
                  if (mounted) setState(() {});
                }),
            GateMailCard(store: store, snap: s),
            TermCard(events: store.calendar),
          ]),
          shortNames: store.shortNames,
          onShortName: (c, v) {
            store.setShortName(c.name, v);
            settingsChanged(); // reminders and widget use the new name
          },
          onOpenLeave: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => LeaveLogScreen(
                        store: store, snap: s, minPct: store.minPct)));
            if (mounted) setState(() {});
          },
          onEditTotal: (c, total) {
            store.setTotal(c.id, total);
            setState(() => snap = store.cached ?? snap);
          },
        );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        title: BigTitle(title, subtitle: subtitle),
        actions: [
          if (tab == 0 && shown != null)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Crony(
                  mood: below
                      ? Mood.worried
                      : tight
                          ? Mood.idle
                          : Mood.happy,
                  size: 34),
            ),
          InboxBell(unread: _unread, onPressed: _openInbox),
          if (tab != 0)
            IconButton(
              tooltip: 'Refresh',
              onPressed: syncing
                  ? null
                  : () {
                      refresh();
                      moodleKey.currentState?.load();
                    },
              icon: syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                        store: store,
                        onChanged: settingsChanged,
                        onSignOut: signOut))),
          ),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
            child: TweenAnimationBuilder<double>(
          key: ValueKey(tab),
          tween: Tween(begin: calm(context) ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, 6 * (1 - v)), child: child)),
          child: switch (tab) {
            0 => needData((s) => attendance(s)),
            1 => needData((s) => attendance(s, register: true)),
            2 => needData((s) => TimetableTab(
                snap: s,
                minPct: store.minPct,
                fixEmail: store.fixEmail,
                exams: store.allExams(s.courses),
                calendar: store.calendar,
                shortNames: store.shortNames,
                onOpenDeadline: (d) {
                  if (d.url.isEmpty) return;
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => WebPage(
                              title: d.name, url: d.url, moodle: moodle)));
                },
                deadlines: moodle.cachedDeadlines ?? const [])),
            3 => needData((s) => PlanTab(
                snap: s,
                minPct: store.minPct,
                calendar: store.calendar,
                shortNames: store.shortNames)),
            _ => MoodleTab(key: moodleKey, moodle: moodle),
          },
        )),
        if ((s != null || tab == 4) && store.prefs.getBool('tip_$tab') != true)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: CronyTip(
                key: ValueKey('tip$tab'),
                text: _tips[tab],
                onDone: () async {
                  await store.prefs.setBool('tip_$tab', true);
                  if (mounted) setState(() {});
                }),
          ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.view_week_outlined),
              selectedIcon: Icon(Icons.view_week),
              label: 'Register'),
          NavigationDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule),
              label: 'Timetable'),
          NavigationDestination(
              icon: Icon(Icons.event_busy_outlined),
              selectedIcon: Icon(Icons.event_busy),
              label: 'Leave'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Moodle'),
        ],
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        title: const BigTitle('Sign in once',
            subtitle: 'Your IIM Mumbai Microsoft account'),
        actions: [
          IconButton(
            tooltip: 'Start the sign-in again',
            onPressed: session.restartLogin,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(children: [
        const Strip(
          icon: Icons.lock_outline,
          text: 'Sign in with your IIM Mumbai Microsoft account. Choose '
              '"Yes" when asked to stay signed in, so you only do this once. '
              'Your password goes only to Microsoft.',
        ),
        const SizedBox(height: 4),
        Expanded(child: WebViewWidget(controller: session.controller)),
      ]),
    );
  }
}
