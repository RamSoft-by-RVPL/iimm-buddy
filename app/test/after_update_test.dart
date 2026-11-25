import 'package:attendance_planner/background.dart';
import 'package:attendance_planner/changes.dart';
import 'package:attendance_planner/log.dart';
import 'package:attendance_planner/planner.dart';
import 'package:attendance_planner/site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the first check after an app update notes classes without alerts',
      () async {
    final day = DateTime.now().add(const Duration(days: 2));
    final d = DateTime(day.year, day.month, day.day);
    ClassSlot slot(int id, String start) => ClassSlot(id, d, start,
        '${start.substring(0, 2)}:30', '404', 'Lab', 'lab', 'Not Marked', true);
    final snap = Snapshot(
      studentName: 'A',
      roll: '1',
      courses: [Course(id: 'lab', name: 'Lab', held: 1, attended: 1)],
      syncedAt: d,
      sessions: [slot(1, '09:00'), slot(2, '14:00')],
    );
    // The old version saw only the 9:00 class (it hid the 14:00 one).
    SharedPreferences.setMockInitialValues({
      'seen_classes': encodeSeen([Seen.of(slot(1, '09:00'))]),
      'seen_build': appBuild - 1,
    });
    final prefs = await SharedPreferences.getInstance();
    // Would throw on the notification plugin if it tried to announce.
    await announceClassChanges(Store(prefs), snap);
    expect(prefs.getInt('seen_build'), appBuild);
    expect(decodeSeen(prefs.getString('seen_classes'))!.length, 2);
  });
}
