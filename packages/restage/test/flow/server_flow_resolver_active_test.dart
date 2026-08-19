import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/flow/flow_experiment_artifact_metadata.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart';

/// The installed built-in catalog version this SDK build ships. The active arm's
/// retained installed-floor backstop rejects a document above it.
const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;

/// The host's compiled flow-ref floor for these fixtures, with headroom above
/// the installed catalog so a document at the installed version always renders
/// while leaving room for the installed-floor backstop fixture (a document at
/// `_installed + 1`, within the ref floor but above the installed catalog).
const int _refFloor = _installed + 2;

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: _refFloor,
    surface: Surface.onboarding,
    decodeResult: _decodeMapResult,
  );

  setUp(Restage.debugReset);

  testWidgets(
      'explicit active surface host seals identity before its warm request',
      (tester) async {
    final bundledBytes = screenBlob('Bundled', 'next');
    final activeBytes = screenBlob('Active', 'next');
    final assignmentKey = Completer<String?>();
    final requests = <http.Request>[];
    SurfaceAssignmentKeyProvider.current = () => assignmentKey.future;
    addTearDown(() {
      if (!assignmentKey.isCompleted) assignmentKey.complete(null);
      SurfaceAssignmentKeyProvider.clear();
    });
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
        onRequest: requests.add,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: RestageSurfaceFlow<Map<String, Object?>>(
        flow: flowRef,
        resolver: resolver,
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    ));
    await tester.pump();

    expect(requests, isEmpty);

    assignmentKey.complete('anon-controlled');
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['assignmentKey'], 'anon-controlled');
    expect(body['flowContractKind'], 'flow');
    expect(body['flowContractVersion'], 1);
    expect(body['flowContractHash'], startsWith('sha256:'));
    expect(body.containsKey('flowContractBytes'), isFalse);
  });

  test('old client → newer compatible active: renders the ACTIVE doc',
      () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]); // new content (OTA)
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    // The newer, content-compatible active version renders — the OTA capability.
    expect(resolved.document.version, 2);
    expect(resolved.screenBlobs['welcome'], activeBytes);
    final metadata =
        (resolver as FlowExperimentArtifactMetadataProvider).metadataFor(
      resolved,
    );
    expect(metadata.requiredLibraries, isEmpty);
    expect(metadata.payloadIntegrityVerified, isTrue);
  });

  test(
      'active onboarding response metadata is not stamped onto flow analytics '
      'events', () async {
    final bundledBytes = screenBlob('Bundled', 'next');
    final activeBytes = screenBlob('Active', 'next');
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
        experimentId: 'exp_onboarding_copy',
        variantId: 'variant_a',
        experimentEpoch: 3,
      ),
    );
    final events = <RestageEvent>[];
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: resolver,
      actions: null,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    await drainFlowTasks();

    final started = events.whereType<FlowStarted>().single;
    expect(started.resolvedVersion, 2);
    expect(started.toMap().containsKey('experimentId'), isFalse);
    expect(started.toMap().containsKey('variantId'), isFalse);
    expect(started.toMap().containsKey('experimentEpoch'), isFalse);

    final envelope = mapRestageEventToEnvelope(
      started,
      eventId: 'evt-1',
      anonymousId: 'anon-1',
      sessionId: 'sess-1',
      appContext: const AnalyticsAppContext(
        platform: 'ios',
        locale: 'en_US',
        sdkVersion: '1.0.0',
      ),
      now: DateTime.utc(2026, 6, 13, 12),
    );
    expect(envelope.surface, AnalyticsSurface.onboarding);
    expect(envelope.surfaceId, 'first_run');
    expect(envelope.experimentId, isNull);
    expect(envelope.variantId, isNull);
    expect(envelope.experimentEpoch, isNull);
  });

  test('new client → breaking active: fails closed to the BUNDLED doc',
      () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6]);
    // A contract expansion (an added terminal-result key) → the gate REJECTS.
    final breakingActive = _doc(
      version: 2,
      screenBytes: activeBytes,
      terminalResult: const {'completed': true, 'extra': 1},
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _server(_envelope(breakingActive, activeBytes)),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    // The breaking active is rejected; the client's own bundled doc renders.
    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs['welcome'], bundledBytes);
  });

  test('active fetch fails → hold-last-good (re-gated) when present', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    var fetches = 0;
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _flakyServer(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
        liveFor: 1,
        onRequest: (_) => fetches++,
      ),
    );

    final first = await resolver.resolveActiveRoot(flowRef);
    final second = await resolver.resolveActiveRoot(flowRef);

    expect(first.document.version, 2);
    // The second fetch fails (null) → hold-last-good serves the cached active.
    expect(second.document.version, 2);
    expect(second.screenBlobs['welcome'], activeBytes);
    expect(second.cacheHit, isTrue);
    final provider = resolver as FlowExperimentArtifactMetadataProvider;
    for (final resolved in [first, second]) {
      final metadata = provider.metadataFor(resolved);
      expect(metadata.requiredLibraries, isEmpty);
      expect(metadata.payloadIntegrityVerified, isTrue);
    }
    expect(fetches, 2);
  });

  test('active fetch fails + no cache → BUNDLED', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(_doc(screenBytes: bundledBytes), bundledBytes),
      httpClient: _notFoundServer(),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs['welcome'], bundledBytes);
    final metadata =
        (resolver as FlowExperimentArtifactMetadataProvider).metadataFor(
      resolved,
    );
    expect(metadata.requiredLibraries, isEmpty);
    expect(metadata.payloadIntegrityVerified, isTrue);
  });

  test('no bundled asset + active arm → fail closed (never an ungated accept)',
      () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _emptyBundle(), // no flow JSON present
      httpClient: _server(
        _envelope(_doc(version: 2, screenBytes: activeBytes), activeBytes),
      ),
    );

    // The active fetch WOULD succeed, but with no bundled client contract the
    // gate cannot run → fail closed; the active doc is never rendered ungated.
    await expectLater(
      resolver.resolveActiveRoot(flowRef),
      throwsA(isA<FlowUnavailableError>()),
    );
    expect(
      logs,
      contains(
        '[restage] rejected bundled onboarding flow baseline "first_run" '
        '(missing_flow_json); active selection failed closed.',
      ),
    );
    expect(logs.join(), isNot(contains(apiKey)));
  });

  for (final surfaceType in const [
    Surface.message,
    Surface.survey,
  ]) {
    test('active arm resolves a ${surfaceType.wireName} flow', () async {
      final bundledBytes = Uint8List.fromList([1, 2, 3]);
      final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
      final requests = <http.Request>[];
      final surfaceRef = OnboardingFlowRef<Map<String, Object?>>(
        id: 'first_run',
        version: 1,
        minClient: _refFloor,
        surface: surfaceType,
        decodeResult: _decodeMapResult,
      );
      final resolver = ServerFlowResolver(
        baseUrl: baseUrl,
        apiKey: apiKey,
        active: true,
        bundle: _bundleFor(
          _doc(screenBytes: bundledBytes),
          bundledBytes,
          surfaceType: surfaceType,
        ),
        httpClient: _server(
          _envelope(
            _doc(version: 2, screenBytes: activeBytes),
            activeBytes,
            surfaceType: surfaceType,
          ),
          onRequest: requests.add,
        ),
      );

      final resolved = await resolver.resolveActiveRoot(surfaceRef);

      expect(resolved.document.version, 2);
      expect(resolved.screenBlobs['welcome'], activeBytes);
      expect(jsonDecode(requests.single.body), {
        'surfaceType': surfaceType.wireName,
        'surfaceSlug': 'first_run',
      });
    });
  }

  test(
      'backstop (resolver): a gate-accepted active above the installed catalog '
      'floor is rejected → BUNDLED', () async {
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    // Both docs at _installed+1: identical content (gate ACCEPTS, self-relative
    // floor passes), but above the installed catalog — the resolver's retained
    // installed-floor check (NOT the version pin) must still reject the active.
    const aboveInstalled = _installed + 1;
    final bundled = _doc(
      screenBytes: bundledBytes,
      minClient: aboveInstalled,
      artifactMinClient: aboveInstalled,
    );
    final active = _doc(
      version: 2,
      screenBytes: activeBytes,
      minClient: aboveInstalled,
      artifactMinClient: aboveInstalled,
    );
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(bundled, bundledBytes),
      httpClient: _server(_envelope(active, activeBytes)),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    // The active (above the installed catalog) is rejected by the retained
    // backstop; the bundled (app-bundle-trusted) renders.
    expect(resolved.document.version, 1);
  });

  test('opt-in off (default): resolve() still exact-pins, no active capability',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final requests = <http.Request>[];
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      httpClient: _server(
        _envelope(_doc(screenBytes: screenBytes), screenBytes),
        onRequest: requests.add,
      ),
    );

    // Default is NOT active-enabled (the controller would not call the active arm).
    expect((resolver as ActiveArmFlowResolver).activeArmEnabled, isFalse);

    final resolved = await resolver.resolve(flowRef);

    // Byte-unchanged exact path: the request carries the explicit version key.
    expect(jsonDecode(requests.single.body), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'first_run',
      'version': 1,
    });
    expect(resolved.document.version, 1);
  });

  test(
      'resolveActiveRoot self-enforces opt-in: on a non-active resolver it '
      'behaves as the exact path (version-pinned), never active', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final requests = <http.Request>[];
    // active defaults to false. Feed a bundle + an envelope so that IF it went
    // active it would gate/fall back through the bundle — proving by contrast
    // that the !active self-guard took the exact path instead.
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      bundle: _bundleFor(_doc(screenBytes: screenBytes), screenBytes),
      httpClient: _server(
        _envelope(_doc(screenBytes: screenBytes), screenBytes),
        onRequest: requests.add,
      ),
    );

    final resolved = await resolver.resolveActiveRoot(flowRef);

    // Exact request (the explicit version key); the active arm omits it.
    expect(jsonDecode(requests.single.body), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'first_run',
      'version': 1,
    });
    expect(resolved.document.version, 1);
  });

  test(
      'active arm + a mis-versioned bundled asset → fail closed (the bundled '
      'contract is version-pinned at load)', () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    final bundledBytes = Uint8List.fromList([1, 2, 3]);
    final activeBytes = Uint8List.fromList([4, 5, 6, 7]);
    // The bundled asset is version 2, but the ref (the client contract) is
    // version 1 — a mis-versioned bundle. It must fail to load → no contract →
    // fail closed, never silently served as the active-arm bundled fallback.
    final resolver = ServerFlowResolver(
      baseUrl: baseUrl,
      apiKey: apiKey,
      active: true,
      bundle: _bundleFor(
        _doc(version: 2, screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: _server(
        _envelope(_doc(version: 3, screenBytes: activeBytes), activeBytes),
      ),
    );

    await expectLater(
      resolver.resolveActiveRoot(flowRef),
      throwsA(isA<FlowUnavailableError>()),
    );
    expect(
      logs,
      contains(
        '[restage] rejected bundled onboarding flow baseline "first_run" '
        '(version_mismatch); active selection failed closed.',
      ),
    );
    expect(logs.join(), isNot(contains(apiKey)));
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

/// Builds a `first_run` flow document: a single `welcome` screen → `done`
/// terminal. [terminalResult] customizes the end result (for the breaking
/// contract-expansion case).
FlowDocument _doc({
  required Uint8List screenBytes,
  int version = 1,
  int minClient = _installed,
  int artifactMinClient = _installed,
  Map<String, Object?> terminalResult = const {'completed': true},
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
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
    states: {
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: terminalResult),
    },
  );
}

/// Surface envelope wrapping [document] with its single `welcome` screen blob.
Uint8List _envelope(
  FlowDocument document,
  Uint8List screenBytes, {
  Surface surfaceType = Surface.onboarding,
}) {
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
  );
  final surface = SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

/// A bundle carrying the bundled flow JSON + its `welcome` screen blob at the
/// SDK's conventional asset paths.
AssetBundle _bundleFor(
  FlowDocument document,
  Uint8List screenBytes, {
  Surface surfaceType = Surface.onboarding,
}) {
  final surface = surfaceType.wireName;
  return _TestBundle({
    'assets/$surface/flows/first_run.flow.json':
        Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    'assets/$surface/screens/welcome.rfw': screenBytes,
  });
}

AssetBundle _emptyBundle() => _TestBundle(const {});

/// A `MockClient` serving [envelope] (base64-wrapped) on every request.
MockClient _server(
  Uint8List envelope, {
  String? experimentId,
  String? variantId,
  int? experimentEpoch,
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    return http.Response(
      jsonEncode({
        'envelope': base64Encode(envelope),
        if (experimentId != null) 'experimentId': experimentId,
        if (variantId != null) 'variantId': variantId,
        if (experimentEpoch != null) 'experimentEpoch': experimentEpoch,
      }),
      200,
    );
  });
}

/// Serves [envelope] for the first [liveFor] requests, then 404s — to exercise
/// the hold-last-good tier on a later fetch failure.
MockClient _flakyServer(
  Uint8List envelope, {
  required int liveFor,
  void Function(http.Request request)? onRequest,
}) {
  var seen = 0;
  return MockClient((request) async {
    onRequest?.call(request);
    if (seen++ < liveFor) {
      return http.Response(
        jsonEncode({'envelope': base64Encode(envelope)}),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

MockClient _notFoundServer() =>
    MockClient((request) async => http.Response('not found', 404));

final class _TestBundle extends CachingAssetBundle {
  _TestBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
