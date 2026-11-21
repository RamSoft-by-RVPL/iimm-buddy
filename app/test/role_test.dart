import 'package:attendance_planner/backend.dart';
import 'package:attendance_planner/role_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a role from the server', () {
    final r = decodeRole('{"role":"cr","label":"CR","batch":"bs-2026-2030",'
        '"token":"abc","can":{"notice":true,"cancel":true}}')!;
    expect([r.label, r.audience, r.canCancel], ['CR', 'bs-2026-2030', true]);
    final m = decodeRole('{"role":"mess","label":"Mess Secretary","batch":"",'
        '"token":"abc","can":{"notice":true,"cancel":false}}')!;
    expect([m.audience, m.canCancel], ['everyone', false]);
  });

  test('no role, or a broken answer, is no role', () {
    expect(decodeRole('{"role":null}'), isNull);
    expect(decodeRole(''), isNull);
    expect(decodeRole('oops'), isNull);
    expect(decodeRole('{"role":"cr","label":"CR"}'), isNull); // no token
  });

  test('seen count only for sent posts with someone to count', () {
    final now = DateTime(2026, 11, 21, 12);
    MyPost p(DateTime at, int got, int of) =>
        MyPost(1, 'CR: x', '', at, received: got, audience: of);
    expect(seenLine(p(DateTime(2026, 11, 21, 10), 5, 8), now),
        'seen on 5 of 8 phones');
    expect(seenLine(p(DateTime(2026, 11, 21, 10), 1, 1), now),
        'seen on 1 of 1 phone');
    expect(seenLine(p(DateTime(2026, 11, 21, 15), 0, 8), now), ''); // later
    expect(seenLine(p(DateTime(2026, 11, 21, 10), 0, 0), now), '');
  });

  test('every role has quick posts', () {
    for (final r in ['cr', 'mess', 'hostel']) {
      expect(roleTemplates[r], isNotEmpty);
    }
  });
}
