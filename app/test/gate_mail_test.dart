import 'dart:convert';

import 'package:attendance_planner/gate_mail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final who = GateDetails(
      name: 'Asha K Rao',
      roll: '260001',
      programme: 'BS Programme',
      parent: 'Kiran Rao',
      phone: '9800000000',
      email: 'asha@example.com');
  final out = DateTime(2026, 11, 19, 16);
  final back = DateTime(2026, 11, 19, 23);

  test('the parent\'s mail, same day', () {
    final m = gateMail(who, out, back);
    expect(m.subject,
        'Permission to leave campus: Asha K Rao (260001), 19 November');
    expect(
        m.body,
        contains(
            'I am the parent of Asha K Rao, a student of the BS Programme, Roll No. 260001, at IIM Mumbai.'));
    expect(m.body, contains('on Thursday, 19 November 2026, at 4:00 PM'));
    expect(m.body, contains('on the same day by 11:00 PM'));
    expect(
        m.body,
        endsWith(
            'Kiran Rao\nParent of Asha K Rao\nRoll No.: 260001\nContact No.: 9800000000'));
    expect(m.body, isNot(contains('reason')));
  });

  test('another day, with a reason, in the student\'s words', () {
    final m = gateMail(who, out, DateTime(2026, 11, 22, 18),
        reason: 'a family function.', fromParent: false);
    expect(
        m.body,
        contains(
            'I, Asha K Rao, a student of the BS Programme, Roll No. 260001, request'));
    expect(m.body, contains('on Sunday, 22 November 2026, by 6:00 PM'));
    expect(m.body, contains('The reason for leaving is a family function.'));
    expect(m.body,
        contains('My parent, Kiran Rao (Contact No.: 9800000000), is aware'));
    expect(m.body, endsWith('Asha K Rao\nRoll No.: 260001'));
  });

  test('the link carries the mail after "#"', () {
    final m = gateMail(who, out, back);
    final link = gateMailLink(m, cc: who.email);
    expect(link, startsWith('https://buddy.iimmumbai.in/leave#'));
    var code = link.split('#').last;
    expect(code, isNot(contains('=')));
    while (code.length % 4 != 0) {
      code += '=';
    }
    final j = jsonDecode(utf8.decode(base64Url.decode(code))) as Map;
    expect(j['t'], gateMailTo.join(','));
    expect(j['c'], 'asha@example.com');
    expect(j['s'], m.subject);
    expect(j['b'], m.body);
    expect(gateMailMessage(m, out, back), contains(link.split('#').first));
  });

  test('times and names', () {
    expect(clock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
    expect(clock(DateTime(2026, 1, 1, 12)), '12:00 PM');
    expect(titleName('MANAS V BHARADIA'), 'Manas V Bharadia');
    expect(titleName('Asha  Rao'), 'Asha  Rao');
  });
}
