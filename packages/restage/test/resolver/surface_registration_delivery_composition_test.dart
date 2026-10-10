import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_request_inputs.dart';
import 'package:restage/src/resolver/delivery_input_budget.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/canonical_assignment_fixture.dart';
import '../support/hosted_artifact_delivery.dart';

final _handle = 'ic1.${'a' * 64}';
const _surface = 'paywall';
const _slug = 'notice';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('composition');
  });
  tearDown(() {
    SurfaceAssignmentKeyProvider.clear();
    SurfaceCanonicalCarrierProvider.clear();
  });

  test('keyless prefetch omits every assignment-enabling field', () async {
    final store = _store();
    _install(store);
    final requests = <Map<String, dynamic>>[];
    final client = _client(requests);
    final prefetched = await client.fetchSurface(
      surfaceType: _surface,
      surfaceSlug: _slug,
      sendAssignmentKey: false,
    );
    expect(prefetched, isNotNull);
    _expectKeyless(requests.single);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);

    final measured = await client.fetchSurface(
      surfaceType: _surface,
      surfaceSlug: _slug,
    );
    expect(requests.last['registrationNonce'], isA<String>());
    expect(storedSurfaceAssignmentKey(measured!.stored!), _handle);
    expect(storedSurfaceRegistrationFingerprint(measured.stored!),
        (await store.capture())!.fingerprint);
  });

  test('keyless fetch scrubs registration from supplied keyed inputs',
      () async {
    _install(_store());
    final requests = <Map<String, dynamic>>[];
    await DeliveryInputBudget.run((budget) async {
      final inputs = await SurfaceRequestInputs.gather(
        budget: budget,
        surface: _surface,
        slug: _slug,
      );
      expect(inputs.lease.registration, isNotNull);
      expect(
          await _client(requests).fetchSurface(
            surfaceType: _surface,
            surfaceSlug: _slug,
            inputs: inputs,
            sendAssignmentKey: false,
          ),
          isNotNull);
    });
    _expectKeyless(requests.single);
  });

  test('supplied inputs retain the deadline through request publication',
      () async {
    _install(_store());
    final deadline = Completer<void>();
    final requests = <Map<String, dynamic>>[];
    await DeliveryInputBudget.run((budget) async {
      final inputs = await SurfaceRequestInputs.gather(
        budget: budget,
        surface: _surface,
        slug: _slug,
        keyDeadline: deadline.future,
      );
      expect(inputs.lease.registration, isNotNull);
      deadline.complete();
      await Future<void>.value();
      expect(
          await _client(requests).fetchSurface(
            surfaceType: _surface,
            surfaceSlug: _slug,
            inputs: inputs,
          ),
          isNotNull);
    });
    _expectKeyless(requests.single);
  });

  test('a deadline supplied at fetch scrubs previously gathered inputs',
      () async {
    _install(_store());
    final requests = <Map<String, dynamic>>[];
    await DeliveryInputBudget.run((budget) async {
      final inputs = await SurfaceRequestInputs.gather(
        budget: budget,
        surface: _surface,
        slug: _slug,
      );
      expect(
          await _client(requests).fetchSurface(
            surfaceType: _surface,
            surfaceSlug: _slug,
            inputs: inputs,
            keyDeadline: Future<void>.value(),
          ),
          isNotNull);
    });
    _expectKeyless(requests.single);
  });

  test('a tuple still loading at the deadline is omitted from background fetch',
      () async {
    final pending = Completer<SurfaceRegistrationAttempt?>();
    SurfaceAssignmentKeyProvider.install(
      key: () => null,
      identityGeneration: () => 0,
      registration: () => pending.future,
    );
    final requests = <Map<String, dynamic>>[];
    final result = await _client(requests).fetchSurface(
      surfaceType: _surface,
      surfaceSlug: _slug,
      keyDeadline: Future<void>.value(),
    );
    expect(result, isNotNull);
    _expectKeyless(requests.single);
  });

  test('optional input delay drops a previously ready tuple after the deadline',
      () async {
    final store = _store();
    _install(store);
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    expect(lease.registration, isNotNull);
    final requests = <Map<String, dynamic>>[];
    final result = await _client(requests).fetchSurface(
      surfaceType: _surface,
      surfaceSlug: _slug,
      registrationLease: lease,
      keyDeadline: Future<void>.value(),
    );
    expect(result, isNotNull);
    _expectKeyless(requests.single);
  });

  test('cached assignments keep their original tuple and local deadline',
      () async {
    var now = DateTime.now().microsecondsSinceEpoch;
    final store = _store(nowMicros: () => now);
    _install(store);
    final requests = <Map<String, dynamic>>[];
    final fresh = (await _client(requests, assigned: true).fetchSurface(
      surfaceType: _surface,
      surfaceSlug: _slug,
    ))!;
    final stored = fresh.stored!;
    final before = await _persistedDeadline();
    now += Duration.microsecondsPerHour;
    final replay = (await replayStoredSurface(stored))!;
    final resolved = attachMeasurementPublicationBindingReference(
      Object(),
      null,
      canonicalExperimentAssignment: replay.canonicalExperimentAssignment,
    );
    expect(measurementRegistrationFingerprintFor(resolved),
        (await store.capture())!.fingerprint);
    expect((await _identity(stored, replay)).reusable, isTrue);
    expect(await _persistedDeadline(), before);

    final changed = StoredSurface(
      descriptorJson: stored.descriptorJson,
      artifactBytes: stored.artifactBytes,
      sidecar: {...stored.sidecar, 'registrationFingerprint': 'f' * 64},
    );
    expect((await _identity(changed, replay)).reusable, isFalse);
    now = before;
    expect((await _identity(stored, replay)).reusable, isFalse);
    expect((await store.capture())!.credentialHandle, isNull);
  });

  test('stale folded response cannot confirm a new identity or cache its arm',
      () async {
    var generation = 0;
    final store = _store(identityGeneration: () => generation);
    _install(store);
    final firstRequest = Completer<void>();
    final responseReady = Completer<void>();
    final requests = <Map<String, dynamic>>[];
    final pending = _client(requests, assigned: true, beforeResponse: () async {
      firstRequest.complete();
      await responseReady.future;
    }).fetchSurface(surfaceType: _surface, surfaceSlug: _slug);
    await firstRequest.future;
    generation++;
    final current = (await store.capture())!;
    responseReady.complete();
    expect(await pending, isNull);
    expect(current.credentialHandle, isNull);
    expect(
        (await store.capture())!.registrationNonce, current.registrationNonce);
  });
}

Future<({bool reusable, String? key, SurfaceAssignmentResolutionLease? lease})>
    _identity(StoredSurface stored, SurfaceFetchResult replay) =>
        storedDeliveryIdentity(
          stored: stored,
          assignment: replay.canonicalExperimentAssignment,
          surface: _surface,
          slug: _slug,
        );

Future<int> _persistedDeadline() async {
  final prefs = await SharedPreferences.getInstance();
  final key = prefs
      .getKeys()
      .singleWhere((key) => key.startsWith('restage.assignmentRegistration.'));
  return (jsonDecode(prefs.getString(key)!) as Map)['localExpiresAtMicros']
      as int;
}

void _expectKeyless(Map<String, dynamic> request) {
  for (final key in [
    'assignmentKey',
    'assignmentCanonicalBase64',
    'registrationNonce',
    'registrationCreatedAtMicros',
  ]) {
    expect(request, isNot(contains(key)));
  }
}

SurfaceAssignmentCredentialStore _store({
  int Function()? nowMicros,
  int Function()? identityGeneration,
}) =>
    SurfaceAssignmentCredentialStore(
      namespace: 'composition',
      actor: () async => 'actor-${identityGeneration?.call() ?? 0}',
      identityGeneration: identityGeneration ?? () => 0,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
      nowMicros: nowMicros,
    );

void _install(SurfaceAssignmentCredentialStore store) {
  SurfaceAssignmentKeyProvider.install(
    key: store.resolve,
    localKey: store.resolveLocal,
    identityGeneration: () => store.generation,
    registration: store.capture,
    confirmedKey: () => store.currentHandle,
    confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
        store.confirm(
      attempt: attempt,
      localRequestStartMicros: start,
      credentialHandle: handle,
      expiresAtMicros: expiry,
      serverNowMicros: serverNow,
    ),
    refuseRegistration: store.refuse,
  );
}

RestageRpcClient _client(
  List<Map<String, dynamic>> requests, {
  bool assigned = false,
  Future<void> Function()? beforeResponse,
}) {
  final delivery = HostedArtifactFixture();
  final envelope = SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: Surface.paywall,
    surfaceSlug: _slug,
    version: 1,
    minClient: 1,
    payload:
        BlobSurfacePayload(blob: Uint8List.fromList([1, 2, 3]), minClient: 1),
    publishedAt: DateTime.utc(2026),
  ));
  return RestageRpcClient(
    baseUrl: 'https://edge.example.test',
    apiKey: 'rs_pk_test',
    httpClient: delivery.client((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      await beforeResponse?.call();
      final now = DateTime.now().microsecondsSinceEpoch;
      return http.Response(
          jsonEncode({
            ...delivery.describeEnvelope(envelope),
            if (body.containsKey('registrationNonce')) ...{
              'credentialHandle': _handle,
              'expiresAtMicros': now + 30 * Duration.microsecondsPerDay,
              'serverNowMicros': now,
            },
            if (assigned) 'assignment': canonicalAssignmentFixture().toJson(),
          }),
          200);
    }),
  );
}
