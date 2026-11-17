import 'package:attendance_planner/planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leave left without course length', () {
    // 17/17: can miss 3 (17/20 = 85%), not 4 (17/21 = 80.9%).
    expect(
        leaveLeft(Course(id: 'a', name: 'a', held: 17, attended: 17), 85), 3);
    // 16/20 = 80%: already short.
    expect(leaveLeft(Course(id: 'a', name: 'a', held: 20, attended: 16), 85),
        lessThan(0));
    expect(leaveLeft(Course(id: 'a', name: 'a', held: 0, attended: 0), 85), 0);
  });

  test('leave left with course length', () {
    // 20 classes at 85% allows 3 absences in all.
    final c = Course(id: 'a', name: 'a', held: 8, attended: 7, total: 20);
    expect(leaveLeft(c, 85), 2);
    final d = Course(id: 'a', name: 'a', held: 8, attended: 4, total: 20);
    expect(leaveLeft(d, 85), -1);
  });

  test('classes to recover', () {
    // 16/20 -> need 7 more: 23/27 = 85.2%; 22/26 = 84.6%.
    expect(
        classesToRecover(
            Course(id: 'a', name: 'a', held: 20, attended: 16), 85),
        7);
    expect(
        classesToRecover(
            Course(id: 'a', name: 'a', held: 20, attended: 17), 85),
        0);
  });

  test('classes between dates follow the weekly timetable', () {
    final c = Course(
        id: 'a',
        name: 'a',
        held: 0,
        attended: 0,
        weekly: {DateTime.monday: 2, DateTime.thursday: 1});
    // Mon 16 Nov 2026 to Sun 22 Nov 2026.
    expect(
        classesBetween(c, DateTime(2026, 11, 16), DateTime(2026, 11, 22)), 3);
    // Tue to Wed: nothing.
    expect(
        classesBetween(c, DateTime(2026, 11, 17), DateTime(2026, 11, 18)), 0);
    // End before start.
    expect(
        classesBetween(c, DateTime(2026, 11, 22), DateTime(2026, 11, 16)), 0);
  });

  test('holiday impact', () {
    final c = Course(
        id: 'a',
        name: 'a',
        held: 10,
        attended: 10,
        total: 20,
        weekly: {DateTime.monday: 1, DateTime.thursday: 1});
    final today = DateTime(2026, 11, 16); // Monday
    // Away Mon 23 to Fri 27: misses 2. Thu 19 attended before leaving.
    final ok = holidayImpact(
        c, today, DateTime(2026, 11, 23), DateTime(2026, 11, 27), 85);
    expect(ok.missed, 2);
    expect(ok.heldAfter, 13);
    expect(ok.attendedAfter, 11);
    expect(ok.safe, true);
    expect(ok.leaveAfter, 1);

    // Away two weeks: misses 4, over the budget of 3.
    final bad = holidayImpact(
        c, today, DateTime(2026, 11, 23), DateTime(2026, 12, 4), 85);
    expect(bad.missed, 4);
    expect(bad.safe, false);
    expect(bad.leaveAfter, -1);
  });

  test('holiday never counts classes past the end of the course', () {
    final c = Course(
        id: 'a',
        name: 'a',
        held: 19,
        attended: 19,
        total: 20,
        weekly: {DateTime.monday: 1});
    final r = holidayImpact(c, DateTime(2026, 11, 16), DateTime(2026, 11, 17),
        DateTime(2026, 12, 31), 85);
    expect(r.missed, 1);
    expect(r.safe, true);
  });

  test('published classes are used up to the horizon, weekly pattern after',
      () {
    final c = Course(
        id: 'a',
        name: 'a',
        held: 0,
        attended: 0,
        weekly: {DateTime.monday: 1},
        upcoming: [
          DateTime(2026, 11, 18),
          DateTime(2026, 11, 18),
          DateTime(2026, 11, 20)
        ],
        horizon: DateTime(2026, 11, 22));
    // Mon 16 is inside the published range and has no class listed.
    expect(
        classesBetween(c, DateTime(2026, 11, 16), DateTime(2026, 11, 19)), 2);
    // Up to Mon 30: 3 published + Mon 23 and Mon 30 estimated.
    expect(
        classesBetween(c, DateTime(2026, 11, 16), DateTime(2026, 11, 30)), 5);
    expect(isEstimated(c, DateTime(2026, 11, 19)), false);
    expect(isEstimated(c, DateTime(2026, 11, 30)), true);
  });
}
