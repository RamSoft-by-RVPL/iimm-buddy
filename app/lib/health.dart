// Finds out why reminders might not arrive on this phone and says how to
// fix it. Most missed reminders come from three phone settings.

import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';

import 'notify.dart';
import 'theme.dart';

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

List<Problem> problemsFrom(NotifyState s, bool battery, String maker) => [
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
      if (!battery)
        Problem(
            'battery restricted',
            'The phone limits this app in the background',
            'Reminders and Moodle alerts can be dropped. Allow the app to '
                'run in the background.'
                '${makerTip(maker) == null ? '' : ' ${makerTip(maker)}'}',
            'Allow',
            askBatteryUnrestricted),
    ];

Future<(NotifyState, List<Problem>)> checkHealth() async {
  final s = await notifyState();
  var battery = true;
  var maker = '';
  try {
    battery = await batteryUnrestricted();
    maker = await phoneMaker();
  } catch (_) {}
  return (s, problemsFrom(s, battery, maker));
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Tone.of(context).bad.withOpacity(0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reminders may not arrive on this phone',
              style: t.textTheme.titleSmall),
          for (final p in problems) ...[
            const SizedBox(height: 10),
            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(p.how, style: t.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () async {
                    try {
                      await p.fix();
                    } catch (_) {}
                    onFixed();
                  },
                  child: Text(p.button)),
            ),
          ],
        ]),
      ),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check().then((_) => _askNext());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Back from a system screen: see what was granted, ask the next one.
    if (s == AppLifecycleState.resumed) _check().then((_) => _askNext());
  }

  Future<void> _check() async {
    try {
      final s = await notifyState();
      final b = await batteryUnrestricted();
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
    final s = state;
    final allDone = s != null && s.allowed && s.exact && battery;
    Widget row(
            bool ok, String title, String why, Future<void> Function() ask) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
              color: ok ? Tone.of(context).good : t.colorScheme.outline),
          title: Text(title),
          subtitle: Text(why),
          trailing: ok
              ? null
              : FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await ask();
                    } catch (_) {}
                    await _check();
                  },
                  child: const Text('Allow')),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: t.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.notifications_active_outlined,
                color: t.colorScheme.onPrimaryContainer, size: 28),
          ),
          const SizedBox(height: 16),
          Text('Welcome to IIMM Buddy', style: t.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'The app reminds you before every class and before assignment '
              'deadlines. To do that reliably on this phone it needs three '
              'things from you.',
              style: t.textTheme.bodyLarge
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (s == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            row(s.allowed, 'Notifications',
                'To show class and deadline reminders.', () async {
              await askNotificationPermission();
              if (!(await notifyState()).allowed) await openAppInfo();
            }),
            row(
                s.exact,
                'Alarms and reminders',
                'So a reminder comes at the exact minute, not late.',
                askExactAlarms),
            row(
                battery,
                'Run in the background',
                'So the phone does not stop the app and drop reminders.',
                askBatteryUnrestricted),
            if (makerTip(maker) != null) ...[
              const SizedBox(height: 8),
              Text(makerTip(maker)!, style: t.textTheme.bodySmall),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: s == null ? null : widget.onDone,
            child: Text(allDone ? 'Continue to sign in' : 'Continue anyway'),
          ),
          if (!allDone && s != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'You can allow these later in Settings, but reminders may '
                  'not arrive until you do.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
