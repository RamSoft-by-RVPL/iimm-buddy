// The email a student sends when a class is wrongly marked absent or was
// never marked. Pure text building, so it can be tested.

import 'site.dart';

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

class Email {
  Email(this.subject, this.body);
  final String subject;
  final String body;
}

/// True for a finished class the student may want corrected.
bool canDispute(ClassSlot s) =>
    !s.upcoming &&
    !s.fromSheet &&
    !s.cancelled &&
    (s.status == 'Absent' || s.status == 'Not Marked');

Email absenceEmail(Snapshot snap, ClassSlot s) {
  final faculty = snap.courseOf(s)?.faculty ?? '';
  final date = '${_days[s.date.weekday - 1]}, ${s.date.day} '
      '${_months[s.date.month - 1]} ${s.date.year}';
  final problem = s.status == 'Absent'
      ? 'my attendance is marked as absent'
      : 'my attendance has not been marked yet';
  return Email(
    'Attendance correction: ${s.course}, ${s.date.day} '
    '${_months[s.date.month - 1]}',
    [
      faculty.isEmpty || faculty.contains(',')
          ? 'Respected Sir/Madam,'
          : 'Respected $faculty,',
      '',
      'I was present in the class below, but $problem. '
          'I request you to please correct it.',
      '',
      'Course: ${s.course}',
      'Date: $date',
      'Time: ${s.start} to ${s.end}',
      if (s.room.isNotEmpty) 'Room: ${s.room}',
      '',
      'Name: ${snap.studentName}',
      'Roll number: ${snap.roll}',
      '',
      'Thank you.',
      snap.studentName,
    ].join('\n'),
  );
}
