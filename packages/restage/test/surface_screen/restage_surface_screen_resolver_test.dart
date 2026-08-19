import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_screen';
const _meteringKey = 'd9428888-122b-4b0b-8b7f-3e23441121e8';

void main() {
  setUp(resetSurfaceScreenTestState);

  test(
      'accepts valid hosted content, forwards assignment and metering context, and partitions cache by assignment key',
      () async {
    final fixture = stringScreenFixture();
    installManifestBundle(fixture.bundle);
    await _installMeteringKey();
    String? assignmentKey = 'assignment-a';
    SurfaceAssignmentKeyProvider.current = () => assignmentKey;
    final requests = <http.Request>[];
    final hostedBlob = rfwScreenBlob(text: 'Hosted screen', event: 'tap');
    final client = RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final assigned = body['assignmentKey'] == null
            ? null
            : SurfaceExperimentAssignmentV1(
                experimentId: 'experiment',
                variantId: 'variant',
                experimentEpoch: 2,
              );
        return http.Response(
          SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(
            fixture.delivery(
              hostedBlob: hostedBlob,
              publishedRevision: 8,
              assignment: assigned,
            ),
          ),
          200,
        );
      }),
    );
    final resolver = _resolver(
      client: client,
      fallback: FixedBundledScreenResolver(fixture.bundled()),
    );

    final first = await resolver.resolve(fixture.ref);
    final cached = await resolver.resolve(fixture.ref);
    assignmentKey = 'assignment-b';
    final otherAssignment = await resolver.resolve(fixture.ref);
    assignmentKey = null;
    final unassigned = await resolver.resolve(fixture.ref);

    expect(first.origin, SurfaceScreenOrigin.hosted);
    expect(first.cacheHit, isFalse);
    expect(first.contentHash, isNot(fixture.contentHash));
    expect(cached.cacheHit, isTrue);
    expect(otherAssignment.cacheHit, isFalse);
    expect(unassigned.cacheHit, isFalse);
    expect(requests, hasLength(3));

    final bodies = requests
        .map((request) => jsonDecode(request.body) as Map<String, Object?>)
        .toList();
    expect(
      bodies.map((body) => body['assignmentKey']),
      <Object?>['assignment-a', 'assignment-b', null],
    );
    expect(
      bodies.map((body) => body['meteringKey']),
      <Object?>[_meteringKey, _meteringKey, _meteringKey],
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
    installManifestBundle(fixture.bundle);
    for (final statusCode in <int>[204, 404]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = RestageSurfaceScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.production,
        baseUrl: _baseUrl,
        assetFallback: fallback,
        rpcClientProvider: () => RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: MockClient((_) async => http.Response('', statusCode)),
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
    installManifestBundle(fixture.bundle);
    for (final statusCode in <int>[408, 429, 500, 502, 503, 504]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: MockClient(
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
    installManifestBundle(fixture.bundle);
    for (final failure in <Object>[
      http.ClientException('offline'),
      TimeoutException('delivery timed out'),
    ]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: MockClient((_) async => throw failure),
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
    installManifestBundle(fixture.bundle);
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: MockClient((_) async => throw StateError('bad client')),
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
    installManifestBundle(fixture.bundle);
    for (final statusCode in <int>[400, 401, 403, 409, 413, 422, 501]) {
      final fallback = FixedBundledScreenResolver(fixture.bundled());
      final resolver = _resolver(
        client: RestageRpcClient(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          httpClient: MockClient(
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
    installManifestBundle(fixture.bundle);
    final fallback = FixedBundledScreenResolver(altered.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: MockClient((_) async => http.Response('', 404)),
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
    installManifestBundle(fixture.bundle);
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      fallback: fallback,
    );

    await expectLater(
      resolver.resolve(fixture.ref),
      throwsA(_unavailable(SurfaceScreenUnavailableReason.invalidPayload)),
    );
    expect(fallback.calls, 0);
  });

  test('never falls back from a present contract-version mismatch', () async {
    final fixture = stringScreenFixture();
    installManifestBundle(fixture.bundle);
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final response = fixture.delivery(contractVersion: 2);
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: MockClient(
          (_) async => http.Response(
            SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(response),
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
    installManifestBundle(fixture.bundle);
    final fallback = FixedBundledScreenResolver(fixture.bundled());
    final resolver = _resolver(
      client: RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: MockClient(
          (_) async => http.Response(
            SurfaceScreenDeliveryResponseV1Codec.encodeCanonicalJson(
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

  testWidgets(
      'configuration installs the manifest-aware standalone screen resolver',
      (_) async {
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);

    expect(
      Restage.defaultSurfaceScreenResolver,
      isA<RestageSurfaceScreenResolver>(),
    );
  });
}

RestageSurfaceScreenResolver _resolver({
  required RestageRpcClient client,
  required BundledSurfaceScreenResolver fallback,
}) =>
    RestageSurfaceScreenResolver(
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
