import 'package:attendance_planner/backend.dart';
import 'package:attendance_planner/crony_ui.dart';
import 'package:attendance_planner/inbox.dart';
import 'package:attendance_planner/moodle.dart';
import 'package:attendance_planner/planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

int day(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

void main() {
  tearDown(() {
    plannerDaysOff = {};
    plannerExamDays = {};
    plannerClassesEnd = null;
  });

  test('a course below the limit with no known length is not "over the limit"',
      () {
    final c = Course(id: 'p', name: 'PADDS', held: 24, attended: 17);
    expect(skipLineN(c, 1, 85), isNot(contains('over the limit')));
    final known =
        Course(id: 'l', name: 'LAC', held: 24, attended: 19, total: 30);
    expect(skipLineN(known, 1, 85), contains('over the limit'));
  });

  test('theory and lab teachers are listed once each', () {
    final c = combine('PADDS', [
      Course(id: 't', name: 'T', held: 1, attended: 1, faculty: 'Trainer 3'),
      Course(
          id: 'l',
          name: 'L',
          held: 1,
          attended: 1,
          faculty: 'Trainer 3, Trainer 2'),
    ]);
    expect(c.faculty, 'Trainer 3, Trainer 2');
  });

  test('Moodle names lose their HTML entities', () {
    expect(unescapeHtml('Design &amp; Data &#39;26 &lt;3'),
        "Design & Data '26 <3");
    expect(unescapeHtml('Plain'), 'Plain');
  });

  test('a course code may have seven letters', () {
    expect(
        codeOf(
            'Principles of Algorithm Design and Data Structures Shweta Labs'),
        'PADDSSL');
  });

  test('no break is suggested across an exam day', () {
    final today = DateTime(2026, 12, 28); // a Monday
    // Exams Thu 31 Dec to Sun 3 Jan, which are also days off.
    for (var k = 3; k <= 6; k++) {
      final d = DateTime(2026, 12, 28 + k);
      plannerExamDays.add(day(d));
      plannerDaysOff.add(day(d));
    }
    final c = Course(
        id: 'c',
        name: 'C',
        held: 10,
        attended: 10,
        total: 40,
        weekly: {1: 2, 2: 2, 3: 2, 4: 2, 5: 2});
    for (final b in [
      ...longWeekends([c], today, 85),
      ...suggestBreaks([c], today, 85),
    ]) {
      expect(firstExamIn(b.from, b.to), isNull, reason: '${b.from} to ${b.to}');
    }
  });

  test('no classes are counted after the last day of classes', () {
    plannerClassesEnd = DateTime(2026, 12, 19);
    final c = Course(
        id: 'c',
        name: 'C',
        held: 10,
        attended: 10,
        weekly: {1: 1, 2: 1, 3: 1, 4: 1, 5: 1});
    expect(classesBetween(c, DateTime(2027, 1, 4), DateTime(2027, 1, 7)), 0);
    expect(
        classesBetween(c, DateTime(2026, 12, 14), DateTime(2026, 12, 18)), 5);
  });

  test('a message missing from the live list was taken back', () {
    final now = DateTime(2026, 11, 28, 12);
    final recent =
        Notice(5, 'Poll: Test', '', now.subtract(const Duration(hours: 3)));
    final kept = Notice(6, 'Kept', '', now);
    final old = Notice(1, 'Old', '', now.subtract(const Duration(days: 8)));
    expect(takenBack([recent, kept, old], {6}, now).map((n) => n.id), [5]);
    // An older server sends no live list: nothing is taken back.
    expect(takenBack([recent], null, now), isEmpty);
  });

  test('a taken-back message leaves the list behind the bell', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await inboxAdd(prefs, [
      InboxItem(
          key: 'notice:5',
          at: now,
          title: 'Poll: Test',
          body: '',
          channel: 'news'),
      InboxItem(
          key: 'notice:6', at: now, title: 'Kept', body: '', channel: 'news'),
    ]);
    await inboxRemove(prefs, {'notice:5'});
    expect(
        inboxItems(prefs, now.add(const Duration(seconds: 1)))
            .map((i) => i.key),
        ['notice:6']);
  });
}
