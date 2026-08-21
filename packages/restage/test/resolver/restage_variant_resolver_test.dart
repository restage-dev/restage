import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restage/restage.dart';
// The installed built-in catalog content version is the resolver's capability
// ceiling (internal; the resolver's own tests reach it via the src path).
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

import '../support/hosted_artifact_delivery.dart';

/// The resolver's capability ceiling — the installed built-in catalog version.
const int _supportedVersion = RestageBuiltInCatalogCapabilities.currentVersion;

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';
  final blob = Uint8List.fromList([10, 20, 30, 255]);

  test('constructor exposes apiKey + environment', () {
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
    );
    expect(resolver.apiKey, 'rs_pk_test');
    expect(resolver.environment, RestageEnvironment.sandbox);
  });

  group('resolve — fresh hosted fetch (active arm)', () {
    test('fetches the active version (version OMITTED) and returns the blob',
        () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final requests = <http.Request>[];
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(
          envelope,
          experimentId: 'exp_paywall_copy',
          variantId: 'variant_a',
          experimentEpoch: 3,
          onRequest: requests.add,
        ),
      );

      final variant = await resolver.resolve('pro_upgrade');

      // Active-arm request: POST to the serve route, bearer auth, version OMITTED.
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$baseUrl/sdk/v1/surface');
      expect(request.headers['Authorization'], 'Bearer $apiKey');
      final activeBody = jsonDecode(request.body) as Map<String, dynamic>;
      expect(activeBody['surfaceType'], 'paywall');
      expect(activeBody['surfaceSlug'], 'pro_upgrade');
      expect(activeBody.containsKey('version'), isFalse);
      // The client contract hash rides every hosted fetch (the hot path); the
      // full contract is uploaded only if the server asks (contractRequired).
      expect(activeBody['contractHash'], startsWith('sha256:'));
      expect(activeBody.containsKey('contract'), isFalse);

      // The resolved variant carries the blob, the id, and the SERVED version.
      expect(variant.bytes, blob);
      expect(variant.paywallId, 'pro_upgrade');
      expect(variant.experimentId, 'exp_paywall_copy');
      expect(variant.variantId, 'variant_a');
      expect(variant.experimentEpoch, 3);
      expect(variant.paywallPublishedVersion, 5);
      expect(variant.cacheHit, isFalse);
    });

    test('threads the internal assignment key into the active hosted request',
        () async {
      addTearDown(SurfaceAssignmentKeyProvider.clear);
      SurfaceAssignmentKeyProvider.current = () async => 'anon-assignment-1';
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final requests = <http.Request>[];
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope, onRequest: requests.add),
      );

      await resolver.resolve('pro_upgrade');

      final keyedBody =
          jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(keyedBody['surfaceType'], 'paywall');
      expect(keyedBody['surfaceSlug'], 'pro_upgrade');
      expect(keyedBody['assignmentKey'], 'anon-assignment-1');
      expect(keyedBody['contractHash'], startsWith('sha256:'));
    });

    test(
        'threads the metering key into the hosted serve body only while the '
        'provider is installed', () async {
      addTearDown(SurfaceMeteringKeyProvider.clear);
      const token = 'd9428888-122b-4b0b-8b7f-3e23441121e8';
      SharedPreferences.setMockInitialValues(
        <String, Object>{'restage.metering_token': token},
      );
      final prefs = await SharedPreferences.getInstance();
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);

      SurfaceMeteringKeyProvider.install(
        store: MeteringTokenStore(prefsProvider: () async => prefs),
      );
      final installedRequests = <http.Request>[];
      await RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope, onRequest: installedRequests.add),
      ).resolve('pro_upgrade');
      expect(
        (jsonDecode(installedRequests.single.body)
            as Map<String, dynamic>)['meteringKey'],
        token,
      );

      SurfaceMeteringKeyProvider.clear();
      final clearedRequests = <http.Request>[];
      await RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope, onRequest: clearedRequests.add),
      ).resolve('pro_upgrade');
      expect(
        jsonDecode(clearedRequests.single.body) as Map<String, dynamic>,
        isNot(contains('meteringKey')),
      );
    });

    test(
        'a contractRequired response triggers a single upload-on-miss retry '
        'with the full contract, then renders the served arm', () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final requests = <http.Request>[];
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client((request) async {
          requests.add(request);
          final uploaded =
              (jsonDecode(request.body) as Map).containsKey('contract');
          // First fetch (hash only): no cached contract → ask for upload.
          // Second fetch (contract attached): serve the arm.
          if (!uploaded) {
            return http.Response(
              jsonEncode({
                ..._delivery.describeEnvelope(envelope),
                'decision': 'clientIncompatible',
                'contractRequired': true,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              ..._delivery.describeEnvelope(envelope),
              'decision': 'assigned',
              'experimentId': 'exp_paywall_copy',
              'variantId': 'variant_a',
              'experimentEpoch': 3,
            }),
            200,
          );
        }),
      );

      final variant = await resolver.resolve('pro_upgrade');

      // Exactly two fetches: hash-only, then the retry carrying the contract.
      expect(requests, hasLength(2));
      final first = jsonDecode(requests[0].body) as Map<String, dynamic>;
      final second = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(first['contractHash'], startsWith('sha256:'));
      expect(first.containsKey('contract'), isFalse);
      expect(second['contractHash'], startsWith('sha256:'));
      expect(second['contract'], isA<Map<String, dynamic>>());
      // The retried (assigned) arm renders with its attribution.
      expect(variant.bytes, blob);
      expect(variant.experimentId, 'exp_paywall_copy');
      expect(variant.variantId, 'variant_a');
    });

    test(
        'two consecutive contractRequired responses fail closed to '
        'unavailable — the upload-on-miss retry never loops', () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final requests = <http.Request>[];
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              ..._delivery.describeEnvelope(envelope),
              'decision': 'clientIncompatible',
              'contractRequired': true,
            }),
            200,
          );
        }),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
      // The hot-path fetch + exactly one upload retry — never more.
      expect(requests, hasLength(2));
    });

    test(
        'a clientIncompatible response (no contractRequired) renders the '
        'pinned active version with NO experiment attribution', () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client((request) async {
          // The client cannot render every arm: it sits out the experiment and
          // is served the pinned active version — no assignment metadata, no
          // contractRequired.
          return http.Response(
            jsonEncode({
              ..._delivery.describeEnvelope(envelope),
              'decision': 'clientIncompatible',
            }),
            200,
          );
        }),
      );

      final variant = await resolver.resolve('pro_upgrade');

      // The pinned active version renders...
      expect(variant.bytes, blob);
      expect(variant.paywallPublishedVersion, 5);
      // ...with NO experiment attribution (it did not join an arm).
      expect(variant.experimentId, isNull);
      expect(variant.variantId, isNull);
    });
  });

  group('resolve — fail-closed reject funnels the SAME ladder (never renders)',
      () {
    test('non-blob (flow) payload falls through to a typed error, not the flow',
        () async {
      final flowEnvelope = _flowEnvelope();
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(flowEnvelope),
        // No bundled asset for this id -> the ladder ends in a throw.
        assetFallback: const AssetVariantResolver(),
      );

      // The flow payload must NOT render as a paywall: it falls through.
      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('a non-decodable envelope falls through to a typed error', () async {
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client(
          (_) async => http.Response(
            jsonEncode({
              ..._delivery.describeEnvelope([0, 1, 2, 3])
            }),
            200,
          ),
        ),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('a blob requiring a higher minClient than supported falls through',
        () async {
      final envelope = _blobEnvelope(
        slug: 'pro_upgrade',
        version: 9,
        minClient: _supportedVersion + 1,
        blob: blob,
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('a blob served under a DIFFERENT slug falls through (no wrong render)',
        () async {
      // The server (bug / routing / substituted response) returns a valid blob
      // whose surfaceSlug is a different paywall. It must NOT render or cache as
      // the requested id — it falls through the ladder.
      final envelope =
          _blobEnvelope(slug: 'other_paywall', version: 9, blob: blob);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('a blob carried by a NON-paywall surface type falls through',
        () async {
      // A blob payload delivered under a non-paywall surfaceType (e.g. message)
      // for the requested slug must NOT render as a paywall — it falls through.
      final envelope = _blobEnvelope(
        slug: 'pro_upgrade',
        version: 9,
        surfaceType: Surface.message,
        blob: blob,
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });
  });

  group('resolve — required-library capability gate (fail-closed)', () {
    final blob = Uint8List.fromList([1, 2, 3, 4]);
    const requirement =
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2);

    tearDown(LibraryRuntimeRegistry.clear);

    RestageVariantResolver resolverFor(Uint8List envelope) =>
        RestageVariantResolver(
          apiKey: apiKey,
          environment: RestageEnvironment.production,
          baseUrl: baseUrl,
          httpClient: _server(envelope),
        );

    test('a blob requiring an unregistered library falls through', () async {
      final envelope = _blobEnvelope(blob: blob, requiredLibraries: const [
        requirement,
      ]);
      // No library registered → fail-closed → the ladder → bundled-not-found.
      await expectLater(
        resolverFor(envelope).resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test(
        'the fallback-exhausted error names the capability gap (not just '
        '"fetch failed")', () async {
      final envelope = _blobEnvelope(blob: blob, requiredLibraries: const [
        requirement,
      ]);
      // No library registered + no bundled asset → the active version is
      // rejected for the library gap and nothing else renders. The thrown error
      // must name the gap, not the generic "the fetch failed" message.
      await expectLater(
        resolverFor(envelope).resolve('pro_upgrade'),
        throwsA(
          isA<RestagePaywallError>().having(
            (error) => error.message,
            'message',
            contains('acme.widgets'),
          ),
        ),
      );
    });

    test('a blob requiring an under-version library falls through', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 1, // installed v1 < required v2
      );
      final envelope = _blobEnvelope(blob: blob, requiredLibraries: const [
        requirement,
      ]);
      await expectLater(
        resolverFor(envelope).resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('a blob whose required library is satisfied renders', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 3, // installed v3 >= required v2
      );
      final envelope = _blobEnvelope(blob: blob, requiredLibraries: const [
        requirement,
      ]);
      final variant = await resolverFor(envelope).resolve('pro_upgrade');
      expect(variant.bytes, blob);
    });

    test(
        're-runs the capability gate on a hold-last-good cache hit (a library '
        'unregistered after caching is not served stale)', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 3, // installed v3 >= required v2
      );
      final envelope = _blobEnvelope(blob: blob, requiredLibraries: const [
        requirement,
      ]);
      // First fetch passes the gate + caches; the second fetch fails transport,
      // so resolution would fall to the in-memory hold-last-good cache.
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _sequenceServer([
          http.Response(
              jsonEncode({..._delivery.describeEnvelope(envelope)}), 200),
          http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ]),
      );

      final first = await resolver.resolve('pro_upgrade');
      expect(first.cacheHit, isFalse);

      // The library is unregistered AFTER caching. The cached blob must NOT be
      // served stale — the hold-last-good tier re-runs the capability gate and
      // falls through (no bundled asset → typed error).
      LibraryRuntimeRegistry.clear();
      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });
  });

  group('resolve — the tiered fallback ladder (hold-last-good → asset → throw)',
      () {
    test('holds the last good blob when a later fetch fails', () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final bindingReference = _bindingReference('a');
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _sequenceServer([
          http.Response(
            _surfaceResponseJson(
              envelope,
              experimentId: 'exp_paywall_copy',
              variantId: 'variant_a',
              experimentEpoch: 3,
            ),
            200,
            headers: {
              'Restage-Measurement-Publication-Binding-V1':
                  _bindingHeader(bindingReference),
            },
          ),
          http.Response(jsonEncode({'error': 'unavailable'}), 404),
        ]),
      );

      final first = await resolver.resolve('pro_upgrade');
      expect(first.cacheHit, isFalse);
      expect(first.experimentId, 'exp_paywall_copy');
      expect(first.variantId, 'variant_a');
      expect(first.experimentEpoch, 3);
      expect(first.paywallPublishedVersion, 5);
      expect(
        measurementPublicationBindingReferenceFor(first),
        bindingReference,
      );

      final second = await resolver.resolve('pro_upgrade');
      // Fetch failed -> served from the in-memory hold-last-good cache.
      expect(second.cacheHit, isTrue);
      expect(second.bytes, blob);
      expect(second.experimentId, 'exp_paywall_copy');
      expect(second.variantId, 'variant_a');
      expect(second.experimentEpoch, 3);
      expect(second.paywallPublishedVersion, 5);
      expect(
        measurementPublicationBindingReferenceFor(second),
        bindingReference,
      );
    });

    test('a REJECTED fresh blob funnels into the same ladder (serves cached)',
        () async {
      final good = _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final rejected = _blobEnvelope(
        slug: 'pro_upgrade',
        version: 6,
        minClient: _supportedVersion + 1,
        blob: Uint8List.fromList([99, 99, 99]),
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _sequenceServer([
          http.Response(jsonEncode({..._delivery.describeEnvelope(good)}), 200),
          http.Response(
              jsonEncode({..._delivery.describeEnvelope(rejected)}), 200),
        ]),
      );

      await resolver.resolve('pro_upgrade');
      final second = await resolver.resolve('pro_upgrade');

      // The above-floor blob is NOT rendered; the last good (v5) blob is held.
      expect(second.cacheHit, isTrue);
      expect(second.bytes, blob);
      expect(second.paywallPublishedVersion, 5);
    });

    test('falls back to the bundled asset when the fetch fails + no cache',
        () async {
      final assetVariant = ResolvedVariant(
        bytes: Uint8List.fromList([1, 1, 1]),
        paywallId: 'pro_upgrade',
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client(
          (_) async => http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ),
        assetFallback: _StubResolver(returns: assetVariant),
      );

      final variant = await resolver.resolve('pro_upgrade');
      expect(variant.bytes, assetVariant.bytes);
      expect(variant.paywallPublishedVersion, isNull);
    });

    test('rethrows a typed error when fetch fails + no cache + no asset',
        () async {
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client(
          (_) async => http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ),
        assetFallback: _StubResolver(
          throws: const RestagePaywallError(
            code: RestageErrorCodes.assetNotFound,
            message: 'no bundled asset',
          ),
        ),
      );

      await expectLater(
        resolver.resolve('pro_upgrade'),
        throwsA(isA<RestagePaywallError>()),
      );
    });

    test('with no baseUrl, falls straight to the bundled asset (no crash)',
        () async {
      final assetVariant = ResolvedVariant(
        bytes: Uint8List.fromList([2, 2, 2]),
        paywallId: 'pro_upgrade',
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        // No baseUrl -> no hosted tier.
        assetFallback: _StubResolver(returns: assetVariant),
      );

      final variant = await resolver.resolve('pro_upgrade');
      expect(variant.bytes, assetVariant.bytes);
    });
  });

  group('resolvePayload', () {
    test('returns BlobPaywallPayload for a hosted blob', () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(envelope),
      );

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<BlobPaywallPayload>());
      final blobPayload = payload as BlobPaywallPayload;
      expect(blobPayload.variant.bytes, blob);
      expect(blobPayload.variant.paywallId, 'pro_upgrade');
      expect(blobPayload.variant.paywallPublishedVersion, 5);
      expect(blobPayload.variant.cacheHit, isFalse);
    });

    test('serves the held blob cache when a later payload resolve fails',
        () async {
      final envelope =
          _blobEnvelope(slug: 'pro_upgrade', version: 5, blob: blob);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _sequenceServer([
          http.Response(
            _surfaceResponseJson(
              envelope,
              experimentId: 'exp_paywall_copy',
              variantId: 'variant_a',
              experimentEpoch: 3,
            ),
            200,
          ),
          http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ]),
      );

      final first = await resolver.resolvePayload('pro_upgrade');
      final second = await resolver.resolvePayload('pro_upgrade');

      expect((first as BlobPaywallPayload).variant.cacheHit, isFalse);
      expect(first.variant.experimentId, 'exp_paywall_copy');
      expect(first.variant.variantId, 'variant_a');
      expect(first.variant.experimentEpoch, 3);
      expect(second, isA<BlobPaywallPayload>());
      final secondBlob = second as BlobPaywallPayload;
      expect(secondBlob.variant.cacheHit, isTrue);
      expect(secondBlob.variant.bytes, blob);
      expect(secondBlob.variant.experimentId, 'exp_paywall_copy');
      expect(secondBlob.variant.variantId, 'variant_a');
      expect(secondBlob.variant.experimentEpoch, 3);
      expect(secondBlob.variant.paywallPublishedVersion, 5);
    });

    test('falls back to a blob-only asset resolver as BlobPaywallPayload',
        () async {
      final assetVariant = ResolvedVariant(
        bytes: Uint8List.fromList([1, 1, 1]),
        paywallId: 'pro_upgrade',
      );
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client(
          (_) async => http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ),
        assetFallback: _StubResolver(returns: assetVariant),
      );

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<BlobPaywallPayload>());
      expect((payload as BlobPaywallPayload).variant, same(assetVariant));
    });

    test(
        'falls back to bundled flow when the hosted flow is rejected by a '
        'retained check (unsupported minClient floor)', () async {
      // The active document requires a higher client than installed — a retained
      // check rejects it and the resolver falls back to the bundled flow. (A
      // rewired *charge control* is NOT a rejection cause — that's blob-OTA
      // parity, served ungated; only structural/floor checks fail closed here.)
      final hostedFlowEnvelope = _flowEnvelope(
        surfaceType: Surface.paywall,
        slug: 'pro_upgrade',
        version: 9,
        minClient: _supportedVersion + 1,
        screenBytes: _purchaseScreen('Subscribe now'),
      );
      final bundledScreen = _purchaseScreen('Subscribe');
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: bundledScreen,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(hostedFlowEnvelope),
        assetFallback: AssetVariantResolver(bundle: bundle),
      );

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<FlowPaywallPayload>());
      final flowPayload = payload as FlowPaywallPayload;
      expect(flowPayload.paywallId, 'pro_upgrade');
      expect(flowPayload.paywallPublishedVersion, isNull);
      expect(flowPayload.flow.document.version, 1);
      expect(flowPayload.flow.screenBlobs['welcome'], bundledScreen);
      expect(bundle.loadedKeys, [
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]);
    });

    test(
        'resolves a compatible hosted flow via the active arm '
        '(served version + experiment)', () async {
      final bundledScreen = _purchaseScreen('Subscribe');
      final hostedScreen = _purchaseScreen('Subscribe now'); // content-only
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(flow: 'pro_upgrade', screenBytes: bundledScreen),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _server(
          _paywallFlowEnvelope(screenBytes: hostedScreen, version: 9),
          experimentId: 'exp_flow',
          variantId: 'variant_a',
          experimentEpoch: 3,
        ),
        assetFallback: AssetVariantResolver(bundle: bundle),
      );

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<FlowPaywallPayload>());
      final flow = payload as FlowPaywallPayload;
      expect(
          flow.paywallPublishedVersion, 9); // the SERVED version, not bundled
      expect(flow.experimentId, 'exp_flow');
      expect(flow.variantId, 'variant_a');
      expect(flow.experimentEpoch, 3);
      expect(flow.resolvedFromActiveArm, isTrue);
      expect(
          flow.flow.screenBlobs['welcome'], hostedScreen); // the HOSTED screen
    });

    test('holds the last-good active flow when a later fetch fails, re-gated',
        () async {
      final bundledScreen = _purchaseScreen('Subscribe');
      final hostedScreen = _purchaseScreen('Subscribe now');
      final bindingReference = _bindingReference('b');
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(flow: 'pro_upgrade', screenBytes: bundledScreen),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _sequenceServer([
          http.Response(
            _surfaceResponseJson(
              _paywallFlowEnvelope(screenBytes: hostedScreen, version: 9),
              experimentId: 'exp_flow',
              variantId: 'variant_a',
              experimentEpoch: 3,
            ),
            200,
            headers: {
              'Restage-Measurement-Publication-Binding-V1':
                  _bindingHeader(bindingReference),
            },
          ),
          http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ]),
        assetFallback: AssetVariantResolver(bundle: bundle),
      );

      final first = await resolver.resolvePayload('pro_upgrade');
      final second = await resolver.resolvePayload('pro_upgrade');

      // First: the fresh hosted active flow.
      expect((first as FlowPaywallPayload).paywallPublishedVersion, 9);
      expect(first.variantId, 'variant_a');
      expect(first.experimentEpoch, 3);
      expect(
        measurementPublicationBindingReferenceFor(first.flow),
        bindingReference,
      );
      // Second (fetch failed): the held-last-good active flow, re-gated + served
      // as a cache hit (still the served version, not the bundled null).
      expect(second, isA<FlowPaywallPayload>());
      final held = second as FlowPaywallPayload;
      expect(held.paywallPublishedVersion, 9);
      expect(held.variantId, 'variant_a');
      expect(held.experimentEpoch, 3);
      expect(held.flow.cacheHit, isTrue);
      expect(held.flow.screenBlobs['welcome'], hostedScreen);
      expect(
        measurementPublicationBindingReferenceFor(held.flow),
        bindingReference,
      );
    });

    test('reaches bundled flow through asset fallback when fetch fails',
        () async {
      final bundledScreen = Uint8List.fromList([1, 2, 3]);
      final bundle = _PaywallAssetBundle()
        ..writeFlow(
          'pro_upgrade',
          _flowDocument(
            flow: 'pro_upgrade',
            screenBytes: bundledScreen,
          ),
        )
        ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen);
      final resolver = RestageVariantResolver(
        apiKey: apiKey,
        environment: RestageEnvironment.production,
        baseUrl: baseUrl,
        httpClient: _delivery.client(
          (_) async => http.Response(jsonEncode({'error': 'unavailable'}), 503),
        ),
        assetFallback: AssetVariantResolver(bundle: bundle),
      );

      final payload = await resolver.resolvePayload('pro_upgrade');

      expect(payload, isA<FlowPaywallPayload>());
      expect((payload as FlowPaywallPayload).flow.document.flow, 'pro_upgrade');
    });
  });
}

/// A `MockClient` serving [envelope] (base64-wrapped) from the surface route.
MockClient _server(
  Uint8List envelope, {
  String? experimentId,
  String? variantId,
  int? experimentEpoch,
  void Function(http.Request request)? onRequest,
}) {
  return _delivery.client((request) async {
    onRequest?.call(request);
    return http.Response(
      _surfaceResponseJson(
        envelope,
        experimentId: experimentId,
        variantId: variantId,
        experimentEpoch: experimentEpoch,
      ),
      200,
    );
  });
}

String _surfaceResponseJson(
  Uint8List envelope, {
  String? experimentId,
  String? variantId,
  int? experimentEpoch,
}) {
  return jsonEncode({
    ..._delivery.describeEnvelope(envelope),
    if (experimentId != null) 'experimentId': experimentId,
    if (variantId != null) 'variantId': variantId,
    if (experimentEpoch != null) 'experimentEpoch': experimentEpoch,
  });
}

/// A `MockClient` returning [responses] in order across successive calls (the
/// last one repeats once exhausted).
MockClient _sequenceServer(List<http.Response> responses) {
  var i = 0;
  return _delivery.client((_) async {
    final response = responses[i < responses.length ? i : responses.length - 1];
    i++;
    return response;
  });
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
        'authority.paywall.$seed',
      ),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}

/// Builds a (blob-payload) surface envelope. Defaults to a paywall; the
/// [surfaceType] / [slug] overrides let a test forge an identity-mismatched
/// envelope (a blob served under a different slug or a non-paywall type).
Uint8List _blobEnvelope({
  required Uint8List blob,
  String slug = 'pro_upgrade',
  int version = 1,
  int minClient = _supportedVersion,
  Surface surfaceType = Surface.paywall,
  List<LibraryRequirement> requiredLibraries = const [],
}) {
  final payload = BlobSurfacePayload(
    minClient: minClient,
    blob: blob,
    requiredLibraries: requiredLibraries,
  );
  final surface = SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: slug,
    version: version,
    minClient: minClient,
    requiredLibraries: requiredLibraries,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

/// Builds a flow (onboarding) surface envelope — a non-blob payload that the
/// paywall resolver must reject.
Uint8List _flowEnvelope({
  Surface surfaceType = Surface.onboarding,
  String slug = 'pro_upgrade',
  int version = 1,
  int minClient = 3,
  Uint8List? screenBytes,
}) {
  final bytes = screenBytes ?? Uint8List.fromList([1, 2, 3]);
  final document = FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: minClient,
        contentHash: FlowContentHash.compute(bytes),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': bytes},
  );
  final surface = SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: slug,
    version: version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

FlowDocument _flowDocument({
  required String flow,
  required Uint8List screenBytes,
  int minClient = _supportedVersion,
}) {
  return FlowDocument(
    flow: flow,
    version: 1,
    schemaVersion: 1,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'paywall_$flow.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _supportedVersion,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// A valid RFW paywall-flow screen blob whose single control fires a purchase.
Uint8List _purchaseScreen(String label) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event 'restage.purchase' { slot: "primary" },
      child: Text(text: "$label"));
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A hosted paywall-flow surface envelope structurally identical to the bundled
/// [_flowDocument] (so the render gate sees only a content change), served at
/// [version] with the given [screenBytes].
Uint8List _paywallFlowEnvelope({
  required Uint8List screenBytes,
  int version = 9,
  String slug = 'pro_upgrade',
}) {
  final document = _flowDocument(flow: slug, screenBytes: screenBytes);
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
  );
  final surface = SurfaceDocument(
    surfaceType: Surface.paywall,
    surfaceSlug: slug,
    version: version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

final class _PaywallAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> _assets = {};
  final List<String> loadedKeys = [];

  void writeFlow(String id, FlowDocument document) {
    _assets['assets/paywalls/$id.flow.json'] = Uint8List.fromList(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/paywalls/screens/$path'] = Uint8List.fromList(bytes);
  }

  @override
  Future<ByteData> load(String key) async {
    // The asset manifest is how the SDK finds packaged containers, and how it
    // knows a logical path was never packaged loose. It is not a delivery
    // artifact, and these tests are about which delivery artifacts a resolve
    // reads.
    if (key != 'AssetManifest.bin') loadedKeys.add(key);
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

/// A stub [VariantResolver] for the composed asset-fallback seam.
final class _StubResolver implements VariantResolver {
  _StubResolver({this.returns, this.throws});

  final ResolvedVariant? returns;
  final RestagePaywallError? throws;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (throws != null) throw throws!;
    return returns!;
  }
}
