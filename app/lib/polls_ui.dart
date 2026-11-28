// Polls on the home screen: vote with one tap, then see how everyone voted.

import 'package:flutter/material.dart';

import 'backend.dart';
import 'crony_ui.dart';
import 'site.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'motion.dart';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Closes today, 18:00" / "Closed".
String pollWhen(Poll p, DateTime now) {
  if (!p.open) return 'Closed';
  final days = DateTime(p.closes.year, p.closes.month, p.closes.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => fmtDate(p.closes),
  };
  return 'Closes $day, ${_hm(p.closes)}';
}

/// Goes up when a poll was made or the list fetched again, so the home
/// screen shows it at once.
final pollsVersion = ValueNotifier<int>(0);

/// Open polls, and closed ones from the last two days, newest first.
List<Poll> pollsToShow(List<Poll> all, DateTime now) => [
      for (final p in all)
        if (p.open || now.difference(p.closes) < const Duration(days: 2)) p
    ];

class PollsCard extends StatefulWidget {
  const PollsCard({super.key, required this.store});
  final Store store;

  @override
  State<PollsCard> createState() => _PollsCardState();
}

class _PollsCardState extends State<PollsCard> {
  late List<Poll> polls = decodePolls(widget.store.prefs.getString('polls'));
  int? busy;

  void _reread() {
    if (mounted) {
      setState(
          () => polls = decodePolls(widget.store.prefs.getString('polls')));
    }
  }

  @override
  void initState() {
    super.initState();
    pollsVersion.addListener(_reread);
    pullPolls(widget.store.prefs).then((p) {
      if (mounted) setState(() => polls = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    pollsVersion.removeListener(_reread);
    super.dispose();
  }

  @override
  void didUpdateWidget(PollsCard old) {
    super.didUpdateWidget(old);
    polls = decodePolls(widget.store.prefs.getString('polls'));
  }

  Future<void> pick(Poll p, int i) async {
    setState(() => busy = p.id);
    try {
      final fresh = await vote(widget.store.prefs, p.id, i);
      if (mounted) setState(() => polls = fresh);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final shown = pollsToShow(polls, now);
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Polls'),
      for (final p in shown)
        PollTile(
            poll: p,
            busy: busy == p.id,
            onPick: p.open && busy == null ? (i) => pick(p, i) : null),
    ]);
  }
}

/// One poll: answers to tap, or the results once voted or closed.
class PollTile extends StatelessWidget {
  const PollTile(
      {super.key, required this.poll, this.onPick, this.busy = false});
  final Poll poll;
  final void Function(int)? onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = poll;
    final results = p.mine != null || !p.open || onPick == null;
    final muted = t.colorScheme.onSurfaceVariant;
    return TiltCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              [
                if (p.from.isNotEmpty) 'From your ${p.from}',
                pollWhen(p, DateTime.now()),
              ].join(' · '),
              style: t.textTheme.labelMedium?.copyWith(color: muted)),
          const SizedBox(height: 4),
          Text(p.question,
              style: t.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (final (i, o) in p.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: results
                  ? _Bar(
                      label: o,
                      votes: i < p.votes.length ? p.votes[i] : 0,
                      total: p.total,
                      mine: p.mine == i,
                      onTap: p.open && onPick != null ? () => onPick!(i) : null)
                  : OutlinedButton(
                      onPressed: busy ? null : () => onPick?.call(i),
                      style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft),
                      child: Text(o),
                    ),
            ),
          Text(
              '${p.total} ${p.total == 1 ? 'vote' : 'votes'}'
              '${p.open && p.mine != null ? ' · tap another answer to change your vote' : ''}',
              style: t.textTheme.bodySmall?.copyWith(color: muted)),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.label,
      required this.votes,
      required this.total,
      required this.mine,
      this.onTap});
  final String label;
  final int votes;
  final int total;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final share = total == 0 ? 0.0 : votes / total;
    final fill = mine
        ? t.colorScheme.primaryContainer
        : t.colorScheme.surfaceContainerHighest;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  mine ? t.colorScheme.primary : t.colorScheme.outlineVariant,
              width: mine ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(alignment: Alignment.centerLeft, children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: share,
              child: ColoredBox(color: fill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              if (mine) ...[
                Icon(Icons.check_circle,
                    size: 18, color: t.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: mine ? FontWeight.w600 : null))),
              Text('${(share * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Makes a poll (role holders): question, 2 to 6 answers, how long it runs.
Future<bool> askPoll(BuildContext context, Store store, MyRole r) async {
  final q = TextEditingController();
  final answers = [
    TextEditingController(text: 'Yes'),
    TextEditingController(text: 'No')
  ];
  var hours = 24;
  const lengths = {3: '3 hours', 24: '1 day', 72: '3 days', 168: '1 week'};
  final ok = await showModalBottomSheet<bool>(
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
                SheetHead('Ask a poll',
                    subtitle:
                        'Goes to ${r.audience} as "${r.label} poll: ..."'),
                TextField(
                  controller: q,
                  autofocus: true,
                  maxLength: 140,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Question',
                      hintText: 'Shift Friday\'s class to Saturday?'),
                ),
                const FieldLabel('Answers'),
                for (final (i, a) in answers.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: a,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Answer ${i + 1}',
                        counterText: '',
                        suffixIcon: answers.length > 2
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => set(() => answers.removeAt(i)))
                            : null,
                      ),
                    ),
                  ),
                if (answers.length < 6)
                  TextButton.icon(
                    onPressed: () =>
                        set(() => answers.add(TextEditingController())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Another answer'),
                  ),
                const SizedBox(height: 8),
                const FieldLabel('Open for'),
                Segmented(
                    options: lengths.values.toList(),
                    selected: lengths.keys.toList().indexOf(hours),
                    onChanged: (i) =>
                        set(() => hours = lengths.keys.toList()[i])),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      final opts = [
                        for (final a in answers)
                          if (a.text.trim().isNotEmpty) a.text.trim()
                      ];
                      if (q.text.trim().isEmpty || opts.length < 2) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Write the question and at least two answers')));
                        return;
                      }
                      if (opts.toSet().length != opts.length) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Two answers are the same')));
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Send poll'),
                  ),
                ),
              ]),
        ),
      ),
    ),
  );
  if (ok != true) return false;
  await createPoll(
      store.prefs,
      q.text.trim(),
      [
        for (final a in answers)
          if (a.text.trim().isNotEmpty) a.text.trim()
      ],
      hours);
  try {
    await pullPolls(store.prefs);
    pollsVersion.value++;
  } catch (_) {}
  return true;
}

/// Small note for poll results in the role screen.
String pollSummary(Poll p) => p.total == 0
    ? 'No votes yet'
    : [
        for (final (i, o) in p.options.indexed)
          '$o ${i < p.votes.length ? p.votes[i] : 0}'
      ].join(' · ');
