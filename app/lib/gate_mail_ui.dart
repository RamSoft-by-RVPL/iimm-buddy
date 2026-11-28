import 'package:cookie_bridge/cookie_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'crony_ui.dart';
import 'gate_mail.dart';
import 'site.dart';
import 'ui_common.dart';
import 'motion.dart';

/// "Going out of campus?" on the home screen.
class GateMailCard extends StatelessWidget {
  const GateMailCard({super.key, required this.store, this.snap});
  final Store store;
  final Snapshot? snap;

  @override
  Widget build(BuildContext context) => TiltCard(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
          leading: const IconTile(Icons.directions_walk),
          title: const Text('Going out of campus?',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('The leave mail for the gate, written for you '
              'or your parent to send'),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => GateMailScreen(store: store, snap: snap))),
        ),
      );
}

class GateMailScreen extends StatefulWidget {
  const GateMailScreen({super.key, required this.store, this.snap});
  final Store store;
  final Snapshot? snap;

  @override
  State<GateMailScreen> createState() => _GateMailScreenState();
}

class _GateMailScreenState extends State<GateMailScreen> {
  Store get store => widget.store;

  /// 0: the parent sends it, 1: the student does.
  var who = 0;
  var sameDay = true;
  late DateTime out;
  late DateTime back;
  final reason = TextEditingController();
  late final name = TextEditingController(
      text: store.gateName.isNotEmpty
          ? store.gateName
          : titleName(widget.snap?.studentName ?? ''));
  late final parent = TextEditingController(text: store.gateParent);
  late final phone = TextEditingController(text: store.gatePhone);
  late var editDetails = store.gateParent.isEmpty;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // The next half hour, and back by 11 PM.
    final next = DateTime(
        now.year, now.month, now.day, now.hour, now.minute < 30 ? 30 : 60);
    out = next;
    back = DateTime(out.year, out.month, out.day, 23);
    if (!back.isAfter(out)) {
      sameDay = false;
      back = back.add(const Duration(days: 1));
    }
  }

  GateDetails get details {
    final (programme, email) = store.gateFromSite;
    return GateDetails(
        name: name.text,
        roll: widget.snap?.roll ?? '',
        programme: programme,
        parent: parent.text,
        phone: phone.text,
        email: email);
  }

  void save() {
    store.gateName = name.text;
    store.gateParent = parent.text;
    store.gatePhone = phone.text;
  }

  String? get problem {
    if (name.text.trim().isEmpty) return 'Fill in your name';
    if (who == 0 && parent.text.trim().isEmpty) {
      return 'Fill in your parent\'s name';
    }
    if (!back.isAfter(out)) return 'The return time is before you leave';
    return null;
  }

  bool check() {
    final p = problem;
    if (p == null) return true;
    if (p.contains('name')) setState(() => editDetails = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p)));
    return false;
  }

  Future<void> sendToParent() async {
    if (!check()) return;
    save();
    final d = details;
    final mail = gateMail(d, out, back, reason: reason.text);
    await Share.share(gateMailMessage(mail, out, back, cc: d.email),
        subject: 'Leave mail for the college');
  }

  Future<void> openEmail() async {
    if (!check()) return;
    save();
    final mail =
        gateMail(details, out, back, reason: reason.text, fromParent: who == 0);
    try {
      await composeEmail(gateMailTo.join(','), mail.subject, mail.body);
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(
          text: 'To: ${gateMailTo.join(', ')}\n'
              'Subject: ${mail.subject}\n\n${mail.body}'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No email app found. The mail is copied instead.')));
    }
  }

  Future<DateTime?> pick(DateTime at, {required bool date}) async {
    final now = DateTime.now();
    if (date) {
      final d = await showDatePicker(
          context: context,
          initialDate: at,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: now.add(const Duration(days: 120)));
      return d == null
          ? null
          : DateTime(d.year, d.month, d.day, at.hour, at.minute);
    }
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(at));
    return t == null
        ? null
        : DateTime(at.year, at.month, at.day, t.hour, t.minute);
  }

  Widget whenRow(DateTime at, ValueChanged<DateTime> set, {bool day = true}) =>
      Row(children: [
        if (day) ...[
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(fmtDate(at)),
              onPressed: () async {
                final d = await pick(at, date: true);
                if (d != null) set(d);
              },
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text(clock(at)),
            onPressed: () async {
              final d = await pick(at, date: false);
              if (d != null) set(d);
            },
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mail =
        gateMail(details, out, back, reason: reason.text, fromParent: who == 0);
    final muted = t.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar:
          AppBar(bottom: const LiquidEdge(), title: const Text('Leave mail')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
              'Before you go out of the main gate, the college needs a mail '
              'to the UG office, security and hostel. Crony writes it; you '
              'check it and it goes from your own email app.',
              style: t.textTheme.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 16),
          const FieldLabel('Who sends it'),
          Segmented(
              options: const ['My parent', 'Me'],
              selected: who,
              onChanged: (i) => setState(() => who = i)),
          const SizedBox(height: 6),
          Text(
              who == 0
                  ? 'Written in your parent\'s words. You send them a link on '
                      'WhatsApp; they tap it and press send.'
                  : 'Written in your own words, sent from your email.',
              style: t.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 18),
          const FieldLabel('Leaving'),
          whenRow(out, (d) {
            setState(() {
              final gap = back.difference(out);
              out = d;
              back = sameDay
                  ? DateTime(d.year, d.month, d.day, back.hour, back.minute)
                  : d.add(gap);
            });
          }),
          const SizedBox(height: 16),
          const FieldLabel('Back'),
          Segmented(
              options: const ['Same day', 'Another day'],
              selected: sameDay ? 0 : 1,
              onChanged: (i) => setState(() {
                    sameDay = i == 0;
                    final day =
                        sameDay ? out : out.add(const Duration(days: 1));
                    back = DateTime(
                        day.year, day.month, day.day, back.hour, back.minute);
                  })),
          const SizedBox(height: 10),
          whenRow(back, (d) => setState(() => back = d), day: !sameDay),
          const SizedBox(height: 16),
          TextField(
            controller: reason,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'a family function, a doctor\'s appointment'),
          ),
          const SizedBox(height: 18),
          if (editDetails) ...[
            const FieldLabel('Details in the mail'),
            TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Your full name')),
            const SizedBox(height: 10),
            TextField(
                controller: parent,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Parent\'s name', hintText: 'As they sign it')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Parent\'s phone number')),
            const SizedBox(height: 4),
            Text('Kept on this phone for next time.',
                style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ] else
            GroupCard(children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                leading: const IconTile(Icons.person_outline),
                title: Text(name.text,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (parent.text.isNotEmpty) 'Parent: ${parent.text}',
                  if (phone.text.isNotEmpty) phone.text,
                ].join(' · ')),
                trailing: TextButton(
                    onPressed: () => setState(() => editDetails = true),
                    child: const Text('Change')),
              ),
            ]),
          const SizedBox(height: 18),
          const FieldLabel('The mail'),
          TiltCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To: ${gateMailTo.join(', ')}',
                        style: t.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: 6),
                    Text(mail.subject,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Divider(height: 18),
                    SelectableText(mail.body,
                        style: t.textTheme.bodyMedium?.copyWith(height: 1.35)),
                  ]),
            ),
          ),
          const SizedBox(height: 18),
          if (who == 0) ...[
            FilledButton.icon(
              onPressed: sendToParent,
              icon: const Icon(Icons.send),
              label: const Text('Send to my parent'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: openEmail,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Open in email on this phone'),
            ),
            const SizedBox(height: 6),
            Text('Use this if your parent\'s email is signed in on this phone.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ] else
            FilledButton.icon(
              onPressed: openEmail,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Open in email'),
            ),
        ],
      ),
    );
  }
}
