// Finds out why reminders might not arrive on this phone and says how to
// fix it. Most missed reminders come from three phone settings.

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';

import 'glass.dart';
import 'mascot.dart';
import 'motion.dart';

import 'notify.dart';
import 'crony_ui.dart';
import 'theme.dart';
import 'update.dart';

class Problem {
  Problem(this.code, this.title, this.how, this.button, this.fix);

  /// Short name used in the diagnostic log.
  final String code;
  final String title;
  final String how;
  final String button;
  final Future<void> Function() fix;
}

/// Phone makers that stop apps in the background unless told otherwise,
/// with the name each one gives the switch.
String? makerTip(String maker) {
  if (RegExp('xiaomi|redmi|poco').hasMatch(maker)) {
    return 'On Xiaomi, Redmi and Poco phones also switch on "Autostart" for '
        'this app, and set Battery saver to "No restrictions".';
  }
  if (RegExp('oppo|realme|oneplus').hasMatch(maker)) {
    return 'On Oppo, Realme and OnePlus phones also allow "Auto launch" and '
        '"Background activity" for this app.';
  }
  if (RegExp('vivo|iqoo').hasMatch(maker)) {
    return 'On Vivo and iQOO phones also allow "Autostart" and "High '
        'background power consumption" for this app.';
  }
  if (maker.contains('samsung')) {
    return 'On Samsung phones also check that this app is not in "Sleeping '
        'apps" or "Deep sleeping apps" (Settings, Battery, Background usage '
        'limits).';
  }
  if (RegExp('huawei|honor').hasMatch(maker)) {
    return 'On Huawei and Honor phones set App launch for this app to '
        '"Manage manually" with all three switches on.';
  }
  return null;
}

List<Problem> problemsFrom(NotifyState s, bool battery, String maker,
        {String mode = ''}) =>
    [
      if (!s.allowed)
        Problem(
            'notifications off',
            'Notifications are switched off for this app',
            'Nothing can be shown until they are allowed.',
            'Allow', () async {
          await askNotificationPermission();
          // Android stops asking after two refusals: open Settings then.
          if (!(await notifyState()).allowed) await openAppInfo();
        }),
      if (!s.exact)
        Problem(
            'exact alarms off',
            'Exact reminders are not allowed',
            'Without "Alarms and reminders" a class reminder can come many '
                'minutes late.',
            'Allow',
            askExactAlarms),
      // "Optimized" (Android's default, and all that "Allow background
      // usage" gives on Android 15+) still lets the exact class reminders
      // and the background check run; only "Restricted" stops them.
      if (!battery && mode != 'optimized')
        Problem(
            'battery restricted',
            'The phone stops this app in the background',
            'Reminders and Moodle alerts can be dropped. Turn on "Allow '
                'background usage" for Crony (App battery usage).'
                '${playStore ? ' In the page that opens, tap "App battery '
                    'usage" and switch on "Allow background usage".' : ''}'
                '${makerTip(maker) == null ? '' : ' ${makerTip(maker)}'}',
            playStore ? 'Open settings' : 'Allow',
            askBatteryUnrestricted),
    ];

Future<(NotifyState, List<Problem>)> checkHealth() async {
  final s = await notifyState();
  var battery = true;
  var maker = '';
  var mode = '';
  try {
    battery = await batteryUnrestricted();
    maker = await phoneMaker();
    mode = await batteryMode();
  } catch (_) {}
  return (s, problemsFrom(s, battery, maker, mode: mode));
}

/// Shows what is wrong, each with a button that fixes it.
class HealthCard extends StatelessWidget {
  const HealthCard(
      {super.key,
      required this.state,
      required this.problems,
      required this.onFixed});
  final NotifyState state;
  final List<Problem> problems;
  final VoidCallback onFixed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (problems.isEmpty) {
      return Strip(
        inset: false,
        icon: Icons.check_circle_outline,
        color: Tone.of(context).good,
        text: 'Reminders can reach you. ${state.next} are set.',
      );
    }
    final bad = Tone.of(context).bad;
    return TiltCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: bad.withOpacity(0.10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            IconTile(Icons.notifications_off_outlined, color: bad),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Reminders may not arrive on this phone',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: t.colorScheme.onSurface)),
            ),
          ]),
        ),
        for (final (i, p) in problems.indexed) ...[
          if (i > 0)
            Divider(
                height: 1,
                color: t.colorScheme.outlineVariant.withOpacity(0.5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(p.how,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () async {
                    try {
                      await p.fix();
                    } catch (_) {}
                    onFixed();
                  },
                  child: Text(p.button)),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// First screen after installing: asks for what reminders need, one tap
/// each, before anything else. Shown once.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  NotifyState? state;
  bool battery = true;
  String maker = '';
  bool busy = false;
  final asked = <String>{};

  /// 0 the welcome, 1 the permissions. Sign-in follows as the third step.
  int step = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  void _toPermissions() {
    setState(() => step = 1);
    _askNext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Back from a system screen: see what was granted, ask the next one.
    if (s == AppLifecycleState.resumed && step == 1) {
      _check().then((_) => _askNext());
    }
  }

  Future<void> _check() async {
    try {
      final s = await notifyState();
      final b = await batteryUnrestricted() ||
          await batteryMode() == 'optimized';
      final m = await phoneMaker();
      if (mounted) {
        setState(() {
          state = s;
          battery = b;
          maker = m;
        });
      }
    } catch (_) {}
  }

  /// Asks for the first thing still missing that has not been asked yet,
  /// so the three questions come one after another on their own.
  Future<void> _askNext() async {
    final s = state;
    if (s == null || busy) return;
    busy = true;
    try {
      if (!s.allowed && asked.add('notify')) {
        await askNotificationPermission();
      } else if (!s.exact && asked.add('exact')) {
        await askExactAlarms();
      } else if (!battery && asked.add('battery')) {
        await askBatteryUnrestricted();
      }
    } catch (_) {}
    busy = false;
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final s = state;
    final allDone = s != null && s.allowed && s.exact && battery;
    const h2 = TextStyle(
        fontFamily: 'Schoolbell',
        fontSize: 37,
        height: 1.05,
        fontWeight: FontWeight.w400,
        letterSpacing: 0);
    final p = TextStyle(
        fontSize: 16, height: 1.45, color: t.colorScheme.onSurfaceVariant);

    Widget row(
            bool ok, String title, String why, Future<void> Function() ask) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(why,
                        style: TextStyle(
                            fontSize: 13,
                            color: t.colorScheme.onSurfaceVariant)),
                  ]),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: ok
                  ? Row(
                      key: const ValueKey('ok'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          Icon(Icons.check, size: 16, color: tone.good),
                          const SizedBox(width: 4),
                          Text('Allowed',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tone.good)),
                        ])
                  : FilledButton.tonal(
                      key: const ValueKey('ask'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      onPressed: () async {
                        try {
                          await ask();
                        } catch (_) {}
                        await _check();
                      },
                      child: const Text('Allow')),
            ),
          ]),
        );

    final pages = [
      Column(
          key: const ValueKey(0),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Crony(mood: Mood.idle, size: 116, play: true),
            const SizedBox(height: 20),
            const Text('Your attendance, worked out.', style: h2),
            const SizedBox(height: 14),
            Text(
                "I'm Crony. I count every class, tell you what you can skip, "
                'and remind you before anything is due.',
                style: p),
          ]),
      Column(
          key: const ValueKey(1),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Crony(
                mood: allDone ? Mood.happy : Mood.idle, size: 72, play: true),
            const SizedBox(height: 18),
            const Text('So reminders arrive on time.', style: h2),
            const SizedBox(height: 12),
            Text('Android needs three permissions for exact reminders.',
                style: p),
            const SizedBox(height: 18),
            if (s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LiquidBar(height: 4),
              )
            else
              TiltCard(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  row(s.allowed, 'Notifications',
                      'Class and deadline reminders', () async {
                    await askNotificationPermission();
                    if (!(await notifyState()).allowed) await openAppInfo();
                  }),
                  Divider(
                      height: 1,
                      color: t.colorScheme.outlineVariant.withOpacity(0.5)),
                  row(
                      s.exact,
                      'Alarms and reminders',
                      'So a reminder comes at the exact minute',
                      askExactAlarms),
                  Divider(
                      height: 1,
                      color: t.colorScheme.outlineVariant.withOpacity(0.5)),
                  row(
                      battery,
                      'Run in the background',
                      'So the phone does not drop reminders',
                      askBatteryUnrestricted),
                ]),
              ),
            if (makerTip(maker) != null) ...[
              const SizedBox(height: 10),
              Text(makerTip(maker)!, style: t.textTheme.bodySmall),
            ],
          ]),
    ];

    Widget dot(bool on) => AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: const Cubic(0.23, 1, 0.32, 1),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
              color: on ? t.colorScheme.primary : t.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(3)),
        );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: step == 0 ? _toPermissions : widget.onDone,
                child: Text('Skip',
                    style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * 0.62),
                  child: AnimatedSwitcher(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 380),
                    switchInCurve: const Cubic(0.23, 1, 0.32, 1),
                    transitionBuilder: (w, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0.08, 0),
                                    end: Offset.zero)
                                .animate(a),
                            child: w)),
                    layoutBuilder: (cur, prev) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...prev, if (cur != null) cur]),
                    child: pages[step],
                  ),
                ),
              ),
            ),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [dot(step == 0), dot(step == 1), dot(false)]),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
              onPressed: step == 0
                  ? _toPermissions
                  : s == null
                      ? null
                      : widget.onDone,
              child: Text(step == 0
                  ? 'Continue'
                  : allDone
                      ? 'Continue to sign in'
                      : 'Continue anyway'),
            ),
            if (step == 1 && !allDone && s != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'You can allow these later in Settings, but reminders may '
                    'not arrive until you do.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ),
          ]),
        ),
      ),
    );
  }
}
