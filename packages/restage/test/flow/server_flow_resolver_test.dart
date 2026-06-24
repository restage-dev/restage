import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
// The installed built-in catalog content version is the resolver's capability
// ceiling (internal; the resolver's own tests reach it via the src path).
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

/// The built-in catalog version this SDK build installs. A delivered document
/// at or below this renders; above it must fail closed — the authoritative
/// installed-capability gate, independent of the ref floor.
const int _renderableMinClient =
    RestageBuiltInCatalogCapabilities.currentVersion;

/// The host's compiled flow-ref floor for these fixtures. Pinned above the
/// installed catalog version (with headroom) so a valid document at the
/// installed version always renders, while leaving room for the two distinct
/// fail-closed cases below: a document above the ref floor
/// ([_aboveRefFloorMinClient]) and a document within the ref floor but above
/// the installed catalog ([_renderableMinClient] + 1). Deriving these from the
/// installed version keeps the asserted relationships stable across catalog
/// version bumps instead of drifting against a hardcoded literal.
const int _refFloorMinClient = _renderableMinClient + 2;

/// A floor strictly above the host's compiled ref floor — used by the
/// fixtures that prove a document/artifact exceeding the ref floor fails
/// closed.
const int _aboveRefFloorMinClient = _refFloorMinClient + 1;

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: _refFloorMinClient,
    decodeResult: _decodeMapResult,
  );

  setUp(Restage.debugReset);

  test(
      'fetches the exact-version flow and returns immutable exact screen bytes',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3, 255]);
    final envelope =
        _envelope(_validDocument(screenBytes: screenBytes), screenBytes);
    final requests = <http.Request>[];
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope, onRequest: requests.add),
    );

    final resolved = await resolver.resolve(flowRef);

    // The resolver POSTs the exact-version request to the serve route with
    // bearer auth and the typed body.
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), '$baseUrl/sdk/v1/surface');
    expect(request.headers['Authorization'], 'Bearer $apiKey');
    expect(
      jsonDecode(request.body),
      {'surfaceType': 'onboarding', 'surfaceSlug': 'first_run', 'version': 1},
    );

    expect(resolved.cacheHit, isFalse);
    expect(resolved.document.flow, flowRef.id);
    expect(resolved.document.version, flowRef.version);
    expect(resolved.screenBlobs.keys, ['welcome']);
    expect(resolved.screenBlobs['welcome'], screenBytes);
    // Deep-frozen result graph.
    expect(
      () => resolved.document.states.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => resolved.screenBlobs['welcome']![0] = 9,
      throwsUnsupportedError,
    );
    expect(
      () => resolved.screenBlobs['extra'] = Uint8List(0),
      throwsUnsupportedError,
    );
  });

  // EXACT-VERSION CONTRACT (intentional — do not "fix" to a latest-version
  // fetch): a re-resolve of the same ref is served from the version-pinned
  // cache and NEVER re-fetches to discover a newer published version. Published
  // surface rows are immutable + env-scoped + uniquely keyed by
  // (surface, environment, version), so a (slug, version) tuple maps to one
  // content hash forever; a higher published version is only ever picked up
  // when the host ships a higher ref.version. No time-based invalidation.
  test('caches by (slug, version): a re-resolve hits without re-fetching',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope =
        _envelope(_validDocument(screenBytes: screenBytes), screenBytes);
    var fetches = 0;
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope, onRequest: (_) => fetches++),
    );

    final first = await resolver.resolve(flowRef);
    final second = await resolver.resolve(flowRef);

    expect(first.cacheHit, isFalse);
    expect(second.cacheHit, isTrue);
    // A pinned version is served from cache: only one network fetch.
    expect(fetches, 1);
    // The cached result is still deep-frozen and carries the same bytes.
    expect(second.screenBlobs['welcome'], screenBytes);
    expect(
      () => second.screenBlobs['welcome']![0] = 9,
      throwsUnsupportedError,
    );
  });

  test('fails closed when the serve route returns 404 unavailable', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'unavailable'}), 404),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unavailable')),
    );
  });

  test('fails closed when the serve route returns 401 unauthorized', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'unauthorized'}), 401),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unavailable')),
    );
  });

  test('fails closed on a transport (network) error', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => throw const SocketishException(),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unavailable')),
    );
  });

  test('fails closed when the 200 body has no envelope field', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'not': 'envelope'}), 200),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unavailable')),
    );
  });

  test('fails closed when the envelope is not valid base64', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'envelope': 'not!base64!'}), 200),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unavailable')),
    );
  });

  test('fails closed when the envelope bytes do not decode', () async {
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'envelope': base64Encode(const [9, 9, 9, 9])
          }),
          200,
        ),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('decode_failed')),
    );
  });

  test('fails closed when a screen blob in the payload is tampered', () async {
    // The payload's canonical bytes carry the blob; flipping a blob byte after
    // assembly breaks the codec's content-hash/isomorphism check at decode.
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope =
        _envelope(_validDocument(screenBytes: screenBytes), screenBytes);
    final tampered = Uint8List.fromList(envelope)
      ..[envelope.length - 1] ^= 0xFF;
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: MockClient(
        (_) async => http.Response(
            jsonEncode({'envelope': base64Encode(tampered)}), 200),
      ),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('decode_failed')),
    );
  });

  test('fails closed when the inner document flow id does not match', () async {
    // The envelope identity matches the ref ("first_run"), so the inner
    // FlowDocument identity check (defense-in-depth, separate from the envelope
    // identity gate) is the one that catches a divergent inner document.
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelopeWithIdentity(
      _validDocument(flow: 'other_flow', screenBytes: screenBytes),
      screenBytes,
      surfaceSlug: 'first_run',
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('flow_mismatch')),
    );
  });

  test(
      'fails closed when the surface envelope identity diverges from the '
      'requested flow (even if the inner document matches)', () async {
    // The inner FlowDocument is a valid "first_run" v1 doc (so the document
    // identity checks would pass), but the decoded SurfaceDocument envelope's
    // header surfaceSlug is "other_flow" — a wrong-surface envelope must not
    // render as this flow. Mirrors the blob path's envelope-identity check.
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelopeWithIdentity(
      _validDocument(screenBytes: screenBytes),
      screenBytes,
      surfaceSlug: 'other_flow',
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('surface_mismatch')),
    );
  });

  test(
      'fails closed when the surface envelope version diverges from the '
      'requested flow (even if the inner document matches)', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelopeWithIdentity(
      _validDocument(screenBytes: screenBytes),
      screenBytes,
      version: 2,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('surface_mismatch')),
    );
  });

  test('fails closed when the inner document version does not match', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelopeWithIdentity(
      _validDocument(version: 2, screenBytes: screenBytes),
      screenBytes,
      version: 1,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('version_mismatch')),
    );
  });

  test('fails closed for an unsupported document schemaVersion', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelope(
      _validDocument(schemaVersion: 2, screenBytes: screenBytes),
      screenBytes,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_schema_version')),
    );
  });

  test('fails closed below the client capability floor (document minClient)',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    // A document requiring more than the host's compiled ref floor must fail
    // closed.
    final envelope = _envelope(
      _validDocument(
          minClient: _aboveRefFloorMinClient, screenBytes: screenBytes),
      screenBytes,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test('fails closed below the client capability floor (artifact minClient)',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelope(
      _validDocument(
        screenBytes: screenBytes,
        artifactMinClient: _aboveRefFloorMinClient,
      ),
      screenBytes,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test(
      'fails closed when document minClient exceeds the installed catalog '
      'version, even within the ref floor', () async {
    // The ref floor sits above the installed catalog version. A document at
    // (installed + 1) passes the ref-consistency check (it is within the ref
    // floor) but exceeds the installed catalog → it must fail closed.
    // Before the installed-capability gate (parity with the blob path) this
    // rendered — the fail-open the review flagged: the ref floor is not the
    // authoritative installed-capability gate.
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelope(
      _validDocument(
        minClient: _renderableMinClient + 1,
        artifactMinClient: _renderableMinClient + 1,
        screenBytes: screenBytes,
      ),
      screenBytes,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test(
      'fails closed when a screen artifact minClient exceeds the installed '
      'catalog version, even within the ref floor', () async {
    // The document floor is renderable, but a single screen artifact requires a
    // higher built-in catalog than installed (installed + 1) while staying
    // within the ref floor. Each screen artifact is gated against the installed
    // capability, not just the ref floor.
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final envelope = _envelope(
      _validDocument(
        artifactMinClient: _renderableMinClient + 1,
        screenBytes: screenBytes,
      ),
      screenBytes,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test('fails closed for a semantically-invalid document (rejected at decode)',
      () async {
    // Document validity is enforced by the surface codec at decode: rebuilding
    // the flow payload re-runs canonical validation, so a forged/out-of-band
    // envelope whose flow JSON decodes structurally but points a screen state at
    // a screen with no artifact fails closed at decode (as `decode_failed`),
    // before the resolver's defense-in-depth validate pass is reachable. We
    // hand-frame such a payload (the canonical encoder would otherwise reject
    // it) to prove the fail-closed boundary.
    final envelope = _handFramedBrokenValidationEnvelope();
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(envelope),
    );

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('decode_failed')),
    );
  });

  test('rejects an empty base URL', () {
    expect(
      () => ServerFlowResolver(baseUrl: '', apiKey: apiKey),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a base URL with a trailing slash', () {
    expect(
      () => ServerFlowResolver(baseUrl: '$baseUrl/', apiKey: apiKey),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects an empty API key', () {
    expect(
      () => ServerFlowResolver(baseUrl: baseUrl, apiKey: ''),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('is injectable as the default flow resolver via Restage.configure', () {
    final resolver = ServerFlowResolver(baseUrl: baseUrl, apiKey: apiKey);

    // No baseUrl on configure: this asserts resolver injection only, and a
    // configured baseUrl would kick off the unrelated entitlement-sync path.
    Restage.configure(
      apiKey: apiKey,
      flowResolver: resolver,
    );

    expect(Restage.defaultFlowResolver, same(resolver));
  });

  group('required-library capability gate (envelope-level, fail-closed)', () {
    final screenBytes = Uint8List.fromList([1, 2, 3, 255]);
    const requirement =
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 2);

    ServerFlowResolver resolverFor(Uint8List envelope) => ServerFlowResolver(
          baseUrl: baseUrl,
          apiKey: apiKey,
          httpClient: _server(envelope),
        );

    test('fails closed when a required library is not registered', () async {
      final envelope = _envelope(
        _validDocument(screenBytes: screenBytes),
        screenBytes,
        requiredLibraries: const [requirement],
      );
      await expectLater(
        resolverFor(envelope).resolve(flowRef),
        throwsA(_flowUnavailable('unsupported_required_library')),
      );
    });

    test('fails closed when a required library is under-version', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 1, // installed v1 < required v2
      );
      final envelope = _envelope(
        _validDocument(screenBytes: screenBytes),
        screenBytes,
        requiredLibraries: const [requirement],
      );
      await expectLater(
        resolverFor(envelope).resolve(flowRef),
        throwsA(_flowUnavailable('unsupported_required_library')),
      );
    });

    test('resolves when the required library is satisfied', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 3, // installed v3 >= required v2
      );
      final envelope = _envelope(
        _validDocument(screenBytes: screenBytes),
        screenBytes,
        requiredLibraries: const [requirement],
      );
      final resolved = await resolverFor(envelope).resolve(flowRef);
      expect(resolved.document.flow, 'first_run');
    });

    test(
        're-runs the capability gate on a cache hit (a library unregistered '
        'after caching fails closed, not a stale render)', () async {
      Restage.registerWidgetLibrary(
        const WidgetLibrary.custom('acme.widgets'),
        widgets: const [],
        capabilityVersion: 3, // installed v3 >= required v2
      );
      final envelope = _envelope(
        _validDocument(screenBytes: screenBytes),
        screenBytes,
        requiredLibraries: const [requirement],
      );
      final resolver = resolverFor(envelope);

      // First resolve passes the gate and caches the renderable.
      final first = await resolver.resolve(flowRef);
      expect(first.cacheHit, isFalse);

      // The library is unregistered AFTER caching (registry cleared). A cache
      // hit must NOT serve the stale renderable — it must re-run the gate and
      // fail closed.
      Restage.debugReset();
      await expectLater(
        resolver.resolve(flowRef),
        throwsA(_flowUnavailable('unsupported_required_library')),
      );
    });
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

Matcher _flowUnavailable(String reason) {
  return isA<FlowUnavailableError>()
      .having((error) => error.reason, 'reason', reason)
      .having((error) => error.flowId, 'flowId', 'first_run')
      .having((error) => error.flowVersion, 'flowVersion', 1)
      .having((error) => error.message, 'message', isNotEmpty);
}

/// Builds a self-contained surface envelope for [document] whose single
/// `welcome` screen blob is [screenBytes] (the same bytes the document's
/// artifact hash was computed from, so the payload is isomorphic).
Uint8List _envelope(
  FlowDocument document,
  Uint8List screenBytes, {
  List<LibraryRequirement> requiredLibraries = const [],
}) {
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
    requiredLibraries: requiredLibraries,
  );
  final surface = SurfaceDocument(
    surfaceType: SurfaceType.onboarding,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    requiredLibraries: requiredLibraries,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

/// Builds a surface envelope whose header identity (`surfaceType` /
/// `surfaceSlug` / `version`) can diverge from the inner [document]'s identity —
/// used to exercise the envelope-identity gate. The payload still wraps
/// [document]; only the envelope header is overridden.
Uint8List _envelopeWithIdentity(
  FlowDocument document,
  Uint8List screenBytes, {
  SurfaceType surfaceType = SurfaceType.onboarding,
  String? surfaceSlug,
  int? version,
}) {
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
  );
  final surface = SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: surfaceSlug ?? document.flow,
    version: version ?? document.version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

/// A `MockClient` serving [envelope] (base64-wrapped) from the surface route.
MockClient _server(
  Uint8List envelope, {
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    return http.Response(
      jsonEncode({'envelope': base64Encode(envelope)}),
      200,
    );
  });
}

FlowDocument _validDocument({
  required Uint8List screenBytes,
  String flow = 'first_run',
  int version = 1,
  int schemaVersion = 1,
  int minClient = _renderableMinClient,
  int artifactMinClient = _renderableMinClient,
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: schemaVersion,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: artifactMinClient,
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

/// Hand-frames a surface envelope whose flow document decodes structurally but
/// fails semantic validation (a screen state points at a screen with no
/// artifact). The canonical encoder validates and would reject this, so the
/// payload + envelope frames are assembled here to mirror the documented wire:
///   payload  = u32be(len "flow") "flow" u32be(len json) json
///              u32be(screenCount) [u32be(idLen) id u32be(blobLen) blob]...
///   envelope = u32be(headerLen) headerJson payloadBytes
Uint8List _handFramedBrokenValidationEnvelope() {
  final screenBytes = Uint8List.fromList([1, 2, 3]);
  final validJson = utf8.decode(
    FlowDocumentCodec.encodeCanonicalJson(
        _validDocument(screenBytes: screenBytes)),
  );
  final brokenJson =
      validJson.replaceFirst('"screen":"welcome"', '"screen":"missing"');
  final payload = _framePayload(brokenJson, {'welcome': screenBytes});
  return _frameEnvelope(
    payload: payload,
    surfaceType: 'onboarding',
    surfaceSlug: 'first_run',
    version: 1,
    minClient: _refFloorMinClient,
  );
}

Uint8List _framePayload(String flowJson, Map<String, Uint8List> blobs) {
  final out = <int>[];
  _appendLengthPrefixed(out, utf8.encode('flow'));
  _appendLengthPrefixed(out, utf8.encode(flowJson));
  out.addAll(_u32be(blobs.length));
  final ids = blobs.keys.toList()..sort();
  for (final id in ids) {
    _appendLengthPrefixed(out, utf8.encode(id));
    _appendLengthPrefixed(out, blobs[id]!);
  }
  return Uint8List.fromList(out);
}

Uint8List _frameEnvelope({
  required Uint8List payload,
  required String surfaceType,
  required String surfaceSlug,
  required int version,
  required int minClient,
}) {
  final header = jsonEncode({
    'contentHash': FlowContentHash.compute(payload).value,
    'formatVersion': 1,
    'minClient': minClient,
    'publishedAtMicros': DateTime.utc(2026).microsecondsSinceEpoch,
    'surfaceSlug': surfaceSlug,
    'surfaceType': surfaceType,
    'version': version,
  });
  final headerBytes = utf8.encode(header);
  return Uint8List.fromList(<int>[
    ..._u32be(headerBytes.length),
    ...headerBytes,
    ...payload,
  ]);
}

void _appendLengthPrefixed(List<int> out, List<int> bytes) {
  out
    ..addAll(_u32be(bytes.length))
    ..addAll(bytes);
}

List<int> _u32be(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

/// A throwing exception used to simulate a transport failure.
class SocketishException implements Exception {
  const SocketishException();
}
