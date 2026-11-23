import 'package:attendance_planner/too_old_ui.dart';
import 'package:attendance_planner/update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('versions compare by number, not by text', () {
    expect(compareVersions('0.8.9', '0.8.10') < 0, true);
    expect(compareVersions('0.8.21', '0.8.21'), 0);
    expect(compareVersions('0.9.0', '0.8.30') > 0, true);
    expect(compareVersions('1.0', '0.8.21') > 0, true);
  });

  test('only a version below the minimum is stopped', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Nothing heard from the server yet: the app works.
    expect(tooOld(prefs, current: '0.8.4'), false);
    await prefs.setString('min_version', '0.8.21');
    expect(tooOld(prefs, current: '0.8.20'), true);
    expect(tooOld(prefs, current: '0.8.21'), false);
    expect(tooOld(prefs, current: '0.8.22'), false);
    // The admin let every version in again.
    await prefs.setString('min_version', '');
    expect(tooOld(prefs, current: '0.8.4'), false);
  });

  testWidgets('the stop screen offers only the update', (tester) async {
    SharedPreferences.setMockInitialValues({'min_version': '9.0.0'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
        home: TooOldScreen(prefs: prefs, onChanged: () {})));
    await tester.pump();
    expect(find.text('Time to update.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });
}
