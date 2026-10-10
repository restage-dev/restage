import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hosted_artifact_delivery.dart';

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
      ..identify('user-a');

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
    expect(eventA.userId, 'user-a');

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
      ..identify('user-before-reset');
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
    expect(beforeReset.userId, 'user-before-reset');

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
      'Restage.reset rotates the issued assignment credential across a real '
      'paywall mount', (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );
    final initialLease = await SurfaceAssignmentKeyProvider.captureLease();
    expect(initialLease.registration, isNotNull);
    expect(initialLease.canSend, isTrue);

    final delivery = HostedArtifactFixture();
    final sent = <Map<String, dynamic>>[];
    final blob = _textBlob();
    var issued = 0;
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'http://127.0.0.1:1',
      assetFallback: _TextResolver(),
      httpClient: delivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add(body);
        expect(body['registrationNonce'], matches(r'^[A-Za-z0-9_-]{43}$'));
        expect(body['registrationCreatedAtMicros'], isA<int>());
        expect(body, isNot(contains('assignmentKey')),
            reason: 'each cold participant enrolls through this mount');
        final now = DateTime.now().microsecondsSinceEpoch;
        return http.Response(
          jsonEncode({
            ...delivery.describe(testBlobDocument(
              blob,
              surfaceSlug: body['surfaceSlug'] as String,
            )),
            'credentialHandle':
                'ic1.${(++issued).toRadixString(16).padLeft(64, '0')}',
            'expiresAtMicros': now + 30 * Duration.microsecondsPerDay,
            'serverNowMicros': now,
          }),
          200,
        );
      }),
    );
    await _mountPaywall(tester, id: 'pro_upgrade', resolver: resolver);
    final firstRequestCount = sent.length;
    final firstReadyCount = find.text('Ready').evaluate().length;
    final old = await SurfaceAssignmentKeyProvider.captureLease();
    final oldAssignmentKey = old.assignmentKey;

    // reset() is synchronous at its public boundary: code that fires or fetches
    // immediately after this call must already see the new participant.
    Restage.reset();
    final immediate = await SurfaceAssignmentKeyProvider.captureLease();

    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(firstRequestCount, 1);
    expect(firstReadyCount, 1);

    // A later real mount stays on the post-reset participant rather than
    // recovering the retired one.
    await _mountPaywall(tester, id: 'pro_upgrade', resolver: resolver);
    final secondReadyCount = find.text('Ready').evaluate().length;
    final secondRequestCount = sent.length;
    final afterRealMountKey =
        (await SurfaceAssignmentKeyProvider.captureLease()).assignmentKey;
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(secondReadyCount, 1);
    expect(secondRequestCount, 2);
    expect(oldAssignmentKey, isNotNull);
    expect(old.isCurrent, isFalse);
    expect(immediate.registration, isNotNull);
    expect(immediate.registration!.registrationNonce,
        isNot(old.registration!.registrationNonce));
    expect(immediate.assignmentKey, isNull,
        reason: 'reset does not enroll before another origin request');
    expect(afterRealMountKey, isNotNull);
    expect(afterRealMountKey, isNot(oldAssignmentKey));
    expect(sent, hasLength(2));
    expect(sent[0]['registrationNonce'], old.registration!.registrationNonce);
    expect(sent[1]['registrationNonce'],
        immediate.registration!.registrationNonce);
    expect(delivery.artifactRequests, isNotEmpty);
    expect(issued, 2);
  });
}

typedef _IdentityStamp = ({
  String anonymousId,
  String sessionId,
  String? surfaceSessionId,
  String? userId,
});

_IdentityStamp _event(
  AnalyticsIdentity identity, {
  required String anonymousId,
  required String sessionId,
}) =>
    (
      anonymousId: anonymousId,
      sessionId: sessionId,
      surfaceSessionId: identity.surfaceSessionId,
      userId: identity.userId,
    );

Future<_IdentityStamp> _queuedEvent(
  AnalyticsIdentity identity, {
  required String eventId,
}) async {
  final sessionId = identity.sessionId;
  final surfaceSessionId = identity.surfaceSessionId;
  final userId = identity.userId;
  final anonymousId =
      identity.cachedAnonymousId ?? await identity.anonymousId();
  return (
    anonymousId: anonymousId,
    sessionId: sessionId,
    surfaceSessionId: surfaceSessionId,
    userId: userId,
  );
}

Future<SharedPreferences> _preferencesSnapshot(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _mountPaywall(
  WidgetTester tester, {
  required String id,
  required VariantResolver resolver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: id,
          resolver: resolver,
          errorBuilder: (_, error) => Text('ERROR: $error'),
        ),
      ),
    ),
  );
  // Platform observation replies need real event-loop turns. Keep the fake
  // mount clock within its original deadline while those ready inputs settle.
  for (var i = 0; i < 200 && find.text('Ready').evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Uint8List _textBlob() =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
  import restage.core;
  widget Paywall = Text(text: "Ready");
''')));

final class _TextResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
        bytes: _textBlob(),
        surfaceVersion: 'test',
        paywallId: id,
      );
}
