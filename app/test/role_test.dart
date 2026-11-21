import 'package:attendance_planner/backend.dart';
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
}
