import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/early/early_request.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_identity.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/governed_measurement_transport.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/runtime/native_facts.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_persistence.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late SharedPreferences prefs;
  late _Preferences storage;

  void configure({String apiKey = 'rs_pk_erasure'}) {
    http.runWithClient(
        () => Restage.configure(
              apiKey: apiKey,
              baseUrl: 'https://sdk.example.com',
              governedMeasurementTransport: transport,
            ),
        () => MockClient((_) async => http.Response('', 503)));
  }

  Future<SurfaceAssignmentResolutionLease> confirm({
    String? handle,
    int lifetimeMicros = Duration.microsecondsPerDay,
  }) async {
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    final now = DateTime.now().microsecondsSinceEpoch;
    expect(
      await lease.confirmRegistration!(
        lease.registration!,
        now,
        handle ?? 'ic1.${'a' * 64}',
        now + lifetimeMicros,
        now,
      ),
      isTrue,
    );
    return lease;
  }

  List<String> pendingRecords() => prefs
      .getKeys()
      .where((key) => key.startsWith('restage.installErasure.'))
      .map((key) => prefs.getString(key)!)
      .toList();

  setUp(() async {
    await Restage.debugResetAndWait();
    EarlyRequest.identitySetter = null;
    EarlyRequest.startupInvalidator = null;
    NativeFacts.debugFacts = null;
    NativeFacts.debugResetRegistration = null;
    NativeFacts.reset();
    SharedPreferences.setMockInitialValues({});
    storage = _Preferences();
    SharedPreferencesStorePlatform.instance = storage;
    prefs = await SharedPreferences.getInstance();
    transport = _Transport();
    configure();
  });

  tearDown(() async {
    EarlyRequest.identitySetter = null;
    EarlyRequest.startupInvalidator = null;
    NativeFacts.debugFacts = null;
    NativeFacts.debugResetRegistration = null;
    NativeFacts.reset();
    await SurfaceAssignmentPersistence.ready.catchError((Object _) {});
    SurfaceAssignmentPersistence.debugRestart();
    await Restage.debugResetAndWait();
  });

  test('disabled no argument deletion warns with held handle and sends no HTTP',
      () async {
    final requests = <http.Request>[];
    http.runWithClient(
        () => Restage.configure(
              apiKey: 'rs_pk_erasure',
              baseUrl: 'https://sdk.example.com',
            ),
        () => MockClient((request) async {
              requests.add(request);
              return http.Response('', 503);
            }));
    final lease = await confirm();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    final messages = _capturePrivacyWarnings();
    final result = await Restage.privacy.request();
    expect(result.status, RestagePrivacyCoordinatorStatus.failed);
    expect(requests, isEmpty);
    expect(transport.requests, isEmpty);
    expect(messages, [_privacyDisabledMessage]);
    expect(lease.isCurrent, isTrue);
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    final pending = pendingRecords().single;
    expect((jsonDecode(pending) as Map)['request']['assignmentKey'],
        'ic1.${'a' * 64}');
    await Restage.privacy.request();
    expect(requests, isEmpty);
    expect(messages, [_privacyDisabledMessage]);
    expect(pendingRecords().single, pending);
    expect(messages.single, isNot(contains('ic1.${'a' * 64}')));
  });

  test('disabled no argument deletion warns before context or handle exists',
      () async {
    await Restage.debugResetAndWait();
    final messages = _capturePrivacyWarnings();
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(messages, [_privacyDisabledMessage]);
    expect(transport.requests, isEmpty);
    expect(pendingRecords(), isEmpty);
  });

  test('custom no argument deletion failure has no disabled warning', () async {
    await confirm();
    transport.onRequest = (request) async => unavailablePrivacyReceipt(request);
    final messages = _capturePrivacyWarnings();
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(transport.requests, hasLength(1));
    expect(
        messages.where((message) => message.startsWith('[restage] Restage.')),
        isEmpty);
    expect(pendingRecords(), hasLength(1));
  });

  test('completion waits for native identity acknowledgement', () async {
    await confirm();
    final entered = Completer<void>();
    final release = Completer<bool>();
    EarlyRequest.startupInvalidator = () async => true;
    EarlyRequest.identitySetter = (_, __) {
      if (!entered.isCompleted) entered.complete();
      return release.future;
    };
    var completed = false;
    final pending = Restage.privacy.request().then((result) {
      completed = true;
      return result;
    });
    try {
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect((jsonDecode(pendingRecords().single) as Map)['finalized'],
          isNot(true));
    } finally {
      release.complete(true);
      await pending;
    }
  });

  test('failed native identity acknowledgement retries after restart',
      () async {
    await confirm();
    final originalActor = prefs.getString('restage.analytics.anonymous_id');
    var nativeActor = originalActor;
    EarlyRequest.startupInvalidator = () async => true;
    EarlyRequest.identitySetter = (_, __) async => false;
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(pendingRecords(), hasLength(1));
    await Restage.debugResetAndWait();
    SurfaceAssignmentPersistence.debugRestart();
    await prefs.reload();
    EarlyRequest.identitySetter = (_, actor) async {
      nativeActor = actor;
      return true;
    };
    configure();
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.completed);
    expect(nativeActor, prefs.getString('restage.analytics.anonymous_id'));
    expect(nativeActor, isNot(originalActor));
  });

  test('completion waits for native startup invalidation', () async {
    await confirm();
    final entered = Completer<void>();
    final release = Completer<bool>();
    EarlyRequest.identitySetter = (_, __) async => true;
    EarlyRequest.startupInvalidator = () {
      entered.complete();
      return release.future;
    };
    var completed = false;
    final pending = Restage.privacy.request().then((result) {
      completed = true;
      return result;
    });
    try {
      await Future.any([entered.future, pending.then((_) {})]);
      expect(completed, isFalse);
      expect((jsonDecode(pendingRecords().single) as Map)['finalized'],
          isNot(true));
    } finally {
      release.complete(true);
      await pending;
    }
  });

  test('failed native startup invalidation retries after restart', () async {
    await confirm();
    var startupEnabled = true;
    EarlyRequest.identitySetter = (_, __) async => true;
    EarlyRequest.startupInvalidator = () async => false;
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(startupEnabled, isTrue);
    await Restage.debugResetAndWait();
    SurfaceAssignmentPersistence.debugRestart();
    await prefs.reload();
    EarlyRequest.startupInvalidator = () async {
      startupEnabled = false;
      return true;
    };
    configure();
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.completed);
    expect(startupEnabled, isFalse);
  });

  test('unfinished marker restores enrollment fence before restart retry',
      () async {
    await confirm();
    storage.failFinalizedWrite = true;
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    final markedActor =
        (jsonDecode(pendingRecords().single) as Map)['resetActor'];
    storage.failFinalizedWrite = false;
    await Restage.debugResetAndWait();
    SurfaceAssignmentPersistence.debugRestart();
    await prefs.reload();
    configure();
    final beforeRetry = await SurfaceAssignmentKeyProvider.captureLease();
    expect(beforeRetry.registration, isNull,
        reason:
            'Unfinished durable reset must block enrollment before privacy retry');
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.completed);
    expect(prefs.getString('restage.analytics.anonymous_id'), markedActor);
    final fresh = await confirm(handle: 'ic1.${'b' * 64}');
    expect(
        (await SurfaceAssignmentKeyProvider.captureLease())
            .registration!
            .registrationNonce,
        fresh.registration!.registrationNonce);
    expect(
        await SurfaceAssignmentKeyProvider.resolveLocal(), 'ic1.${'b' * 64}');
  });

  test('self erasure sends expired stored handle without serving rollover',
      () async {
    final lease = await confirm(lifetimeMicros: 1);
    final registrationKey = prefs.getKeys().singleWhere(
          (key) => key.startsWith('restage.assignmentRegistration.'),
        );
    final stored = prefs.getString(registrationKey);
    final generation = SurfaceAssignmentKeyProvider.analyticsIdentityGeneration;
    final writes = storage.registrationWrites;
    transport.onRequest = (request) async {
      expect(_operation(request).assignmentKey, 'ic1.${'a' * 64}');
      expect(prefs.getString(registrationKey), stored);
      expect(
          SurfaceAssignmentKeyProvider.analyticsIdentityGeneration, generation);
      return unavailablePrivacyReceipt(request);
    };
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(transport.requests, hasLength(1));
    expect(prefs.getString(registrationKey), stored);
    expect(storage.registrationWrites, writes);
    expect(
        SurfaceAssignmentKeyProvider.analyticsIdentityGeneration, generation);
    expect(lease.isCurrent, isTrue);
    expect(pendingRecords(), hasLength(1));
  });

  test('no handle privacy read does not mint or advance serving generation',
      () async {
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    expect(lease.registration, isNotNull);
    expect(lease.assignmentKey, isNull);
    final writes = storage.registrationWrites;
    final generation = SurfaceAssignmentKeyProvider.analyticsIdentityGeneration;
    final registrations = {
      for (final key in prefs.getKeys().where(
            (key) => key.startsWith('restage.assignmentRegistration.'),
          ))
        key: prefs.getString(key)
    };
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    expect(transport.requests, isEmpty);
    expect(storage.registrationWrites, writes);
    expect(
        SurfaceAssignmentKeyProvider.analyticsIdentityGeneration, generation);
    expect({for (final key in registrations.keys) key: prefs.getString(key)},
        registrations);
    expect(pendingRecords(), isEmpty);
  });

  test('self erasure sends stored handle', () async {
    await confirm();
    transport.onRequest = (request) async {
      expect(pendingRecords(), hasLength(1));
      final persisted = jsonDecode(pendingRecords().single) as Map;
      final sent = _operation(request);
      expect((persisted['request'] as Map)['operationId'], sent.operationId);
      expect(sent.assignmentKey, 'ic1.${'a' * 64}');
      expect(request.targets, RestagePrivacyTargets.measurement);
      expect(request.action, RestagePrivacyAction.delete);
      return _completed(request);
    };
    final result = await Restage.privacy.request();
    expect(result.status, RestagePrivacyCoordinatorStatus.completed);
    expect(transport.requests, hasLength(1));
    expect(pendingRecords(), isEmpty);
  });

  test('lost receipt reuses pending operation after restart', () async {
    await confirm();
    transport.onRequest = (_) async => throw StateError('response lost');
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final first = transport.requests.single.canonicalBytes;
    final durable = pendingRecords().single;
    await Restage.debugResetAndWait();
    await prefs.reload();
    transport = _Transport();
    configure();
    expect(pendingRecords().single, durable);
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(transport.requests.single.canonicalBytes, first);
    expect(pendingRecords(), isEmpty);
  });

  test('completion rotates assignment identity and preserves metering',
      () async {
    final old = await confirm();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    final metering = await SurfaceMeteringKeyProvider.currentKey();
    expect(metering, isNotNull);
    await prefs.setString('host.setting', 'preserved');
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    await prefs.reload();
    expect(prefs.getString('restage.analytics.anonymous_id'), isNot(actor));
    expect(prefs.getString('restage.analytics.anonymous_id'), isNotNull);
    expect(old.isCurrent, isFalse);
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(
      next.registration!.registrationNonce,
      isNot(old.registration!.registrationNonce),
    );
    expect(next.assignmentKey, isNull);
    expect(await SurfaceMeteringKeyProvider.currentKey(), metering);
    expect(prefs.getString('restage.metering_token'), metering);
    expect(prefs.getString('host.setting'), 'preserved');
    expect(pendingRecords(), isEmpty);
  });

  test('mismatched receipt keeps retry authority', () async {
    await confirm();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    transport.onRequest =
        (request) async => _completed(request, operationId: 'other.operation');
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(pendingRecords(), hasLength(1));
    transport.onRequest = (request) async => _completed(request);
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(
      transport.requests.last.canonicalBytes,
      transport.requests.first.canonicalBytes,
    );
  });

  test('late receipt does not rotate newer identity', () async {
    await confirm();
    final entered = Completer<RestagePrivacyRequestV1>();
    final response = Completer<RestagePrivacyReceiptV1>();
    transport.onRequest = (request) {
      entered.complete(request);
      return response.future;
    };
    final pending = Restage.privacy.request();
    final request = await entered.future;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    final actor = prefs.getString('restage.analytics.anonymous_id');
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    response.complete(_completed(request));
    expect((await pending).status, RestagePrivacyCoordinatorStatus.failed);
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(next.isCurrent, isTrue);
    expect(pendingRecords(), hasLength(1));
  });

  test('scope change keeps pending authority in its original app', () async {
    await confirm();
    transport.onRequest = (_) async => throw StateError('response lost');
    await Restage.privacy.request();
    final original = pendingRecords().single;
    final other = _Transport();
    transport = other;
    configure(apiKey: 'rs_pk_other');
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(other.requests, isEmpty);
    expect(pendingRecords(), [original]);
  });

  testWidgets(
      'a presentation painted before an erasure is not filed under the new '
      'identity when its session opens after it', (tester) async {
    await tester.runAsync(confirm);
    final fixture = AdmittedBundledPublicationFixture.build();
    final profile = Completer<BundledMeasurementTargetProfileLoadResult>();
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () => profile.future,
      presentationMetadataAdmitted: true,
    );
    addTearDown(harness.close);
    final bytes =
        Uint8List.fromList(AdmittedBundledPublicationFixture.artifactBytes);
    final session = MeasurementHostSessionController.openDeferred(
      attachMeasurementBundledGeneratedSourceCarrier(
        ResolvedVariant(
          bytes: bytes,
          paywallId: 'fixture-artifact',
          surfaceVersion: FlowContentHash.compute(bytes).value,
        ),
        MeasurementBundledGeneratedSourceCarrier(
          measurementPublicationDraftDigest: fixture
              .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
        ),
      ),
    );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: session.wrapRootSubtree(const SizedBox(width: 10, height: 10)),
    ));
    await tester.pump();
    expect(session.debugState, MeasurementHostSessionDebugState.pending);

    final erased = await tester.runAsync(Restage.privacy.request);
    expect(erased!.status, RestagePrivacyCoordinatorStatus.completed);

    final logs = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    try {
      profile.complete(BundledMeasurementTargetProfileLoadResult(
        target: fixture.target,
        bindingReadPort: fixture.port,
      ));
      for (var i = 0; i < 20; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    } finally {
      debugPrint = previous;
    }

    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(harness.worker.registrations, isEmpty);
    expect(harness.worker.deliveries, isEmpty);
    expect(logs.where((m) => m?.startsWith('[restage]') ?? false), [
      '[restage] measurement session did not open; this presentation is not '
          'measured',
    ]);
    expect(
      await tester.runAsync(
          () => session.teardown().timeout(const Duration(seconds: 5))),
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('no handle does not register', () async {
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(transport.requests, isEmpty);
    expect(pendingRecords(), isEmpty);
  });

  test('concurrent requests share one operation', () async {
    await confirm();
    final entered = Completer<RestagePrivacyRequestV1>();
    final response = Completer<RestagePrivacyReceiptV1>();
    transport.onRequest = (request) {
      entered.complete(request);
      return response.future;
    };
    final first = Restage.privacy.request();
    final second = Restage.privacy.request();
    final request = await entered.future;
    expect(transport.requests, hasLength(1));
    response.complete(_completed(request));
    final results = await Future.wait([first, second]);
    expect(
      results.every(
        (r) => r.status == RestagePrivacyCoordinatorStatus.completed,
      ),
      isTrue,
    );
    expect(transport.requests, hasLength(1));
  });

  test('pending write failure blocks sending and retains the operation',
      () async {
    await confirm();
    storage.failPendingWrite = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(transport.requests, isEmpty);
    final record = jsonDecode(pendingRecords().single) as Map;
    storage.failPendingWrite = false;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(
      _operation(transport.requests.single).operationId,
      (record['request'] as Map)['operationId'],
    );
  });

  test('failed pending removal retries without rotating a finalized identity',
      () async {
    await confirm();
    storage.failPendingRemoval = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final actor = prefs.getString('restage.analytics.anonymous_id');
    storage.failPendingRemoval = false;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(
      transport.requests.last.canonicalBytes,
      transport.requests.first.canonicalBytes,
    );
  });

  test('failed assignment cleanup resumes the marked actor after restart',
      () async {
    final old = await confirm();
    storage.failAssignmentRemoval = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final markedActor =
        (jsonDecode(pendingRecords().single) as Map)['resetActor'];
    expect(markedActor, prefs.getString('restage.analytics.anonymous_id'));
    final first = transport.requests.single.canonicalBytes;
    storage.failAssignmentRemoval = false;
    await Restage.debugResetAndWait();
    await prefs.reload();
    transport = _Transport();
    configure();
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    await prefs.reload();
    expect(prefs.getString('restage.analytics.anonymous_id'), markedActor);
    expect(transport.requests.single.canonicalBytes, first);
    expect(pendingRecords(), isEmpty);
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(
      next.registration!.registrationNonce,
      isNot(old.registration!.registrationNonce),
    );
  });

  test('failed actor persistence retries the marked transition after restart',
      () async {
    await confirm();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    storage.failActorWrite = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final markedActor =
        (jsonDecode(pendingRecords().single) as Map)['resetActor'];
    final durable = await storage.getAll();
    expect(durable['flutter.restage.analytics.anonymous_id'], actor);
    final first = transport.requests.single.canonicalBytes;
    storage.failActorWrite = false;
    await Restage.debugResetAndWait();
    await prefs.reload();
    transport = _Transport();
    configure();
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    await prefs.reload();
    expect(prefs.getString('restage.analytics.anonymous_id'), markedActor);
    expect(transport.requests.single.canonicalBytes, first);
    expect(pendingRecords(), isEmpty);
  });

  test('marked retry preserves an unrelated newer actor and assignment',
      () async {
    await confirm();
    storage.failPendingRemoval = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    storage.failPendingRemoval = false;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    final next = await confirm();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(next.isCurrent, isTrue);
    expect(
      await SurfaceAssignmentKeyProvider.resolveLocal(),
      'ic1.${'a' * 64}',
    );
    expect(pendingRecords(), isEmpty);
  });

  test('durable identity reset reports failed repair after a newer reset',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var blockNextLookup = true;
    var nextId = 0;
    final identity = AnalyticsIdentity(
      prefsProvider: () async {
        if (blockNextLookup) {
          blockNextLookup = false;
          entered.complete();
          await release.future;
        }
        return prefs;
      },
      newId: () => 'actor.${++nextId}',
    );
    final pending = identity.reset(requirePersistence: true);
    await entered.future;
    await identity.reset();
    final newerActor = identity.cachedAnonymousId;
    storage.failActorWrite = true;
    final failure = expectLater(pending, throwsStateError);
    release.complete();
    await failure;
    expect(identity.cachedAnonymousId, newerActor);
    storage.failActorWrite = false;
    await identity.persistCurrent();
  });

  test('completion rotates the populated native registration tuple', () async {
    await SurfaceAssignmentPersistence.forget();
    final oldNonce =
        base64UrlEncode(List<int>.filled(32, 1)).replaceAll('=', '');
    final newNonce =
        base64UrlEncode(List<int>.filled(32, 2)).replaceAll('=', '');
    NativeFacts.reset();
    NativeFacts.debugFacts = {
      'registrationNonce': oldNonce,
      'registrationCreatedAtMicros': 100,
    };
    var resets = 0;
    NativeFacts.debugResetRegistration = () {
      resets++;
      return (nonce: newNonce, createdAtMicros: 200);
    };
    configure();
    final old = await confirm();
    expect(old.registration!.registrationNonce, oldNonce);
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(resets, 1);
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(next.registration!.registrationNonce, newNonce);
    expect(next.registration!.registrationCreatedAtMicros, 200);
    expect(next.assignmentKey, isNull);
  });

  test('failed native rotation retains retry authority', () async {
    await SurfaceAssignmentPersistence.forget();
    final oldNonce =
        base64UrlEncode(List<int>.filled(32, 1)).replaceAll('=', '');
    final newNonce =
        base64UrlEncode(List<int>.filled(32, 2)).replaceAll('=', '');
    NativeFacts.reset();
    NativeFacts.debugFacts = {
      'registrationNonce': oldNonce,
      'registrationCreatedAtMicros': 100,
    };
    NativeFacts.debugResetRegistration =
        () => (nonce: oldNonce, createdAtMicros: 100);
    configure();
    await confirm();
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(pendingRecords(), hasLength(1));
    final actor = prefs.getString('restage.analytics.anonymous_id');
    NativeFacts.debugResetRegistration =
        () => (nonce: newNonce, createdAtMicros: 200);
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(
      (await SurfaceAssignmentKeyProvider.captureLease())
          .registration!
          .registrationNonce,
      newNonce,
    );
    expect(
      transport.requests.last.canonicalBytes,
      transport.requests.first.canonicalBytes,
    );
  });

  test('pending removal failure preserves new enrollment on retry', () async {
    await confirm();
    storage.failPendingRemoval = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final durable = await storage.getAll();
    final pending = durable.entries
        .singleWhere((entry) => entry.key.contains('restage.installErasure.'));
    expect((jsonDecode(pending.value as String) as Map)['finalized'], isTrue);
    final newer = await confirm(handle: 'ic1.${'b' * 64}');
    final actor = prefs.getString('restage.analytics.anonymous_id');
    storage.failPendingRemoval = false;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(newer.isCurrent, isTrue);
    expect(
      await SurfaceAssignmentKeyProvider.resolveLocal(),
      'ic1.${'b' * 64}',
    );
    expect(
      transport.requests.last.canonicalBytes,
      transport.requests.first.canonicalBytes,
    );
  });

  test('finalized retry preserves persisted enrollment after restart',
      () async {
    await confirm();
    storage.failPendingRemoval = true;
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.failed);
    final newer = await confirm(handle: 'ic1.${'b' * 64}');
    final actor = prefs.getString('restage.analytics.anonymous_id');
    final first = transport.requests.single.canonicalBytes;
    storage.failPendingRemoval = false;
    await Restage.debugResetAndWait();
    await prefs.reload();
    transport = _Transport();
    configure();
    expect((await Restage.privacy.request()).status,
        RestagePrivacyCoordinatorStatus.completed);
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    expect(next.registration!.registrationNonce,
        newer.registration!.registrationNonce);
    expect(next.assignmentKey, 'ic1.${'b' * 64}');
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(transport.requests.single.canonicalBytes, first);
  });

  test('failed finalization marker keeps enrollment fenced until retry',
      () async {
    await confirm();
    storage.failFinalizedWrite = true;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    final actor = prefs.getString('restage.analytics.anonymous_id');
    expect(
      (await SurfaceAssignmentKeyProvider.captureLease()).registration,
      isNull,
    );
    storage.failFinalizedWrite = false;
    expect(
      (await Restage.privacy.request()).status,
      RestagePrivacyCoordinatorStatus.completed,
    );
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(
      (await SurfaceAssignmentKeyProvider.captureLease()).registration,
      isNotNull,
    );
    expect(pendingRecords(), isEmpty);
  });

  test('completion awaits durable assignment cleanup', () async {
    await confirm();
    storage.removalEntered = Completer<void>();
    storage.releaseRemoval = Completer<void>();
    var completed = false;
    final pending = Restage.privacy.request().then((result) {
      completed = true;
      return result;
    });
    await storage.removalEntered!.future;
    expect(completed, isFalse);
    expect(pendingRecords(), hasLength(1));
    storage.releaseRemoval!.complete();
    expect((await pending).status, RestagePrivacyCoordinatorStatus.completed);
    expect(pendingRecords(), isEmpty);
  });

  test('late receipt after reconfiguration keeps the new scope intact',
      () async {
    await confirm();
    final entered = Completer<RestagePrivacyRequestV1>();
    final response = Completer<RestagePrivacyReceiptV1>();
    transport.onRequest = (request) {
      entered.complete(request);
      return response.future;
    };
    final pending = Restage.privacy.request();
    final request = await entered.future;
    configure(apiKey: 'rs_pk_other');
    final next = await SurfaceAssignmentKeyProvider.captureLease();
    final actor = prefs.getString('restage.analytics.anonymous_id');
    response.complete(_completed(request));
    expect((await pending).status, RestagePrivacyCoordinatorStatus.failed);
    expect(prefs.getString('restage.analytics.anonymous_id'), actor);
    expect(next.isCurrent, isTrue);
    expect(pendingRecords(), hasLength(1));
  });

  test('explicit privacy request retains its behavior', () async {
    final old = await confirm();
    final request = RestagePrivacyRequestV1(
      targets: RestagePrivacyTargets.commerce,
      action: RestagePrivacyAction.export,
      authorities: [
        RestagePrivacyDomainAuthority(
          domain: RestagePrivacyDomain.commerce,
          requestCanonicalBytes: utf8.encode('opaque.host.authority'),
        ),
      ],
    );
    transport.onRequest = (sent) async {
      expect(identical(sent, request), isTrue);
      return unavailablePrivacyReceipt(sent);
    };
    expect(
      (await Restage.privacy.request(request)).status,
      RestagePrivacyCoordinatorStatus.failed,
    );
    expect(old.isCurrent, isTrue);
    expect(pendingRecords(), isEmpty);
  });
}

MeasurementInstallErasureRequestV1 _operation(
  RestagePrivacyRequestV1 request,
) =>
    MeasurementInstallErasureRequestV1.fromCanonicalBytes(
      request.authorities.single.requestCanonicalBytes,
    );

RestagePrivacyReceiptV1 _completed(
  RestagePrivacyRequestV1 request, {
  String? operationId,
}) {
  final operation = _operation(request);
  final receipt = MeasurementInstallErasureReceiptV1(
    operationId: operationId ?? operation.operationId,
    target: TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(2),
      environmentTargetId: EnvironmentTargetId(3),
      namedEnvironmentId: NamedEnvironmentId(4),
      runtimePlane: RuntimePlane.live,
    ),
    completedAtServerTimeMicros: 100,
  );
  return RestagePrivacyReceiptV1(
    targets: request.targets,
    action: request.action,
    correlationId: request.correlationId,
    status: RestagePrivacyCoordinatorStatus.completed,
    domainResults: [
      RestagePrivacyDomainResult.withReceipt(
        RestagePrivacyDomainReceipt(
          domain: RestagePrivacyDomain.measurement,
          action: RestagePrivacyAction.delete,
          status: RestagePrivacyDomainStatus.completed,
          operationId: operation.operationId,
          receiptCanonicalBytes: receipt.canonicalBytes,
        ),
      ),
    ],
  );
}

final class _Transport implements RestageGovernedMeasurementTransport {
  final requests = <RestagePrivacyRequestV1>[];
  Future<RestagePrivacyReceiptV1> Function(RestagePrivacyRequestV1) onRequest =
      (request) async => _completed(request);

  @override
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  ) {
    requests.add(request);
    return onRequest(request);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected governed operation');
}

final class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.empty();
  int registrationWrites = 0;
  bool failPendingWrite = false;
  bool failPendingRemoval = false;
  bool failAssignmentRemoval = false;
  bool failActorWrite = false;
  bool failFinalizedWrite = false;
  Completer<void>? removalEntered;
  Completer<void>? releaseRemoval;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.contains('restage.assignmentRegistration.')) registrationWrites++;
    if (failPendingWrite && key.contains('restage.installErasure.')) {
      return false;
    }
    if (failFinalizedWrite &&
        key.contains('restage.installErasure.') &&
        (jsonDecode(value as String) as Map)['finalized'] == true) {
      return false;
    }
    if (failActorWrite && key.endsWith('restage.analytics.anonymous_id')) {
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (failPendingRemoval && key.contains('restage.installErasure.')) {
      return false;
    }
    if (failAssignmentRemoval &&
        key.contains('restage.assignmentRegistration.')) {
      return false;
    }
    if (key.contains('restage.assignmentRegistration.') &&
        removalEntered != null) {
      if (!removalEntered!.isCompleted) removalEntered!.complete();
      await releaseRemoval!.future;
    }
    return super.remove(key);
  }
}

const _privacyDisabledMessage = '[restage] Restage.privacy.request is disabled '
    'because no governed transport is configured. Try checking apiKey, baseUrl '
    'and governedMeasurementTransportEnabled in Restage.configure, or supplying '
    'governedMeasurementTransport.';

List<String> _capturePrivacyWarnings() {
  final messages = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) messages.add(message);
  };
  addTearDown(() => debugPrint = original);
  return messages;
}
