import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  test('reset fences delayed lookup and event completion by generation',
      () async {
    const oldActor = 'actor-a';
    const newActor = 'actor-b';
    const anonymousIdKey = 'restage.analytics.anonymous_id';
    final oldPreferences = await _preferencesSnapshot(
      <String, Object>{anonymousIdKey: oldActor},
    );
    final resetPreferences = await _preferencesSnapshot(
      <String, Object>{anonymousIdKey: oldActor},
    );
    final oldProvider = Completer<SharedPreferences>();
    final resetProvider = Completer<SharedPreferences>();
    var resetGeneration = false;
    final generatedIds = <String>['session-a', newActor, 'session-b'];
    final identity = AnalyticsIdentity(
      prefsProvider: () =>
          resetGeneration ? resetProvider.future : oldProvider.future,
      newId: () => generatedIds.removeAt(0),
    )
      ..surfaceSessionId = 'surface-a'
      ..identify('customer-a');

    final oldLookup = identity.anonymousId();
    final oldEvent = _queuedEvent(identity, eventId: 'event-a');

    resetGeneration = true;
    final reset = identity.reset();
    final immediateLookup = identity.anonymousId();
    final immediateEvent = _queuedEvent(identity, eventId: 'event-b');

    // The new generation is visible synchronously, before either preferences
    // operation is released.
    expect(identity.cachedAnonymousId, newActor);
    expect(await immediateLookup, newActor);
    final eventB = await immediateEvent;
    expect(eventB.anonymousId, newActor);
    expect(eventB.sessionId, 'session-b');
    expect(eventB.surfaceSessionId, isNull);
    expect(eventB.userId, isNull);

    // Persist B first, then release the isolated old-generation snapshot A.
    // This removes SharedPreferences singleton/cache callback ordering from the
    // race while keeping both provider awaits explicitly controlled.
    resetProvider.complete(resetPreferences);
    await reset;
    oldProvider.complete(oldPreferences);

    expect(await oldLookup, oldActor);
    final eventA = await oldEvent;
    expect(eventA.anonymousId, oldActor);
    expect(eventA.sessionId, 'session-a');
    expect(eventA.surfaceSessionId, 'surface-a');
    expect(eventA.userId, 'customer-a');

    final currentActor = await identity.anonymousId();
    SharedPreferences.resetStatic();
    final persistedPreferences = await SharedPreferences.getInstance();
    expect(
      <String, String?>{
        'current operation': currentActor,
        'current cache': identity.cachedAnonymousId,
        'persisted actor': persistedPreferences.getString(anonymousIdKey),
      },
      <String, String?>{
        'current operation': newActor,
        'current cache': newActor,
        'persisted actor': newActor,
      },
    );
  });

  test('reset fences a delayed old-generation mint from cache and persistence',
      () async {
    const oldActor = 'actor-a';
    const newActor = 'actor-b';
    const anonymousIdKey = 'restage.analytics.anonymous_id';
    final oldPreferences = await _preferencesSnapshot(<String, Object>{});
    final resetPreferences = await _preferencesSnapshot(<String, Object>{});
    final oldProvider = Completer<SharedPreferences>();
    final resetProvider = Completer<SharedPreferences>();
    var resetGeneration = false;
    final generatedIds = <String>[newActor, 'session-b', oldActor];
    final identity = AnalyticsIdentity(
      prefsProvider: () =>
          resetGeneration ? resetProvider.future : oldProvider.future,
      newId: () => generatedIds.removeAt(0),
    );

    final oldLookup = identity.anonymousId();

    resetGeneration = true;
    final reset = identity.reset();
    expect(identity.cachedAnonymousId, newActor);

    // Establish B in persistence before the empty old-generation snapshot is
    // allowed to resolve and mint A.
    resetProvider.complete(resetPreferences);
    await reset;
    oldProvider.complete(oldPreferences);

    // The caller that began in generation A keeps its result even though that
    // generation is no longer allowed to publish cache or persistence state.
    expect(await oldLookup, oldActor);

    final currentActor = await identity.anonymousId();
    SharedPreferences.resetStatic();
    final persistedPreferences = await SharedPreferences.getInstance();
    expect(
      <String, String?>{
        'current operation': currentActor,
        'current cache': identity.cachedAnonymousId,
        'persisted actor': persistedPreferences.getString(anonymousIdKey),
      },
      <String, String?>{
        'current operation': newActor,
        'current cache': newActor,
        'persisted actor': newActor,
      },
    );
  });

  test('concurrent cold anonymousId calls share one minted actor', () async {
    const anonymousIdKey = 'restage.analytics.anonymous_id';
    final firstPreferences = await _preferencesSnapshot(<String, Object>{});
    final secondPreferences = await _preferencesSnapshot(<String, Object>{});
    final firstProvider = Completer<SharedPreferences>();
    final secondProvider = Completer<SharedPreferences>();
    var providerCalls = 0;
    var mintedIds = 0;
    final identity = AnalyticsIdentity(
      prefsProvider: () =>
          providerCalls++ == 0 ? firstProvider.future : secondProvider.future,
      newId: () => 'actor-${mintedIds++}',
    );

    final first = identity.anonymousId();
    final second = identity.anonymousId();
    firstProvider.complete(firstPreferences);
    secondProvider.complete(secondPreferences);
    final actors = await Future.wait(<Future<String>>[first, second]);

    SharedPreferences.resetStatic();
    final persistedPreferences = await SharedPreferences.getInstance();

    expect(
      <String, Object?>{
        'results': actors,
        'provider calls': providerCalls,
        'minted ids': mintedIds,
        'current cache': identity.cachedAnonymousId,
        'persisted actor': persistedPreferences.getString(anonymousIdKey),
      },
      <String, Object?>{
        'results': <String>['actor-0', 'actor-0'],
        'provider calls': 1,
        'minted ids': 1,
        'current cache': 'actor-0',
        'persisted actor': 'actor-0',
      },
    );
  });

  test('reset starts an independent participant with no cross-identity linkage',
      () async {
    var nextId = 0;
    final identity = AnalyticsIdentity(newId: () => 'generated-${nextId++}');
    SurfaceAssignmentKeyProvider.current = identity.anonymousId;
    addTearDown(SurfaceAssignmentKeyProvider.clear);

    final oldAssignmentKey = await SurfaceAssignmentKeyProvider.resolve();
    final oldSessionId = identity.sessionId;
    identity
      ..surfaceSessionId = 'surface-session-before-reset'
      ..identify('customer-user-before-reset');
    final beforeReset = _event(
      identity,
      anonymousId: oldAssignmentKey!,
      sessionId: oldSessionId,
    );

    await identity.reset();

    final newAssignmentKey = await SurfaceAssignmentKeyProvider.resolve();
    final afterReset = _event(
      identity,
      anonymousId: newAssignmentKey!,
      sessionId: identity.sessionId,
    );

    // The event already captured under the old participant remains immutable.
    expect(beforeReset.anonymousId, oldAssignmentKey);
    expect(beforeReset.sessionId, oldSessionId);
    expect(beforeReset.surfaceSessionId, 'surface-session-before-reset');
    expect(beforeReset.userId, 'customer-user-before-reset');

    // Delivery re-evaluates assignment under the freshly-minted participant.
    expect(newAssignmentKey, isNot(oldAssignmentKey));
    expect(afterReset.anonymousId, newAssignmentKey);

    // No identity dimension on a post-reset event can join it back to the old
    // participant. Surface content identity is deliberately outside this set.
    final oldIdentityDimensions = <String?>{
      beforeReset.anonymousId,
      beforeReset.sessionId,
      beforeReset.surfaceSessionId,
      beforeReset.userId,
    };
    final newIdentityDimensions = <String?>{
      afterReset.anonymousId,
      afterReset.sessionId,
      afterReset.surfaceSessionId,
      afterReset.userId,
    };
    expect(newIdentityDimensions.intersection(oldIdentityDimensions), isEmpty);
  });

  testWidgets(
      'Restage.reset changes identity synchronously, leaves no fabricated '
      'surface session, and the next real mount creates a fresh one',
      (tester) async {
    final postedEvents = <Map<String, Object?>>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      postedEvents.addAll(
        (body['events']! as List<Object?>).cast<Map<String, Object?>>(),
      );
      return http.Response('', 200);
    });
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );

    final resolver = _TextResolver();
    await _mountPaywall(tester, id: 'before-reset', resolver: resolver);
    final oldAssignmentKey = await SurfaceAssignmentKeyProvider.resolve();

    Restage.identify('customer-before-reset');
    Restage.track('queued_before_reset');

    // reset() is synchronous at its public boundary: code that fires or fetches
    // immediately after this call must already see the new participant.
    Restage.reset();
    Restage.track('immediate_after_reset');
    final immediateAssignmentKey = await SurfaceAssignmentKeyProvider.resolve();

    await tester.pump();
    await Restage.debugFlushAnalytics();

    final beforeReset = _posted(postedEvents, 'queued_before_reset');
    final afterReset = _posted(postedEvents, 'immediate_after_reset');
    final oldSurfaceSessionId = beforeReset['surfaceSessionId'] as String?;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _mountPaywall(tester, id: 'after-reset', resolver: resolver);
    Restage.track('after_real_mount');
    await tester.pump();
    await Restage.debugFlushAnalytics();

    final afterRealMount = _posted(postedEvents, 'after_real_mount');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(oldAssignmentKey, isNotNull);
    expect(immediateAssignmentKey, isNot(oldAssignmentKey));

    // The queued pre-reset event keeps its old actor; the immediate post-reset
    // event has the new actor/session, no user, and no invented presentation.
    expect(beforeReset['anonymousId'], oldAssignmentKey);
    expect(beforeReset['userId'], 'customer-before-reset');
    expect(oldSurfaceSessionId, isNotNull);
    expect(afterReset['anonymousId'], immediateAssignmentKey);
    expect(afterReset['anonymousId'], isNot(beforeReset['anonymousId']));
    expect(afterReset['sessionId'], isNot(beforeReset['sessionId']));
    expect(afterReset['userId'], isNull);
    expect(afterReset['surfaceSessionId'], isNull);

    expect(afterRealMount['anonymousId'], immediateAssignmentKey);
    expect(afterRealMount['sessionId'], afterReset['sessionId']);
    expect(afterRealMount['userId'], isNull);
    expect(afterRealMount['surfaceSessionId'], isNotNull);
    expect(afterRealMount['surfaceSessionId'], isNot(oldSurfaceSessionId));
  });
}

AnalyticsEvent _event(
  AnalyticsIdentity identity, {
  required String anonymousId,
  required String sessionId,
}) =>
    mapRestageEventToEnvelope(
      const PaywallViewed(paywallId: 'pricing', productIds: []),
      eventId: identity.newEventId(),
      anonymousId: anonymousId,
      sessionId: sessionId,
      surfaceSessionId: identity.surfaceSessionId,
      userId: identity.userId,
      appContext: const AnalyticsAppContext(
        platform: AnalyticsPlatform.ios,
        locale: 'en-US',
        sdkVersion: '1.0.0',
      ),
      now: DateTime.utc(2026, 1, 1),
    );

Future<AnalyticsEvent> _queuedEvent(
  AnalyticsIdentity identity, {
  required String eventId,
}) async {
  final sessionId = identity.sessionId;
  final surfaceSessionId = identity.surfaceSessionId;
  final userId = identity.userId;
  final anonymousId =
      identity.cachedAnonymousId ?? await identity.anonymousId();
  return mapRestageEventToEnvelope(
    const PaywallViewed(paywallId: 'pricing', productIds: []),
    eventId: eventId,
    anonymousId: anonymousId,
    sessionId: sessionId,
    surfaceSessionId: surfaceSessionId,
    userId: userId,
    appContext: const AnalyticsAppContext(
      platform: AnalyticsPlatform.ios,
      locale: 'en-US',
      sdkVersion: '1.0.0',
    ),
    now: DateTime.utc(2026, 1, 1),
  );
}

Future<SharedPreferences> _preferencesSnapshot(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Map<String, Object?> _posted(
  List<Map<String, Object?>> events,
  String name,
) =>
    events.singleWhere((event) => event['name'] == name);

Future<void> _mountPaywall(
  WidgetTester tester, {
  required String id,
  required VariantResolver resolver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: RestagePaywall(id: id, resolver: resolver)),
    ),
  );
  await tester.pumpAndSettle();
}

final class _TextResolver implements VariantResolver {
  _TextResolver()
      : _bytes = Uint8List.fromList(
          encodeLibraryBlob(
            parseLibraryFile('''
              import restage.core;
              widget Paywall = Text(text: "Ready");
            '''),
          ),
        );

  final Uint8List _bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: _bytes, paywallId: id);
}
