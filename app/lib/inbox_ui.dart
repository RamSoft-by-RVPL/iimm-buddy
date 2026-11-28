import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crony_ui.dart';
import 'inbox.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';
import 'glass.dart';

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

  static String _label(String channel) => switch (channel) {
        'classes' => 'Classes',
        'moodle' => 'Moodle',
        'attendance' => 'Attendance',
        _ => 'News',
      };

  static String _group(String channel) =>
      const ['classes', 'moodle', 'attendance'].contains(channel)
          ? channel
          : 'news';

  static Color _color(BuildContext context, String channel) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (_group(channel)) {
      'classes' => dark ? Brand.pink : const Color(0xFFB8355A),
      'moodle' => dark ? const Color(0xFF8DB8E8) : const Color(0xFF2F6FB0),
      'attendance' => Tone.of(context).bad,
      _ => dark ? const Color(0xFFB9D46A) : const Color(0xFF5E7A1F),
    };
  }

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

  String? filter;

  Widget _row(BuildContext context, InboxItem i, bool isNew) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final c = _color(context, i.channel);
    return InkWell(
      onTap: () => Navigator.pop(context, i.open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            IconTile(_icon(i.channel), color: c),
            if (isNew)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: t.brightness == Brightness.dark
                          ? Brand.lemon
                          : Brand.lemonDeep,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: t.cardTheme.color ?? t.colorScheme.surface,
                          width: 2)),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_label(i.channel).toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: c)),
                const Spacer(),
                Text(_time(i.at),
                    style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: muted)),
              ]),
              const SizedBox(height: 3),
              Text(i.title,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: isNew ? FontWeight.w600 : FontWeight.w500,
                      color: t.colorScheme.onSurface)),
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

  Widget _chips(BuildContext context, List<InboxItem> list) {
    final counts = <String, int>{};
    for (final i in list) {
      counts.update(_group(i.channel), (n) => n + 1, ifAbsent: () => 1);
    }
    final kinds = [
      for (final k in const ['classes', 'moodle', 'attendance', 'news'])
        if (counts.containsKey(k)) k
    ];
    if (kinds.length < 2) return const SizedBox(height: 4);
    Widget chip(String? k, String text, int n) {
      final on = filter == k;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          showCheckmark: false,
          selected: on,
          label: Text('$text  $n'),
          onSelected: (_) => setState(() => filter = k),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        children: [
          chip(null, 'All', list.length),
          for (final k in kinds) chip(k, _label(k), counts[k]!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = items;
    final now = DateTime.now();
    final unread = all?.where((i) => i.at.isAfter(seenBefore)).length ?? 0;
    final list = all == null || filter == null
        ? all
        : [
            for (final i in all)
              if (_group(i.channel) == filter) i
          ];

    Widget body;
    if (list == null) {
      body = const Center(child: LoadingNote('Opening notifications...'));
    } else if (all!.isEmpty) {
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
      final fresh = [
        for (final i in list)
          if (i.at.isAfter(seenBefore)) i
      ];
      final days = <String, List<InboxItem>>{};
      for (final i in list) {
        if (i.at.isAfter(seenBefore)) continue;
        days.putIfAbsent(_day(i.at, now), () => []).add(i);
      }
      var k = 0;
      if (fresh.isNotEmpty) {
        children.add(Rise(
          index: k++,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('New',
                trailing:
                    Pill('${fresh.length}', color: t.colorScheme.primary)),
            GroupCard(children: [
              for (final i in fresh) _row(context, i, true),
            ]),
          ]),
        ));
      }
      for (final e in days.entries) {
        children.add(Rise(
          index: k++,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(
                fresh.isEmpty || e.key != 'Today' ? e.key : 'Earlier today'),
            GroupCard(children: [
              for (final i in e.value) _row(context, i, false),
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
      body = Column(children: [
        _chips(context, all),
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: children),
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        bottom: const LiquidEdge(),
        toolbarHeight: 76,
        titleSpacing: 0,
        title: BigTitle('Notifications',
            subtitle: all == null || all.isEmpty
                ? null
                : unread == 0
                    ? 'All caught up'
                    : '$unread new since you last looked'),
        actions: [
          if (all != null && all.isNotEmpty)
            TextButton(onPressed: _clear, child: const Text('Clear all')),
          const SizedBox(width: 8),
        ],
      ),
      body: GlassRefresh(onRefresh: _load, child: body),
    );
  }
}
