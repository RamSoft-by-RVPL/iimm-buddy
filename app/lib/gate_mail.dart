// The mail the institute wants before a student goes out of the main gate:
// written in the parent's words (the parent sends it) or in the student's
// own. Pure text building, so it can be tested.

import 'dart:convert';

import 'absence.dart' show Email;
import 'site.dart';

/// Who gets the leave mail.
const gateMailTo = [
  'ugoffice@iimmumbai.ac.in',
  'newgatesecurity@iimmumbai.ac.in',
  'sandt@iimmumbai.ac.in',
  'pgphostels@iimmumbai.ac.in',
];

/// Where the parent opens the mail from a shared link. The mail travels in
/// the part after "#", which the browser never sends to the server.
const gateMailPage = 'https://buddy.iimmumbai.in/leave';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];
const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];

/// What the student fills in once and the app keeps.
class GateDetails {
  GateDetails(
      {required this.name,
      required this.roll,
      this.programme = '',
      this.parent = '',
      this.phone = '',
      this.email = ''});
  final String name;
  final String roll;

  /// "BS Programme".
  final String programme;
  final String parent;
  final String phone;

  /// The student's own address, copied in when the parent sends it.
  final String email;
}

/// "4:00 PM".
String clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Thursday, 19 November 2026".
String longDate(DateTime d) =>
    '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "MANAS V BHARADIA" → "Manas V Bharadia". Mixed case is left alone.
String titleName(String n) => n != n.toUpperCase()
    ? n.trim()
    : n
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');

/// The leave mail. [fromParent] writes it in the parent's words.
Email gateMail(GateDetails who, DateTime out, DateTime back,
    {String reason = '', bool fromParent = true}) {
  final name = who.name.trim().isEmpty ? 'my ward' : who.name.trim();
  final of = [
    if (who.programme.isNotEmpty) 'a student of the ${who.programme}',
    if (who.roll.isNotEmpty) 'Roll No. ${who.roll}',
  ].join(', ');
  final leave = 'on ${longDate(out)}, at ${clock(out)}';
  final ret = _sameDay(out, back)
      ? 'on the same day by ${clock(back)}'
      : 'on ${longDate(back)}, by ${clock(back)}';
  final why = reason.trim().replaceAll(RegExp(r'[.\s]+$'), '');
  final whyLine = why.isEmpty ? '' : ' The reason for leaving is $why.';
  final parent = who.parent.trim();
  final phone = who.phone.trim();

  final body = fromParent
      ? [
          'Dear Sir/Madam,',
          '',
          'I am the parent of $name${of.isEmpty ? '' : ', $of,'} at IIM Mumbai.',
          '',
          'I would like to request your kind permission for my ward to leave '
              'the hostel premises $leave, and return to the hostel $ret.'
              '$whyLine',
          '',
          'I kindly request you to grant permission for the above-mentioned '
              'duration. I assure you that my ward will return to the hostel '
              'within the stipulated time.',
          '',
          'Thank you for your kind consideration and cooperation.',
          '',
          'Yours sincerely,',
          if (parent.isNotEmpty) parent,
          'Parent of $name',
          if (who.roll.isNotEmpty) 'Roll No.: ${who.roll}',
          if (phone.isNotEmpty) 'Contact No.: $phone',
        ]
      : [
          'Dear Sir/Madam,',
          '',
          'I, $name${of.isEmpty ? '' : ', $of'}, request your kind permission '
              'to leave the hostel premises $leave. I will return to the '
              'hostel $ret.$whyLine',
          '',
          if (parent.isNotEmpty) ...[
            'My parent, $parent${phone.isEmpty ? '' : ' (Contact No.: $phone)'}, '
                'is aware of this.',
            '',
          ],
          'I assure you that I will return to the hostel within the '
              'stipulated time.',
          '',
          'Thank you for your kind consideration.',
          '',
          'Yours sincerely,',
          name,
          if (who.roll.isNotEmpty) 'Roll No.: ${who.roll}',
        ];

  final day = '${out.day} ${_months[out.month - 1]}';
  return Email(
      'Permission to leave campus: $name'
      '${who.roll.isEmpty ? '' : ' (${who.roll})'}, $day',
      body.join('\n'));
}

/// The link a parent taps: opens a page with the mail and a button that
/// puts it in their email app, addressed and ready to send.
String gateMailLink(Email mail, {String cc = ''}) {
  final data = jsonEncode({
    't': gateMailTo.join(','),
    if (cc.isNotEmpty) 'c': cc,
    's': mail.subject,
    'b': mail.body,
  });
  final code = base64Url.encode(utf8.encode(data)).replaceAll('=', '');
  return '$gateMailPage#$code';
}

/// The message the student sends their parent on WhatsApp.
String gateMailMessage(Email mail, DateTime out, DateTime back,
    {String cc = ''}) {
  final ret = _sameDay(out, back)
      ? 'back the same day by ${clock(back)}'
      : 'back ${longDate(back)}, by ${clock(back)}';
  return 'I need to go out of campus. The college needs a mail from you '
      'first. Please tap this link, then press send in your email app '
      '(it is already written and addressed):\n\n'
      '${gateMailLink(mail, cc: cc)}\n\n'
      'Leaving ${longDate(out)}, at ${clock(out)}; $ret.';
}

/// What the student fills in once, read from the app's saved data.
extension GateStore on Store {
  String get gateParent => prefs.getString('gate_parent') ?? '';
  set gateParent(String v) => prefs.setString('gate_parent', v.trim());
  String get gatePhone => prefs.getString('gate_phone') ?? '';
  set gatePhone(String v) => prefs.setString('gate_phone', v.trim());
  String get gateName => prefs.getString('gate_name') ?? '';
  set gateName(String v) => prefs.setString('gate_name', v.trim());

  /// The programme and the student's email from the attendance site.
  (String, String) get gateFromSite {
    try {
      final data =
          (jsonDecode(prefs.getString('summary') ?? '') as Map)['data'] as Map;
      final student = (data['student'] as Map?) ?? {};
      final m = ((data['modules'] as List?) ?? []).firstOrNull as Map?;
      final code = '${m?['programme_code'] ?? ''}'.trim();
      return (
        code.isEmpty ? '' : '$code Programme',
        '${student['email'] ?? ''}'.trim().toLowerCase()
      );
    } catch (_) {
      return ('', '');
    }
  }
}
