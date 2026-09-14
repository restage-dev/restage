import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_analytics_identity_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/canonical_assignment_fixture.dart';
import 'surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_screen';
const _meteringKey = 'd9428888-122b-4b0b-8b7f-3e23441121e8';

void main() {
  setUp(resetSurfaceScreenTestState);

  tearDown(Restage.debugReset);

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
    final assignment = canonicalAssignmentFixture();
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
            ...SurfaceScreenDeliveryDescriptorV1Codec.encode(
              fixture.delivery(hostedBlob: hostedBlob, publishedRevision: 8),
            ),
            if (assignmentKey == 'assignment-a')
              'assignment': assignment.toJson(),
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
      measurementPublicationBindingReferenceFor(first),
      bindingReference,
    );
    expect(measurementExperimentAssignmentFor(first), assignment);
    expect(first.contentHash, isNot(fixture.contentHash));
    expect(second.cacheHit, isFalse);
    expect(
      measurementPublicationBindingReferenceFor(second),
      bindingReference,
    );
    expect(measurementExperimentAssignmentFor(second), assignment);
    expect(measurementExperimentAssignmentFor(otherAssignment), isNull);
    expect(measurementExperimentAssignmentFor(unassigned), isNull);
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
