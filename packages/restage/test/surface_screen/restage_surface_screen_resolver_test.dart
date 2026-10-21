import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_store_key.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/delivery_input_budget.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_analytics_identity_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' show RemoteWidget;
import 'package:shared_preferences/shared_preferences.dart';

import '../measurement/admitted_bundled_publication_fixture.dart';
import '../measurement/measurement_host_construction_test_support.dart';
import '../support/canonical_assignment_fixture.dart';
import 'surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_screen';
const _meteringKey = 'd9428888-122b-4b0b-8b7f-3e23441121e8';

void main() {
  setUp(resetSurfaceScreenTestState);

  tearDown(Restage.debugReset);

  test(
      'typed request drops held assignment when optional input outlives the render deadline',
      () async {
    final deadline = Completer<void>();
    final heldReady = Completer<void>();
    final inputStarted = Completer<void>();
    final optionalInput = Completer<String?>();
    var keyReads = 0;
    final readyKey = 'ic1.${'a' * 64}';
    SurfaceAssignmentKeyProvider.install(
      key: () => readyKey,
      identityGeneration: () => 0,
      confirmedKey: () => readyKey,
      registration: () async {
        keyReads++;
        return SurfaceRegistrationAttempt(
          registrationNonce: 'b' * 64,
          registrationCreatedAtMicros: 1000,
          generation: 0,
          fingerprint: 'c' * 64,
          credentialHandle: readyKey,
        );
      },
    );
    final assignment = canonicalAssignmentFixture();
    final carrier = base64UrlEncode(
      utf8.encode(
          CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
              assignment)),
    ).replaceAll('=', '');
    SurfaceCanonicalCarrierProvider.installHeldAssignment(() {
      heldReady.complete();
      return carrier;
    });
    SurfaceAnalyticsIdentityProvider.install(() {
      inputStarted.complete();
      return optionalInput.future;
    });
    final fixture = stringScreenFixture();
    final bodies = <Map<String, dynamic>>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          expect(request.url.path, '/sdk/v1/surface');
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );
    final pending = resolver.fresh(
      resolver.storeKeyFor(fixture.ref),
      sendAssignmentKey: true,
      keyDeadline: deadline.future,
    );
    await inputStarted.future;
    await heldReady.future;
    expect(keyReads, 1);
    expect(bodies, isEmpty);
    deadline.complete();
    await Future<void>.value();
    optionalInput.complete('12345678-1234-4234-8234-123456789abc');
    expect(await pending, isNull);

    expect(bodies, hasLength(1));
    expect(bodies.single['surface'], fixture.ref.surface.wireName);
    expect(bodies.single['slug'], fixture.ref.slug);
    expect(bodies.single['contractVersion'], fixture.ref.contractVersion);
    for (final key in [
      'assignmentKey',
      'assignmentCanonicalBase64',
      'registrationNonce',
      'registrationCreatedAtMicros',
    ]) {
      expect(bodies.single, isNot(contains(key)), reason: key);
    }
  });

  test('a screen key issued no ref is not fetched', () async {
    final fixture = stringScreenFixture();
    final requests = <http.Request>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );
    const key = SurfaceStoreKey(
      scope: '0123456789abcdef',
      surfaceType: 'screen',
      slug: 'unknown',
      contractVersion: 1,
    );

    final fresh = await racedResolverOf<ResolvedSurfaceScreen>(resolver)!
        .fresh(key, sendAssignmentKey: false);

    expect(fresh, isNull);
    expect(requests, isEmpty);
  });

  test('screens are stored under the screen kind and report their surface',
      () async {
    final reports = <SurfaceResolutionReport>[];
    Restage.configure(
      apiKey: _apiKey,
      analyticsEnabled: false,
      measurementEnabled: false,
      onSurfaceResolution: reports.add,
    );
    final fixture = stringScreenFixture();
    final hostedBlob = rfwScreenBlob(text: 'Hosted screen', event: 'tap');
    var online = true;
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async => online
            ? http.Response(
                jsonEncode(SurfaceScreenDeliveryDescriptorV1Codec.encode(
                  fixture.delivery(
                      hostedBlob: hostedBlob, publishedRevision: 8),
                )),
                200,
              )
            : http.Response('unavailable', 503)),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final key = resolver.storeKeyFor(fixture.ref);
    final first = await resolver.resolve(fixture.ref);
    online = false;
    final held = await resolver.resolve(fixture.ref);

    expect(key.surfaceType, SurfaceSourceKind.screen.wireName);
    expect(key.contractVersion, fixture.ref.contractVersion);
    expect(await resolver.store.read(key), isNotNull);
    expect(first.cacheHit, isFalse);
    expect(held.origin, SurfaceScreenOrigin.hosted);
    expect(held.cacheHit, isTrue);
    expect(reports.map((report) => report.surfaceType),
        everyElement(fixture.ref.surface));
    expect(reports.map((report) => report.source), [
      SurfaceResolutionSource.fresh,
      SurfaceResolutionSource.holdLastGood,
    ]);

    final raced = racedResolverOf<ResolvedSurfaceScreen>(resolver)!;
    await raced.forgetStored(key);
    final bundled = await resolver.resolve(fixture.ref);
    expect(bundled.origin, SurfaceScreenOrigin.bundled);
  });

  test('an in-flight typed resolve omits the identifier after analytics is off',
      () async {
    SharedPreferences.setMockInitialValues({});
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      measurementEnabled: false,
    );
    await pumpEventQueue();
    final started = Completer<void>();
    final identifier = Completer<String?>();
    SurfaceAnalyticsIdentityProvider.install(() {
      started.complete();
      return identifier.future;
    });
    final fixture = stringScreenFixture();
    final bodies = <Map<String, dynamic>>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final pending = resolver.resolve(fixture.ref);
    await started.future;
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      analyticsEnabled: false,
    );
    identifier.complete('12345678-1234-4234-8234-123456789abc');
    final resolved = await pending;

    expect(resolved.origin, SurfaceScreenOrigin.bundled);
    expect(bodies, hasLength(1));
    expect(bodies.single, isNot(contains('analyticsAnonymousId')));
  });

  test('each typed attempt reads the identifier under its own assignment lease',
      () async {
    const firstId = '12345678-1234-4234-8234-123456789abc';
    const secondId = '22345678-1234-4234-8234-123456789abc';
    SurfaceAssignmentKeyProvider.current = () => 'assignment-a';
    var reads = 0;
    SurfaceAnalyticsIdentityProvider.install(() async {
      reads += 1;
      return reads == 1 ? firstId : secondId;
    });
    final fixture = stringScreenFixture();
    final bodies = <Map<String, dynamic>>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            SurfaceAssignmentKeyProvider.current = () => 'assignment-b';
          }
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    await resolver.resolve(fixture.ref);

    expect(reads, 2);
    expect(bodies.map((body) => body['assignmentKey']),
        ['assignment-a', 'assignment-b']);
    expect(bodies.map((body) => body['analyticsAnonymousId']),
        [firstId, secondId]);
  });

  test('an identity retry reads its inputs under a fresh deadline', () async {
    SurfaceAssignmentKeyProvider.current = () => 'assignment-a';
    final fixture = stringScreenFixture();
    final bodies = <Map<String, dynamic>>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            // The first attempt outlives its input deadline, then loses its
            // identity; the retry's key answers only after a turn.
            await Future<void>.delayed(
              DeliveryInputBudget.defaultTotal +
                  const Duration(milliseconds: 100),
            );
            SurfaceAssignmentKeyProvider.current =
                () => Future<String?>.delayed(
                      const Duration(milliseconds: 20),
                      () => 'assignment-b',
                    );
          }
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    await resolver.resolve(fixture.ref);

    expect(bodies.map((body) => body['assignmentKey']),
        ['assignment-a', 'assignment-b']);
  });

  test(
      'typed requests omit an identifier when its provider changes after reading',
      () async {
    const identifier = '12345678-1234-4234-8234-123456789abc';
    SurfaceAnalyticsIdentityProvider.install(() async => identifier);
    SurfaceCanonicalCarrierProvider.installHeldAssignment(() {
      SurfaceAnalyticsIdentityProvider.install(() async => identifier);
      return null;
    });
    final fixture = stringScreenFixture();
    final bodies = <Map<String, dynamic>>[];
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204);
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    await resolver.resolve(fixture.ref);

    expect(bodies, hasLength(1));
    expect(bodies.single, isNot(contains('analyticsAnonymousId')));
  });

  test(
      'decides freshly on every resolve and forwards metering and assignment context',
      () async {
    final fixture = stringScreenFixture();
    await _installMeteringKey();
    final bindingReference = _bindingReference('a');
    final servedAssignment = _servedAssignment();
    String? assignmentKey = 'assignment-a';
    SurfaceAssignmentKeyProvider.current = () => assignmentKey;
    final requests = <http.Request>[];
    final hostedBlob = rfwScreenBlob(text: 'Hosted screen', event: 'tap');
    final client = RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: fixture.hostedDelivery.client((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            ...fixture
                .delivery(
                  hostedBlob: hostedBlob,
                  publishedRevision: 8,
                )
                .toJson(),
            'assignment': servedAssignment.toJson(),
          }),
          200,
          headers: {
            'Restage-Measurement-Publication-Binding-V1':
                _bindingHeader(bindingReference),
          },
        );
      }),
    );
    final resolver = _resolver(
      client: client,
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final first = await resolver.resolve(fixture.ref);
    final second = await resolver.resolve(fixture.ref);
    assignmentKey = 'assignment-b';
    final otherAssignment = await resolver.resolve(fixture.ref);
    assignmentKey = null;
    final unassigned = await resolver.resolve(fixture.ref);

    expect(first.origin, SurfaceScreenOrigin.hosted);
    expect(first.cacheHit, isFalse);
    expect(
      first.assignment,
      projectSurfaceAssignment(servedAssignment),
    );
    expect(measurementExperimentAssignmentFor(first), servedAssignment);
    expect(
      measurementPublicationBindingReferenceFor(first),
      bindingReference,
    );
    expect(first.contentHash, isNot(fixture.contentHash));
    expect(second.cacheHit, isFalse);
    expect(second.assignment, first.assignment);
    expect(measurementExperimentAssignmentFor(second), servedAssignment);
    expect(
      measurementPublicationBindingReferenceFor(second),
      bindingReference,
    );
    expect(otherAssignment.cacheHit, isFalse);
    expect(unassigned.cacheHit, isFalse);
    expect(requests, hasLength(4));

    final bodies = requests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList();
    expect(
      bodies.map((body) => body['assignmentKey']),
      <Object?>['assignment-a', 'assignment-a', 'assignment-b', null],
    );
    expect(
      bodies.map((body) => body['meteringKey']),
      <Object?>[_meteringKey, _meteringKey, _meteringKey, _meteringKey],
    );
    expect(
      bodies.every((body) =>
          body['surface'] == fixture.ref.surface.wireName &&
          body['slug'] == fixture.ref.slug &&
          body['contractVersion'] == fixture.ref.contractVersion),
      isTrue,
    );
  });

  test('uses only the exact bundled closure for ordinary absence', () async {
    final fixture = stringScreenFixture();
    for (final statusCode in <int>[204, 404]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = RestageScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.production,
        baseUrl: _baseUrl,
        assetFallback: fallback,
        rpcClientProvider: () => RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: fixture.hostedDelivery
              .client((_) async => http.Response('', statusCode)),
        ),
      );

      final resolved = await resolver.resolve(fixture.ref);

      expect(resolved.origin, SurfaceScreenOrigin.bundled);
      expect(resolved.contentHash, fixture.contentHash);
      expect(fallback.calls, 1, reason: 'status $statusCode');
    }
  });

  test('uses only the exact bundled closure for retryable availability',
      () async {
    final fixture = stringScreenFixture();
    for (final statusCode in <int>[408, 429, 500, 502, 503, 504]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: fixture.hostedDelivery.client(
            (_) async => http.Response('unavailable', statusCode),
          ),
        ),
        fallback: fallback,
      );

      final resolved = await resolver.resolve(fixture.ref);

      expect(resolved.origin, SurfaceScreenOrigin.bundled);
      expect(fallback.calls, 1, reason: 'status $statusCode');
    }
  });

  test('uses only the exact bundled closure for I/O and timeout unavailability',
      () async {
    final fixture = stringScreenFixture();
    for (final failure in <Object>[
      http.ClientException('offline'),
      TimeoutException('delivery timed out'),
    ]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: fixture.hostedDelivery.client((_) async => throw failure),
        ),
        fallback: fallback,
      );

      final resolved = await resolver.resolve(fixture.ref);

      expect(resolved.origin, SurfaceScreenOrigin.bundled);
      expect(fallback.calls, 1);
    }
  });

  test('never falls back from an unexpected local delivery failure', () async {
    final fixture = stringScreenFixture();
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery
            .client((_) async => throw StateError('bad client')),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.invalidPayload)),
    );
    expect(fallback.calls, 0);
  });

  test('never falls back from deterministic hosted HTTP rejection', () async {
    final fixture = stringScreenFixture();
    for (final statusCode in <int>[400, 401, 403, 409, 413, 422, 501]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: fixture.hostedDelivery.client(
            (_) async => http.Response('delivery rejected', statusCode),
          ),
        ),
        fallback: fallback,
      );

      await expectLater(
        resolver.resolve(fixture.ref),
        throwsA(_unavailable(SurfaceScreenUnavailableReason.invalidPayload)),
        reason: 'status $statusCode',
      );
      expect(fallback.calls, 0, reason: 'status $statusCode');
    }
  });

  test('rejects an altered bundled closure instead of accepting a fallback',
      () async {
    final fixture = stringScreenFixture();
    final altered = stringScreenFixture(
      slug: fixture.ref.slug,
      text: 'Different bundled closure',
    );
    final fallback = FixedBundledScreenResolver(altered.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient:
            fixture.hostedDelivery.client((_) async => http.Response('', 404)),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.contractMismatch)),
    );
    expect(fallback.calls, 1);
  });

  test('never falls back from a malformed present hosted response', () async {
    final fixture = stringScreenFixture();
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery
            .client((_) async => http.Response('{}', 200)),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.invalidPayload)),
    );
    expect(fallback.calls, 0);
  });

  test('strictly refuses a hosted response with the retired assignment key',
      () {
    final fixture = stringScreenFixture();
    final response = <String, Object?>{
      ...fixture.delivery().toJson(),
      'assignment': <String, Object?>{
        'experimentId': 'retired-experiment',
        'variantId': 'retired-variant',
        'experimentEpoch': 1,
      },
    };

    expect(
      () => SurfaceScreenDeliveryDescriptorV1Codec.decode(response),
      throwsA(isA<FormatException>()),
    );
  });

  test('never falls back from a present contract-version mismatch', () async {
    final fixture = stringScreenFixture();
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final response = fixture.delivery(contractVersion: 2);
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client(
          (_) async => http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
                response),
            200,
          ),
        ),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.contractMismatch)),
    );
    expect(fallback.calls, 0);
  });

  test('never falls back from hosted capability rejection', () async {
    final fixture = stringScreenFixture(
      capabilities: CapabilityManifest(
        builtInFloor: 999999,
        requiredLibraries: const [],
      ),
    );
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client(
          (_) async => http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(),
            ),
            200,
          ),
        ),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.incompatible)),
    );
    expect(fallback.calls, 0);
  });

  test('accepts hosted required libraries that match by value', () async {
    // The hosted document's library list arrives decoded from the wire, so it
    // is never the same list instance the generated contract holds. Comparing
    // the two by identity rejects every hosted screen that requires a custom
    // library, so this fixture deliberately requires one.
    const namespace = 'example.custom';
    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom(namespace),
      widgets: const <RestageWidgetFactory>[],
      capabilityVersion: 3,
    );
    final fixture = stringScreenFixture(
      capabilities: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const <LibraryRequirement>[
          LibraryRequirement(namespace: namespace, minVersion: 2),
        ],
      ),
    );
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client(
          (_) async => http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(),
            ),
            200,
          ),
        ),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final resolved = await resolver.resolve(fixture.ref);

    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(resolved.capabilities.requiredLibraries, hasLength(1));
  });

  test('accepts hosted content whose payload carries local seeds', () async {
    final fixture = stringScreenFixture(
      capabilities: CapabilityManifest(
        builtInFloor: kSurfaceFeatureClientFloor,
        requiredLibraries: const <LibraryRequirement>[],
      ),
    );
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client(
          (_) async => http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(
                localSeeds: const {
                  'OnboardingScreen': {'note': ''},
                },
              ),
            ),
            200,
          ),
        ),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final resolved = await resolver.resolve(fixture.ref);

    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    // The mount validates the same result before rendering it.
    fixture.ref.provenance.validateResolved(resolved);
  });

  test('serves hosted content when the application packages no bundles',
      () async {
    final fixture = stringScreenFixture(packagesBundle: false);
    final fallback = AbsentBundledScreenResolver();
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client(
          (_) async => http.Response(
            SurfaceScreenDeliveryDescriptorV1Codec.encodeCanonicalJson(
              fixture.delivery(publishedRevision: 4),
            ),
            200,
          ),
        ),
      ),
      fallback: fallback,
    );

    final resolved = await resolver.resolve(fixture.ref);

    expect(resolved.origin, SurfaceScreenOrigin.hosted);
    expect(resolved.publishedRevision, 4);
    expect(fallback.calls, 0, reason: 'hosted content never needs a bundle');
  });

  testWidgets(
      'offstage hosted screen waits for paint before public and Measurement presentation ownership',
      (tester) async {
    final fixture = stringScreenFixture(
      blob: rfwSourceBlob('''
import restage.core;
import restage.material;

widget OnboardingScreen = SizedBox(
  width: 240.0,
  height: 160.0,
  child: RestagePager(children: [
    Text(text: "First"),
    Text(text: "Second")
  ])
);
'''),
    );
    final binding = _fixtureBinding();
    final readPort = _AcceptedBindingReadPort(binding);
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: _bindingContext(binding),
      hostedBindingReadPortLookup: () => readPort,
    );
    addTearDown(() => unawaited(harness.close()));
    final servedAssignment = _servedAssignment();
    final deliveryResponse = Completer<http.Response>();
    var deliveryRequests = 0;
    final hostedResolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((_) {
          deliveryRequests += 1;
          return deliveryResponse.future;
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);
    SurfaceAssignmentKeyProvider.current = () => 'assignment-screen';
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    var selectedIndex = 0;
    late StateSetter select;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            select = setState;
            return IndexedStack(
              index: selectedIndex,
              children: <Widget>[
                const SizedBox.expand(),
                RestageScreen<String>(
                  screen: fixture.ref,
                  resolver: hostedResolver,
                  unavailable: const SurfaceScreenUnavailablePolicy.hide(),
                  onEvent: (_) {},
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();
    deliveryResponse.complete(
      http.Response(
        jsonEncode({
          ...fixture.delivery(publishedRevision: 8).toJson(),
          'assignment': servedAssignment.toJson(),
        }),
        200,
        headers: {
          'Restage-Measurement-Publication-Binding-V1':
              _bindingHeader(binding.reference),
        },
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          find.byType(RemoteWidget, skipOffstage: false).evaluate().isNotEmpty,
    );

    final assignment = projectSurfaceAssignment(servedAssignment);
    expect(find.byType(RemoteWidget, skipOffstage: false), findsOneWidget);
    expect(harness.owner.debugActiveSessionCount, 1);
    final assignmentWhileOffstage = Restage.assignmentFor(
      fixture.ref.slug,
      surfaceType: Surface.general,
    );
    expect(harness.worker.activeRegistrations, hasLength(1));
    final workerAssignment = MeasurementExperimentAssignmentV1.fromJson(
      CanonicalJsonCodec.decode(
        harness.worker.activeRegistrations.single
            .experimentAssignmentCanonicalBytes!,
      )! as Map<String, Object?>,
    );
    expect(
      workerAssignment.outcomeLinkCarrier,
      servedAssignment.outcomeLinkCarrier,
    );
    expect(harness.worker.finalizationCalls, 0);
    expect(harness.worker.discardCalls, 0);
    expect(deliveryRequests, 1);

    select(() => selectedIndex = 1);
    await tester.pump();
    await tester.pump();

    expect(
      Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
      assignment,
    );
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final event = events.whereType<PagerPageChanged>().single;
    expect(event.surfaceId, fixture.ref.slug);
    expect(event.surfaceType, Surface.general);
    expect(event.surfaceVersion, '8');
    expect(event.assignment, assignment);
    expect(event.variantId, servedAssignment.armId.value);

    await tester.pumpWidget(const SizedBox());
    await _pumpUntil(tester, () => harness.worker.finalizationCalls == 1);
    expect(assignmentWhileOffstage, isNull);
    expect(harness.worker.finalizationCalls, 1);
    expect(harness.worker.discardCalls, 1);
    expect(
      Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
      assignment,
    );
  });

  testWidgets(
      'reset during standalone screen Measurement opening retires the candidate',
      (tester) async {
    final fixture = stringScreenFixture();
    final binding = _fixtureBinding();
    final readPort = _ControlledBindingReadPort(binding);
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: _bindingContext(binding),
      hostedBindingReadPortLookup: () => readPort,
    );
    addTearDown(() => unawaited(harness.close()));
    final servedAssignment = _servedAssignment();
    final deliveryResponse = Completer<http.Response>();
    var deliveryRequests = 0;
    final hostedResolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.client((_) {
          deliveryRequests += 1;
          return deliveryResponse.future;
        }),
      ),
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);
    var identityGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
        key: () => 'assignment-$identityGeneration',
        identityGeneration: () => identityGeneration);

    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(index: 0, children: [
          const SizedBox.expand(),
          RestageScreen<String>(
            screen: fixture.ref,
            resolver: hostedResolver,
            unavailable: const SurfaceScreenUnavailablePolicy.hide(),
            onEvent: (_) {},
            loadingBuilder: (_) => const Text('screen-loading'),
          )
        ]),
      ),
    );
    await tester.pump();
    deliveryResponse.complete(
      http.Response(
        jsonEncode({
          ...fixture.delivery(publishedRevision: 8).toJson(),
          'assignment': servedAssignment.toJson(),
        }),
        200,
        headers: {
          'Restage-Measurement-Publication-Binding-V1':
              _bindingHeader(binding.reference),
        },
      ),
    );
    await _pumpUntil(tester, () => readPort.references.isNotEmpty);
    await _pumpUntil(
        tester,
        () => find
            .byType(RemoteWidget, skipOffstage: false)
            .evaluate()
            .isNotEmpty);
    expect(readPort.references, <Object?>[binding.reference]);
    expect(find.byType(RemoteWidget, skipOffstage: false), findsOneWidget);
    expect(
        Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
        isNull);

    identityGeneration++;
    Restage.reset();
    readPort.completeAccepted();
    await _pumpFrames(tester);
    expect(deliveryRequests, 1);
    expect(find.byType(RemoteWidget, skipOffstage: false), findsOneWidget);
    expect(
      Restage.assignmentFor(fixture.ref.slug, surfaceType: Surface.general),
      isNull,
    );
    expect(harness.worker.activeSessionIds, isEmpty);
    expect(harness.worker.finalizationCalls, 0);
    expect(harness.worker.discardCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prepaint identity rejection settles on the unavailable floor',
      (tester) async {
    final fixture = stringScreenFixture();
    final resolver = FixedScreenResolver(fixture.hosted());
    final unavailable = <SurfaceScreenUnavailableError>[];
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);

    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          index: 0,
          children: <Widget>[
            const SizedBox.expand(),
            RestageScreen<String>(
              screen: fixture.ref,
              resolver: resolver,
              unavailable: SurfaceScreenUnavailablePolicy.fallback(
                builder: (_, error) =>
                    Text('screen-unavailable:${error.reason.name}'),
              ),
              onUnavailable: unavailable.add,
              onEvent: (_) {},
              loadingBuilder: (_) => const Text('screen-loading'),
            ),
          ],
        ),
      ),
    );
    await _pumpFrames(tester);

    for (var attempt = 0; attempt < 2; attempt += 1) {
      Restage.reset();
      await _pumpFrames(tester);
    }

    Restage.reset();
    await _pumpFrames(tester);

    final resolverCalls = resolver.calls;
    final unavailableSnapshot = List<SurfaceScreenUnavailableError>.of(
      unavailable,
    );
    final unavailableFallbackCount = find
        .text('screen-unavailable:missing', skipOffstage: false)
        .evaluate()
        .length;
    final loadingCount =
        find.text('screen-loading', skipOffstage: false).evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(resolverCalls, 1);
    expect(unavailableSnapshot, hasLength(1));
    expect(
      unavailableSnapshot.single.reason,
      SurfaceScreenUnavailableReason.missing,
    );
    expect(unavailableFallbackCount, 1);
    expect(loadingCount, 0);
  });

  test('fails closed when absent hosted content has no packaged bundle',
      () async {
    final fixture = stringScreenFixture(packagesBundle: false);
    final fallback = AbsentBundledScreenResolver();
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient:
            fixture.hostedDelivery.client((_) async => http.Response('', 404)),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.missing)),
    );
    expect(fallback.calls, 1);
  });

  testWidgets('configuration installs the hosted standalone screen resolver',
      (_) async {
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);

    expect(
      Restage.defaultSurfaceScreenResolver,
      isA<RestageScreenResolver>(),
    );
  });
}

RestageScreenResolver _resolver({
  required RestageRpcClient client,
  required BundledSurfaceScreenResolver fallback,
}) =>
    RestageScreenResolver(
      apiKey: _apiKey,
      environment: RestageEnvironment.production,
      baseUrl: _baseUrl,
      assetFallback: fallback,
      rpcClientProvider: () => client,
    );

Matcher _unavailable(SurfaceScreenUnavailableReason reason) =>
    isA<SurfaceScreenUnavailableError>().having(
      (error) => error.reason,
      'reason',
      reason,
    );

Future<void> _installMeteringKey() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'restage.metering_token': _meteringKey,
  });
  final preferences = await SharedPreferences.getInstance();
  SurfaceMeteringKeyProvider.install(
    store: MeteringTokenStore(prefsProvider: () async => preferences),
  );
}

String _bindingHeader(MeasurementPublicationBindingReferenceV1 reference) =>
    base64UrlEncode(reference.canonicalBytes).replaceAll('=', '');

MeasurementPublicationBindingReferenceV1 _bindingReference(String seed) {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest(seed * 64),
    selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId(
        'authority.screen.resolver.$seed',
      ),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}

CanonicalSurfaceExperimentAssignmentV1 _servedAssignment() =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.screen'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.screen.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.screen.1'),
      armId: ExperimentPublicArmIdV1('arm.screen'),
      outcomeLinkCarrier:
          base64UrlEncode(utf8.encode('outcome.screen')).replaceAll('=', ''),
    );

MeasurementPublicationBindingV1 _fixtureBinding() =>
    AdmittedBundledPublicationFixture.build(includeOrderedCapture: false)
        .binding;

ExactMeasurementPublicationContextRefV1 _bindingContext(
  MeasurementPublicationBindingV1 binding,
) =>
    ExactMeasurementPublicationContextRefV1(
      bindingReference: binding.reference,
      surfaceIdentity: binding.publishedSurfaceRevision.surfaceIdentity,
      surfaceRevisionId: binding.publishedSurfaceRevision.revisionId,
      artifactGraphHash: binding.exactArtifactGraph.canonicalDigest,
      measurementManifestHash:
          binding.completeMeasurementManifest.canonicalDigest,
    );

MeasurementPublicationBindingReadAccepted _acceptedBinding(
  MeasurementPublicationBindingV1 binding,
) =>
    MeasurementPublicationBindingReadAccepted(
      reference: binding.reference,
      binding: binding,
      registeredPublicationAttestation: RegisteredPublicationAttestationV1(
        bindingReference: binding.reference,
        attestationDigest: CanonicalDigest('9' * 64),
      ),
    );

final class _AcceptedBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  _AcceptedBindingReadPort(this.binding);

  final MeasurementPublicationBindingV1 binding;
  final references = <MeasurementPublicationBindingReferenceV1>[];

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) async {
    references.add(bindingReference);
    return _acceptedBinding(binding);
  }
}

final class _ControlledBindingReadPort
    implements MeasurementPublicationBindingReadPort {
  _ControlledBindingReadPort(this.binding);

  final MeasurementPublicationBindingV1 binding;
  final references = <MeasurementPublicationBindingReferenceV1>[];
  final _result = Completer<MeasurementPublicationBindingReadResult>();

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
    MeasurementPublicationBindingReferenceV1 bindingReference,
  ) {
    references.add(bindingReference);
    return _result.future;
  }

  void completeAccepted() => _result.complete(_acceptedBinding(binding));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
) async {
  for (var attempt = 0; attempt < 20 && !predicate(); attempt += 1) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(predicate(), isTrue);
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 20}) async {
  for (var frame = 0; frame < count; frame += 1) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}
