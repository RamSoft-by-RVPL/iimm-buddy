import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'crony_ui.dart';
import 'free.dart';
import 'glass.dart';
import 'motion.dart';
import 'site.dart';
import 'theme.dart';

String _why(Object e) => e is SocketException || e is HttpException
    ? 'No connection'
    : '$e'.replaceFirst('Exception: ', '');

/// A friend's initial on a small disc; lemon when both are free right now.
class _Initial extends StatelessWidget {
  const _Initial(this.name, {this.together = false});
  final String name;
  final bool together;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: together ? Brand.lemon : t.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: together ? Border.all(color: Brand.edge, width: 1.5) : null),
      child: Text(name.characters.first.toUpperCase(),
          style: Brand.hand(17,
              color: together ? Brand.onPink : t.colorScheme.onSurface,
              height: 1.1)),
    );
  }
}

/// On Today: how long the student is free (or in class), and which friends
/// are free at the same time. Opens the friends screen.
class FreeCard extends StatelessWidget {
  const FreeCard(
      {super.key, required this.store, required this.snap, this.onChanged});
  final Store store;
  final Snapshot snap;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final mine = busyOf(snap.sessions, now, days: 1);
    final state = freeAt(mine, now);
    final (head, sub) = freeWords(state, now);
    final friends = friendsOf(store.prefs);
    final line = t.colorScheme.outlineVariant.withOpacity(0.5);
    return TiltCard(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FriendsScreen(store: store, snap: snap)));
          onChanged?.call();
        },
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              IconTile(state.inClass
                  ? Icons.school_outlined
                  : Icons.local_cafe_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(head,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 13.5, color: muted)),
                    ]),
              ),
              if (friends.isEmpty)
                Text('Friends',
                    style: t.textTheme.labelLarge
                        ?.copyWith(color: t.colorScheme.primary)),
              Icon(Icons.chevron_right, size: 20, color: muted),
            ]),
          ),
          for (final f in friends.take(3)) ...[
            Divider(height: 1, thickness: 1, color: line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
              child: Builder(builder: (context) {
                final (words, together) = friendWords(f, mine, now);
                return Row(children: [
                  _Initial(f.name, together: together),
                  const SizedBox(width: 12),
                  Text(f.name,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(words,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 13.5, color: muted)),
                  ),
                ]);
              }),
            ),
          ],
          if (friends.length > 3) ...[
            Divider(height: 1, thickness: 1, color: line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
              child: Text('and ${friends.length - 3} more',
                  style: TextStyle(fontSize: 13.5, color: muted)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Share a code, add friends by theirs, and see who is free right now.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.store, required this.snap});
  final Store store;
  final Snapshot snap;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _input = TextEditingController();
  bool _busy = false;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    pullFriends(store.prefs).then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// One line at the bottom; a newer one replaces the one showing.
  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Runs one request with the buttons held, and says why if it fails.
  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _say(_why(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
        final f = await addFriend(store.prefs, _input.text);
        _input.clear();
        tick();
        if (mounted) _say('${f.name} added.');
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final code = myCode(store.prefs);
    final mine = busyOf(widget.snap.sessions, now, days: 1);
    final friends = friendsOf(store.prefs);
    final gone = friendCodes(store.prefs).length - friends.length;
    const ink = Brand.onPink;
    return Scaffold(
      appBar: screenBar('Friends', subtitle: 'Who is free when you are'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Sticker(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            radius: 24,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(code == null ? 'SHARE YOUR FREE TIME' : 'YOUR CODE',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: ink)),
              const SizedBox(height: 6),
              if (code != null)
                Semantics(
                  label: 'Your code, ${showCode(code).split('').join(' ')}',
                  excludeSemantics: true,
                  child: Text(showCode(code),
                      style: Brand.hand(44, color: ink, height: 1.1)),
                ),
              if (code == null)
                Text('Let friends see when you are free',
                    style: Brand.hand(28, color: ink, height: 1.15)),
              const SizedBox(height: 8),
              const Text(
                  'A friend who adds your code sees your first name and the '
                  'times you are in class. Not which class, not the room and '
                  'not your attendance.',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: Brand.onPinkMuted)),
              const SizedBox(height: 14),
              if (code == null)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await shareFree(store.prefs, widget.snap);
                            tick();
                          }),
                  child: const Text('Get my code'),
                )
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await Clipboard.setData(
                            ClipboardData(text: showCode(code)));
                        tick();
                        if (mounted) _say('Code copied.');
                      } catch (_) {
                        if (mounted) _say('Could not copy. Read it out.');
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Share.share(
                        'Add me on Crony to see when we are both free. '
                        'My code is ${showCode(code)}.'),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Send'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => stopSharing(store.prefs)),
                    style: TextButton.styleFrom(foregroundColor: ink),
                    child: const Text('Stop sharing'),
                  ),
                ]),
            ]),
          ),
          const SectionTitle('Add a friend'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(
                    labelText: 'Their code', hintText: 'ABCD-EF23'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
                onPressed: _busy ? null : _add, child: const Text('Add')),
          ]),
          SectionTitle(
              friends.isEmpty ? 'Friends' : 'Friends · ${friends.length}'),
          if (friends.isEmpty)
            const EmptyNote(
                icon: Icons.group_outlined,
                title: 'No friends added yet',
                text: 'Ask a friend to open Friends in Crony and send you '
                    'their code.')
          else
            GroupCard(children: [
              for (final f in friends)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  child: Builder(builder: (context) {
                    final (words, together) = friendWords(f, mine, now);
                    return Row(children: [
                      _Initial(f.name, together: together),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              Text(words,
                                  style:
                                      TextStyle(fontSize: 13.5, color: muted)),
                            ]),
                      ),
                      IconButton(
                        tooltip: 'Remove ${f.name}',
                        icon: Icon(Icons.close, size: 20, color: muted),
                        onPressed: () async {
                          await removeFriend(store.prefs, f.code);
                          if (mounted) setState(() {});
                        },
                      ),
                    ]);
                  }),
                ),
            ]),
          if (gone > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                  gone == 1
                      ? 'One friend has stopped sharing and is not shown.'
                      : '$gone friends have stopped sharing and are not shown.',
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
        ],
      ),
    );
  }
}
