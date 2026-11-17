import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inbox.dart';
import 'theme.dart';
import 'ui_common.dart';

/// The bell in the top bar, with the number of new notifications.
class InboxBell extends StatelessWidget {
  const InboxBell({super.key, required this.unread, required this.onPressed});
  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: unread == 0 ? 'Notifications' : '$unread new notifications',
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(unread > 0
              ? Icons.notifications
              : Icons.notifications_none_outlined),
        ),
      );
}

/// Every notification of the last few weeks. Pops with the place a tapped
/// item points to ("timetable", "course:12", ...), or null.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<InboxItem>? items;
  DateTime seenBefore = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The background check writes from another process: read it fresh.
    await widget.prefs.reload();
    final now = DateTime.now();
    final list = inboxItems(widget.prefs, now);
    final before = inboxSeenAt(widget.prefs);
    await inboxMarkSeen(widget.prefs, now);
    if (mounted) {
      setState(() {
        items = list;
        seenBefore = before;
      });
    }
  }

  Future<void> _clear() async {
    await inboxClear(widget.prefs, DateTime.now());
    if (!mounted) return;
    setState(() => items = []);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cleared. New notifications will show here.')));
  }

  static IconData _icon(String channel) => switch (channel) {
        'classes' => Icons.schedule,
        'moodle' => Icons.menu_book_outlined,
        'attendance' => Icons.fact_check_outlined,
        _ => Icons.campaign_outlined,
      };

  static String _day(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(now.year, now.month, now.day);
    final n = b.difference(a).inDays;
    if (n == 0) return 'Today';
    if (n == 1) return 'Yesterday';
    return fmtDate(d);
  }

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = Tone.of(context);
    final list = items;
    final now = DateTime.now();

    Widget body;
    if (list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      body = ListView(children: const [
        SizedBox(height: 80),
        EmptyNote(
            icon: Icons.notifications_none_outlined,
            title: 'No notifications yet',
            text: 'Class reminders, new Moodle files, deadlines and '
                'attendance alerts will be listed here.'),
      ]);
    } else {
      final children = <Widget>[];
      String? day;
      for (final i in list) {
        final d = _day(i.at, now);
        if (d != day) {
          day = d;
          children.add(SectionTitle(d));
        }
        final isNew = i.at.isAfter(seenBefore);
        children.add(Card(
          child: InkWell(
            onTap: () => Navigator.pop(context, i.open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: t.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(_icon(i.channel),
                      size: 20, color: t.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(i.title,
                                style: t.textTheme.titleSmall?.copyWith(
                                    fontWeight: isNew
                                        ? FontWeight.w700
                                        : FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text(_time(i.at),
                              style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant)),
                          if (isNew) ...[
                            const SizedBox(width: 6),
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: tone.bad, shape: BoxShape.circle)),
                          ],
                        ]),
                        if (i.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(i.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodyMedium?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant)),
                        ],
                      ]),
                ),
              ]),
            ),
          ),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        child: Text('Kept on this phone for $inboxDays days.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ));
      body = ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
          children: children);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (list != null && list.isNotEmpty)
            TextButton(onPressed: _clear, child: const Text('Clear all')),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
