import 'package:attendance_planner/demo.dart';
import 'package:attendance_planner/moodle.dart';
import 'package:attendance_planner/net.dart';
import 'package:attendance_planner/site.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => demoMode = false);

  test('demo summary reads like the real site', () {
    final now = DateTime.now();
    final s = parseSummary(demoSummary(now), now, {});
    expect(s.studentName, isNotEmpty);
    expect(s.courses, hasLength(6));
    expect(s.next, isNotEmpty);
    expect(s.next.first.startsAt.isAfter(now), isTrue);
  });

  test('demo answers instead of the site and Moodle', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await startDemo(prefs);
    expect(isDemo(prefs), isTrue);
    expect(await siteApi('api/student-dashboard.php?action=summary'),
        contains('ARJUN'));
    await expectLater(httpSend(Uri.parse(moodleBase)), throwsException);

    final m = Moodle(prefs);
    final courses = await m.courses();
    expect(courses, hasLength(6));
    expect(await m.sections(courses.first.id), isNotEmpty);
    expect(await m.deadlines(), hasLength(2));

    await stopDemo(prefs);
    expect(isDemo(prefs), isFalse);
    expect(demoMode, isFalse);
    expect(prefs.getString('exams_pub'), isNull);
  });
}
