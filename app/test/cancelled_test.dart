import 'package:attendance_planner/changes.dart';
import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/site.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final d = DateTime(2026, 11, 20);
  ClassSlot slot(int id, String start, String course, String cid,
          {String status = 'Not Marked'}) =>
      ClassSlot(id, d, start, '${start.substring(0, 2)}:30', '404', course, cid,
          status, status == 'Not Marked');
  final snap = Snapshot(
    studentName: 'A',
    roll: '1',
    courses: [
      Course(id: 'pf', name: 'Programming Fundamentals', held: 10, attended: 9),
      Course(
          id: 'lac',
          name: 'Linear Algebra and Calculus',
          held: 10,
          attended: 9),
    ],
    syncedAt: d,
    sessions: [
      slot(1, '09:00', 'Programming Fundamentals', 'pf'),
      slot(2, '10:40', 'Linear Algebra and Calculus', 'lac'),
      slot(3, '14:00', 'Programming Fundamentals', 'pf', status: 'Present'),
    ],
  );
  List<int> ids(Snapshot s) => [for (final x in s.sessions) x.id];

  test('a cancelled class is hidden, others stay', () {
    final off = Cancelled.decode(
        '{"classes":[{"id":1,"d":"2026-11-20","s":"09:00","c":"Programming Fundamentals","why":""}]}');
    expect(ids(snap.withoutCancelled(off)), [2, 3]);
  });

  test('empty course cancels every class at that time', () {
    final off = [Cancelled(d, '10:40', '')];
    expect(ids(snap.withoutCancelled(off)), [1, 3]);
  });

  test('another course at that time, another day, or a marked class stay', () {
    expect(
        ids(snap.withoutCancelled(
            [Cancelled(d, '09:00', 'Linear Algebra and Calculus')])),
        [1, 2, 3]);
    expect(
        ids(snap.withoutCancelled(
            [Cancelled(DateTime(2026, 11, 21), '09:00', '')])),
        [1, 2, 3]);
    expect(ids(snap.withoutCancelled([Cancelled(d, '14:00', '')])), [1, 2, 3]);
  });

  test('a bad answer cancels nothing', () {
    expect(Cancelled.decode('oops'), isEmpty);
    expect(Cancelled.decode(null), isEmpty);
  });

  test('the change check announces it as cancelled', () {
    final now = DateTime(2026, 11, 19, 12);
    final before = comingClasses(snap.next, now);
    final after = comingClasses(
        snap.withoutCancelled([Cancelled(d, '09:00', '')]).next, now);
    final c = classChanges(before, after, now);
    expect(c.single.title, 'Class cancelled: Programming Fundamentals');
  });
}
