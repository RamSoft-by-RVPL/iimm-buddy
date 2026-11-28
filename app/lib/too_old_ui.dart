// Shown instead of the whole app when the admin has said this version may
// no longer be used (see tooOld). Only updating gets past it.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';
import 'mascot.dart';
import 'update.dart';

class TooOldScreen extends StatefulWidget {
  const TooOldScreen({super.key, required this.prefs, required this.onChanged});
  final SharedPreferences prefs;

  /// Called after each check, in case the admin let this version in again.
  final VoidCallback onChanged;

  @override
  State<TooOldScreen> createState() => _TooOldScreenState();
}

class _TooOldScreenState extends State<TooOldScreen>
    with WidgetsBindingObserver {
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    logEvent(widget.prefs, 'too_old',
        '$appVersion < ${widget.prefs.getString('min_version')}');
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    await checkUpdate(widget.prefs);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _update() async {
    setState(() => busy = true);
    final u = await checkUpdate(widget.prefs);
    if (!mounted) return;
    setState(() => busy = false);
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not get the new version. Check your '
              'internet and try again.')));
      return;
    }
    await runUpdate(context, widget.prefs, u);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = TextStyle(
        fontSize: 16, height: 1.45, color: t.colorScheme.onSurfaceVariant);
    final u = knownUpdate(widget.prefs);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const Crony(mood: Mood.worried, size: 96, play: true),
                const SizedBox(height: 20),
                const Text('Time to update.',
                    style: TextStyle(
                        fontFamily: 'Schoolbell',
                        fontSize: 37,
                        height: 1.05,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0)),
                const SizedBox(height: 14),
                Text(
                    'Version $appVersion of Crony can no longer be used. '
                    '${playStore ? 'Update Crony from the Play Store' : 'Update it'}'
                    ' to keep getting your attendance, timetable and '
                    'reminders.',
                    style: p),
                const Spacer(flex: 2),
                if (!playStore)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : _update,
                      child: Text(busy
                          ? 'Looking for the new version...'
                          : u == null
                              ? 'Update'
                              : 'Update to ${u.version}'),
                    ),
                  ),
              ]),
        ),
      ),
    );
  }
}
