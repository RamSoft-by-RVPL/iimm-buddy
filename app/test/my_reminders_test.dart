import 'package:attendance_planner/my_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 19, 12, 0);

  test('a one-time reminder goes off once, and not once passed', () {
    final r = MyReminder(1, 'Lab file', DateTime(2026, 11, 20, 8), 'Once');
    expect(r.nextTimes(now), [DateTime(2026, 11, 20, 8)]);
    expect(r.live(DateTime(2026, 11, 20, 9)), isFalse);
  });

  test('a daily reminder rolls on from today', () {
    final r = MyReminder(2, 'Gym', DateTime(2026, 11, 10, 18, 30), 'Every day');
    final t = r.nextTimes(now, most: 3);
    expect(t, [
      DateTime(2026, 11, 19, 18, 30),
      DateTime(2026, 11, 20, 18, 30),
      DateTime(2026, 11, 21, 18, 30),
    ]);
    // Earlier today: starts tomorrow.
    final m = MyReminder(3, 'Meds', DateTime(2026, 11, 10, 9), 'Every day');
    expect(m.nextTimes(now, most: 1).single, DateTime(2026, 11, 20, 9));
  });

  test('a weekly reminder keeps its weekday', () {
    final r =
        MyReminder(4, 'Call home', DateTime(2026, 11, 1, 20), 'Every week');
    final t = r.nextTimes(now, most: 2);
    expect(t.first, DateTime(2026, 11, 22, 20));
    expect(t.first.weekday, DateTime(2026, 11, 1).weekday);
    expect(t.last, DateTime(2026, 11, 29, 20));
  });

  test('notifications: own numbers, the text the student wrote', () {
    final list = [
      MyReminder(1, 'Lab file', DateTime(2026, 11, 20, 8), 'Once'),
      MyReminder(2, 'Gym', DateTime(2026, 11, 10, 18, 30), 'Every day'),
    ];
    final a = myReminderAlerts(list, now);
    expect(a.length, 1 + 14);
    expect(a.first.title, 'Lab file');
    expect(a.map((x) => x.id).toSet().length, a.length);
    expect(a.every((x) => x.id >= 2000000), isTrue);
  });

  test('saved and read back', () {
    final l = [MyReminder(9, 'X', DateTime(2026, 12, 1, 7, 5), 'Every week')];
    final back = decodeMyReminders(encodeMyReminders(l)).single;
    expect([back.id, back.title, back.at, back.repeat],
        [9, 'X', DateTime(2026, 12, 1, 7, 5), 'Every week']);
    expect(decodeMyReminders('bad'), isEmpty);
  });
}
