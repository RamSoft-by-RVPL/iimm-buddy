import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crony_ui.dart';
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

  Widget _row(BuildContext context, InboxItem i, bool isNew) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => Navigator.pop(context, i.open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(_icon(i.channel)),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(i.title,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: isNew ? FontWeight.w600 : FontWeight.w500,
                          color: t.colorScheme.onSurface)),
                ),
                const SizedBox(width: 10),
                Text(_time(i.at),
                    style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: muted)),
                if (isNew) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Dot(t.colorScheme.primary),
                  ),
                ],
              ]),
              if (i.body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(i.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13.5, height: 1.4, color: muted)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = items;
    final now = DateTime.now();
    final unread = list?.where((i) => i.at.isAfter(seenBefore)).length ?? 0;

    Widget body;
    if (list == null) {
      body = const Center(child: LoadingNote('Opening notifications...'));
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
      final days = <String, List<InboxItem>>{};
      for (final i in list) {
        days.putIfAbsent(_day(i.at, now), () => []).add(i);
      }
      for (final (k, (d, group))
          in days.entries.map((e) => (e.key, e.value)).indexed) {
        children.add(Rise(
          index: k,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(d),
            GroupCard(children: [
              for (final i in group) _row(context, i, i.at.isAfter(seenBefore)),
            ]),
          ]),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: children);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 0,
        title: BigTitle('Notifications',
            subtitle: list == null || list.isEmpty
                ? null
                : unread == 0
                    ? 'All caught up'
                    : '$unread new since you last looked'),
        actions: [
          if (list != null && list.isNotEmpty)
            TextButton(onPressed: _clear, child: const Text('Clear all')),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
