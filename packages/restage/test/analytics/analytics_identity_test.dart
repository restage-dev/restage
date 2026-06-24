import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('anonymousId is minted once and persists across instances', () async {
    var n = 0;
    final a = AnalyticsIdentity(newId: () => 'gen-${n++}');
    expect(await a.anonymousId(), 'gen-0');
    // Cached within the instance — no re-mint.
    expect(await a.anonymousId(), 'gen-0');
    // A fresh instance reads the persisted value rather than minting anew.
    final b = AnalyticsIdentity(newId: () => 'gen-SHOULD-NOT-MINT');
    expect(await b.anonymousId(), 'gen-0');
  });

  test('reset rotates anonymousId, clears userId, rotates session', () async {
    var n = 0;
    final a = AnalyticsIdentity(newId: () => 'gen-${n++}');
    final id0 = await a.anonymousId();
    final session0 = a.sessionId;
    a.identify('user-x');
    expect(a.userId, 'user-x');

    await a.reset();

    expect(await a.anonymousId(), isNot(id0));
    expect(a.userId, isNull);
    expect(a.sessionId, isNot(session0));
  });

  test('sessionId is stable until rotated', () {
    var n = 0;
    final a = AnalyticsIdentity(newId: () => 'gen-${n++}');
    final session = a.sessionId;
    expect(a.sessionId, session);
    a.rotateSession();
    expect(a.sessionId, isNot(session));
  });

  test('surfaceSessionId is settable and clearable', () {
    final a = AnalyticsIdentity();
    expect(a.surfaceSessionId, isNull);
    a.surfaceSessionId = 'surf-1';
    expect(a.surfaceSessionId, 'surf-1');
    a.surfaceSessionId = null;
    expect(a.surfaceSessionId, isNull);
  });

  test('newEventId mints a distinct id each call', () {
    var n = 0;
    final a = AnalyticsIdentity(newId: () => 'gen-${n++}');
    expect(a.newEventId(), isNot(a.newEventId()));
  });
}
