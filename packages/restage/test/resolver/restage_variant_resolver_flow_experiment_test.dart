import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
// ignore: implementation_imports
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  test(
      'presentation preflights and seals the exact flow contract before a '
      'hash-only request and one canonical retry', () async {
    final bundledScreen = _screen('Bundled');
    final hostedScreen = _screen('Hosted');
    final bundle = _ControlledPaywallBundle()
      ..writeFlow(_flowDocument(screen: bundledScreen))
      ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen)
      ..hold('assets/paywalls/pro_upgrade.flow.json')
      ..hold('assets/paywalls/screens/paywall_pro_upgrade.rfw');
    final assignmentStarted = Completer<void>();
    final assignment = Completer<String?>();
    SurfaceAssignmentKeyProvider.current = () {
      if (!assignmentStarted.isCompleted) assignmentStarted.complete();
      return assignment.future;
    };
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');

    await _waitUntil(
      () => bundle.loadedKeys.isNotEmpty || assignmentStarted.isCompleted,
    );
    expect(
      (
        firstAsset: bundle.loadedKeys.firstOrNull,
        assignmentStarted: assignmentStarted.isCompleted,
        requestCount: server.requests.length,
      ),
      (
        firstAsset: 'assets/paywalls/pro_upgrade.flow.json',
        assignmentStarted: false,
        requestCount: 0,
      ),
    );

    bundle.release('assets/paywalls/pro_upgrade.flow.json');
    await _waitUntil(
      () => bundle.loadedKeys
          .contains('assets/paywalls/screens/paywall_pro_upgrade.rfw'),
    );
    expect(server.requests, isEmpty);
    expect(assignmentStarted.isCompleted, isFalse);

    bundle.release('assets/paywalls/screens/paywall_pro_upgrade.rfw');
    await assignmentStarted.future;
    expect(server.requests, isEmpty);

    assignment.complete('anon-paywall-key');
    await _waitUntil(() => server.requests.length == 1);
    final firstBody = _requestBody(server.requests.single.request);
    expect(firstBody['assignmentKey'], 'anon-paywall-key');
    expect(firstBody['surfaceType'], 'paywall');
    expect(firstBody['surfaceSlug'], 'pro_upgrade');
    expect(firstBody['flowContractKind'], kFlowExperimentContractKind);
    expect(firstBody['flowContractVersion'], 1);
    expect(firstBody['flowContractHash'], startsWith('sha256:'));
    expect(firstBody, isNot(contains('flowContractBytes')));
    expect(firstBody, isNot(contains('contractHash')));
    expect(firstBody, isNot(contains('contract')));

    server.requests.single.complete(_surfaceResponse(
      _flowEnvelope(screen: hostedScreen, publishedVersion: 9),
      flowContractRequired: true,
    ));
    await _waitUntil(() => server.requests.length == 2);
    final secondBody = _requestBody(server.requests[1].request);
    expect(secondBody['assignmentKey'], 'anon-paywall-key');
    expect(
      secondBody['flowContractHash'],
      firstBody['flowContractHash'],
    );
    final retryBytes = base64Url.decode(
      base64Url.normalize(secondBody['flowContractBytes']! as String),
    );
    expect(
      FlowExperimentClientContractV1.decode(retryBytes).contentHash.value,
      firstBody['flowContractHash'],
    );
    expect(secondBody, isNot(contains('contractHash')));
    expect(secondBody, isNot(contains('contract')));

    server.requests[1].complete(_surfaceResponse(
      _flowEnvelope(screen: hostedScreen, publishedVersion: 9),
      decision: 'assigned',
      experimentId: 'experiment-flow',
      variantId: 'variant-b',
      experimentEpoch: 7,
    ));
    final payload = await resolved as FlowPaywallPayload;
    await Future<void>.delayed(Duration.zero);

    expect(server.requests, hasLength(2));
    expect(payload.acceptedCandidate, isNotNull);
    expect(payload.flow, same(payload.acceptedCandidate!.candidateRoot));
    expect(payload.experimentId, 'experiment-flow');
    expect(payload.variantId, 'variant-b');
    expect(payload.experimentEpoch, 7);
    expect(payload.paywallPublishedVersion, 9);
    expect(payload.flow.screenBlobs['welcome'], hostedScreen);
    expect(
      bundle.loadedKeys,
      orderedEquals(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]),
    );
  });

  test(
      'missing flow preflight preserves the legacy blob request body and still '
      'reaches the rfw fallback', () async {
    final presentationBundle = _ControlledPaywallBundle()
      ..writeBlob('pro_upgrade', Uint8List.fromList(<int>[1, 2, 3]));
    final ordinaryBundle = _ControlledPaywallBundle()
      ..writeBlob('pro_upgrade', Uint8List.fromList(<int>[1, 2, 3]));
    final presentationBodies = <String>[];
    final ordinaryBodies = <String>[];
    final presentation = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: _failingServer(presentationBodies),
      assetFallback: AssetVariantResolver(bundle: presentationBundle),
    );
    final ordinary = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: _failingServer(ordinaryBodies),
      assetFallback: AssetVariantResolver(bundle: ordinaryBundle),
    );

    final presentationPayload =
        await presentation.resolvePayloadForPresentation('pro_upgrade');
    final ordinaryPayload = await ordinary.resolvePayload('pro_upgrade');

    expect(presentationPayload, isA<BlobPaywallPayload>());
    expect(ordinaryPayload, isA<BlobPaywallPayload>());
    expect(presentationBodies, hasLength(1));
    expect(ordinaryBodies, hasLength(1));
    expect(presentationBodies.single, ordinaryBodies.single);
    expect(
      presentationBundle.loadedKeys,
      containsAllInOrder(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/pro_upgrade.rfw',
      ]),
    );
  });

  test(
      'three controlled strict identity drifts fall back to the frozen '
      'unassigned baseline without a request or fourth attempt', () async {
    final bundledScreen = _screen('Bundled');
    final bundle = _ControlledPaywallBundle()
      ..writeFlow(_flowDocument(screen: bundledScreen))
      ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen);
    final assignmentAttempts = <Completer<String?>>[];
    late FutureOr<String?> Function() provider;
    provider = () {
      final attempt = Completer<String?>();
      assignmentAttempts.add(attempt);
      return attempt.future;
    };
    SurfaceAssignmentKeyProvider.current = provider;
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');
    for (var attempt = 0; attempt < 3; attempt += 1) {
      await _waitUntil(() => assignmentAttempts.length == attempt + 1);
      expect(server.requests, isEmpty);
      SurfaceAssignmentKeyProvider.current = provider;
      assignmentAttempts[attempt].complete(null);
    }

    final payload = await resolved.timeout(const Duration(seconds: 1))
        as FlowPaywallPayload;
    await Future<void>.delayed(Duration.zero);

    expect(assignmentAttempts, hasLength(3));
    expect(server.requests, isEmpty);
    expect(payload.acceptedCandidate, isNull);
    expect(payload.resolvedFromActiveArm, isFalse);
    expect(payload.experimentId, isNull);
    expect(payload.pinnedFlowResolver, isNotNull);
    expect(payload.flow.screenBlobs['welcome'], bundledScreen);
    expect(payload.hasHostedExperimentAuthority, isFalse);
    expect(
      bundle.loadedKeys,
      orderedEquals(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]),
    );
  });

  test('identity drift during the initial request rejects the stale root',
      () async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledScreen = _screen('Bundled');
    final staleScreen = _screen('Stale candidate');
    final freshScreen = _screen('Fresh candidate');
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(
        bundle: (_ControlledPaywallBundle()
          ..writeFlow(_flowDocument(screen: bundledScreen))
          ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen)),
      ),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');
    await _waitUntil(() => server.requests.length == 1);
    actorGeneration += 1;
    server.requests[0].complete(_surfaceResponse(
      _flowEnvelope(screen: staleScreen, publishedVersion: 8),
      decision: 'assigned',
      experimentId: 'stale-experiment',
      variantId: 'stale-variant',
      experimentEpoch: 1,
    ));
    await _waitUntil(() => server.requests.length == 2);
    server.requests[1].complete(_surfaceResponse(
      _flowEnvelope(screen: freshScreen, publishedVersion: 9),
      decision: 'assigned',
      experimentId: 'fresh-experiment',
      variantId: 'fresh-variant',
      experimentEpoch: 2,
    ));

    final payload = await resolved as FlowPaywallPayload;
    expect(server.requests, hasLength(2));
    expect(
        _requestBody(server.requests[0].request)['assignmentKey'], 'actor-0');
    expect(
        _requestBody(server.requests[1].request)['assignmentKey'], 'actor-1');
    expect(payload.flow.screenBlobs['welcome'], freshScreen);
    expect(payload.experimentId, 'fresh-experiment');
  });

  test('identity drift during canonical retry rejects both stale responses',
      () async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledScreen = _screen('Bundled');
    final staleScreen = _screen('Stale retry');
    final freshScreen = _screen('Fresh retry');
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(
        bundle: (_ControlledPaywallBundle()
          ..writeFlow(_flowDocument(screen: bundledScreen))
          ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen)),
      ),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');
    await _waitUntil(() => server.requests.length == 1);
    final staleResponse = _surfaceResponse(
      _flowEnvelope(screen: staleScreen, publishedVersion: 8),
      decision: 'assigned',
      experimentId: 'stale-experiment',
      variantId: 'stale-variant',
      experimentEpoch: 1,
    );
    server.requests[0].complete(_surfaceResponse(
      _flowEnvelope(screen: staleScreen, publishedVersion: 8),
      flowContractRequired: true,
    ));
    await _waitUntil(() => server.requests.length == 2);
    actorGeneration += 1;
    server.requests[1].complete(staleResponse);
    await _waitUntil(() => server.requests.length == 3);
    server.requests[2].complete(_surfaceResponse(
      _flowEnvelope(screen: freshScreen, publishedVersion: 9),
      decision: 'assigned',
      experimentId: 'fresh-experiment',
      variantId: 'fresh-variant',
      experimentEpoch: 2,
    ));

    final payload = await resolved as FlowPaywallPayload;
    final bodies =
        server.requests.map((entry) => _requestBody(entry.request)).toList();
    expect(server.requests, hasLength(3));
    expect(bodies[0]['assignmentKey'], 'actor-0');
    expect(bodies[0], isNot(contains('flowContractBytes')));
    expect(bodies[1]['assignmentKey'], 'actor-0');
    expect(bodies[1], contains('flowContractBytes'));
    expect(bodies[2]['assignmentKey'], 'actor-1');
    expect(bodies[2], isNot(contains('flowContractBytes')));
    expect(payload.flow.screenBlobs['welcome'], freshScreen);
  });

  test(
      'child-prefetch drift rejects the stale root then pins the fresh exact '
      'paywall closure', () async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final baselineRootScreen = _screen('Bundled root');
    final baselineChildScreen = _screen('Pinned candidate child');
    final staleRootScreen = _screen('Stale candidate root');
    final candidateRootScreen = _screen('Candidate root');
    final candidateChildScreen = baselineChildScreen;
    final baselineChild = _childFlowDocument(screen: baselineChildScreen);
    final candidateChild = baselineChild;
    final baselineRoot = _rootWithChildDocument(
      screen: baselineRootScreen,
      child: baselineChild,
    );
    final staleRoot = _rootWithChildDocument(
      screen: staleRootScreen,
      child: candidateChild,
    );
    final candidateRoot = _rootWithChildDocument(
      screen: candidateRootScreen,
      child: candidateChild,
    );
    final bundle = _ControlledPaywallBundle()
      ..writeFlow(baselineRoot)
      ..writeFlow(baselineChild)
      ..writeScreen('root.rfw', baselineRootScreen)
      ..writeScreen('child.rfw', baselineChildScreen);
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');
    await _waitUntil(() => server.requests.length == 1);
    server.requests[0].complete(_surfaceResponse(
      _flowEnvelopeFor(
        staleRoot,
        <String, Uint8List>{'welcome': staleRootScreen},
        publishedVersion: 9,
      ),
      decision: 'assigned',
      experimentId: 'experiment-flow',
      variantId: 'variant-b',
      experimentEpoch: 7,
    ));
    await _waitUntil(() => server.requests.length == 2);
    final staleChildRequest = _requestBody(server.requests[1].request);
    actorGeneration += 1;
    server.requests[1].complete(_surfaceResponse(
      _flowEnvelopeFor(
        candidateChild,
        <String, Uint8List>{'screen': candidateChildScreen},
        publishedVersion: 1,
      ),
    ));
    await _waitUntil(() => server.requests.length == 3);
    server.requests[2].complete(_surfaceResponse(
      _flowEnvelopeFor(
        candidateRoot,
        <String, Uint8List>{'welcome': candidateRootScreen},
        publishedVersion: 10,
      ),
      decision: 'assigned',
      experimentId: 'experiment-flow',
      variantId: 'variant-b',
      experimentEpoch: 8,
    ));
    await _waitUntil(() => server.requests.length == 4);
    final freshChildRequest = _requestBody(server.requests[3].request);
    server.requests[3].complete(_surfaceResponse(
      _flowEnvelopeFor(
        candidateChild,
        <String, Uint8List>{'screen': candidateChildScreen},
        publishedVersion: 1,
      ),
    ));
    final payload = await resolved as FlowPaywallPayload;
    final pinnedChild = await payload.pinnedFlowResolver!.resolve<Object?>(
      const OnboardingFlowRef<Object?>(
        id: 'child',
        version: 1,
        minClient: 3,
        surface: Surface.paywall,
        decodeResult: _identityResult,
      ),
    );

    expect(payload.flow, same(payload.acceptedCandidate!.candidateRoot));
    expect(payload.flow.screenBlobs['welcome'], candidateRootScreen);
    expect(pinnedChild.screenBlobs['screen'], candidateChildScreen);
    for (final childRequest in <Map<String, Object?>>[
      staleChildRequest,
      freshChildRequest,
    ]) {
      expect(childRequest, <String, Object?>{
        'surfaceType': 'paywall',
        'surfaceSlug': 'child',
        'version': 1,
      });
    }
    expect(
      _requestBody(server.requests[0].request)['assignmentKey'],
      'actor-0',
    );
    expect(
      _requestBody(server.requests[2].request)['assignmentKey'],
      'actor-1',
    );
    expect(server.requests, hasLength(4));
  });

  test('presentation disposal during preflight publishes no hosted request',
      () async {
    final bundledScreen = _screen('Bundled');
    final bundle = _ControlledPaywallBundle()
      ..writeFlow(_flowDocument(screen: bundledScreen))
      ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen)
      ..hold('assets/paywalls/pro_upgrade.flow.json');
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );
    var current = true;

    final resolved = withPaywallPresentationGuard(
      guard: () => current,
      resolve: () => resolver.resolvePayloadForPresentation('pro_upgrade'),
    );
    await _waitUntil(() => bundle.loadedKeys.isNotEmpty);
    current = false;
    bundle.release('assets/paywalls/pro_upgrade.flow.json');

    await expectLater(
      resolved,
      throwsA(isA<StaleSurfaceAssignmentResolution>()),
    );
    expect(server.requests, isEmpty);
    expect(
      bundle.loadedKeys,
      orderedEquals(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]),
    );
  });

  test('presentation disposal during a hosted await cannot publish HLG',
      () async {
    final bundledScreen = _screen('Bundled after disposal');
    final disposedScreen = _screen('Disposed candidate');
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(
        bundle: (_ControlledPaywallBundle()
          ..writeFlow(_flowDocument(screen: bundledScreen))
          ..writeScreen('paywall_pro_upgrade.rfw', bundledScreen)),
      ),
    );
    var current = true;

    final disposed = withPaywallPresentationGuard(
      guard: () => current,
      resolve: () => resolver.resolvePayloadForPresentation('pro_upgrade'),
    );
    await _waitUntil(() => server.requests.length == 1);
    current = false;
    server.requests[0].complete(_surfaceResponse(
      _flowEnvelope(screen: disposedScreen, publishedVersion: 9),
      decision: 'assigned',
      experimentId: 'disposed-experiment',
      variantId: 'disposed-variant',
      experimentEpoch: 1,
    ));
    await expectLater(
      disposed,
      throwsA(isA<StaleSurfaceAssignmentResolution>()),
    );

    current = true;
    final next = resolver.resolvePayloadForPresentation('pro_upgrade');
    await _waitUntil(() => server.requests.length == 2);
    server.requests[1].complete(http.Response('unavailable', 503));
    final payload = await next as FlowPaywallPayload;

    expect(payload.acceptedCandidate, isNull);
    expect(payload.flow.screenBlobs['welcome'], bundledScreen);
    expect(payload.flow.screenBlobs['welcome'], isNot(disposedScreen));
    expect(server.requests, hasLength(2));
  });

  test('action-bearing bundled paywall cannot advertise a strict contract',
      () async {
    final screen = _screen('Action baseline');
    final bundle = _ControlledPaywallBundle()
      ..writeFlow(_actionFlowDocument(screen: screen))
      ..writeScreen('paywall_pro_upgrade.rfw', screen);
    final server = _ControlledSurfaceServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    final resolved = resolver.resolvePayloadForPresentation('pro_upgrade');
    await _waitUntil(() => server.requests.length == 1);
    final request = _requestBody(server.requests.single.request);
    server.requests.single.complete(http.Response('unavailable', 503));
    final payload = await resolved as FlowPaywallPayload;

    expect(request, isNot(contains('flowContractHash')));
    expect(request, isNot(contains('flowContractBytes')));
    expect(payload.acceptedCandidate, isNull);
    expect(payload.experimentId, isNull);
  });

  test('a custom fallback is never preflighted or auto-enrolled', () async {
    final custom = _RecordingCustomFallback();
    final requests = <Map<String, Object?>>[];
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: MockClient((request) async {
        requests.add(_requestBody(request));
        return http.Response('unavailable', 503);
      }),
      assetFallback: custom,
    );

    final payload = await resolver.resolvePayloadForPresentation('pro_upgrade');

    expect(payload, isA<BlobPaywallPayload>());
    expect(custom.calls, 1);
    expect(requests, hasLength(1));
    expect(requests.single, isNot(contains('flowContractHash')));
    expect(requests.single, isNot(contains('flowContractBytes')));
  });
}

MockClient _failingServer(List<String> bodies) {
  return MockClient((request) async {
    bodies.add(request.body);
    return http.Response('unavailable', 503);
  });
}

Map<String, Object?> _requestBody(http.Request request) =>
    (jsonDecode(request.body) as Map).cast<String, Object?>();

http.Response _surfaceResponse(
  Uint8List envelope, {
  String? decision,
  String? experimentId,
  String? variantId,
  int? experimentEpoch,
  bool flowContractRequired = false,
}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'envelope': base64Encode(envelope),
      if (decision != null) 'decision': decision,
      if (experimentId != null) 'experimentId': experimentId,
      if (variantId != null) 'variantId': variantId,
      if (experimentEpoch != null) 'experimentEpoch': experimentEpoch,
      if (flowContractRequired) 'flowContractRequired': true,
    }),
    200,
  );
}

Uint8List _flowEnvelope({
  required Uint8List screen,
  required int publishedVersion,
}) {
  final document = _flowDocument(screen: screen);
  return _flowEnvelopeFor(
    document,
    <String, Uint8List>{'welcome': screen},
    publishedVersion: publishedVersion,
  );
}

Uint8List _flowEnvelopeFor(
  FlowDocument document,
  Map<String, Uint8List> screenBlobs, {
  required int publishedVersion,
}) {
  return SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: Surface.paywall,
    surfaceSlug: document.flow,
    version: publishedVersion,
    minClient: document.minClient,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: screenBlobs,
    ),
    publishedAt: DateTime.utc(2026),
  ));
}

FlowDocument _flowDocument({required Uint8List screen}) {
  return FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: const <String, FlowActionContract>{},
    screenArtifacts: <String, ScreenArtifact>{
      'welcome': ScreenArtifact(
        path: 'paywall_pro_upgrade.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(screen),
      ),
    },
    states: const <String, FlowState>{
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: <String, FlowTransition>{
          'finish': FlowTransition.goto('done'),
        },
      ),
      'done': EndFlowState(result: <String, Object?>{}),
    },
  );
}

FlowDocument _actionFlowDocument({required Uint8List screen}) {
  return FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: const <String, FlowActionContract>{
      'grant': FlowActionContract(
        actionName: 'grant',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: FlowActionSchema.bool(),
        minClient: 3,
        idempotent: false,
      ),
    },
    screenArtifacts: <String, ScreenArtifact>{
      'welcome': ScreenArtifact(
        path: 'paywall_pro_upgrade.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(screen),
      ),
    },
    states: const <String, FlowState>{
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: <String, FlowTransition>{
          'finish': ActionFlowTransition(
            action: 'grant',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: <String, Object?>{}),
    },
  );
}

FlowDocument _childFlowDocument({required Uint8List screen}) {
  return FlowDocument(
    flow: 'child',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'screen',
    actions: const <String, FlowActionContract>{},
    screenArtifacts: <String, ScreenArtifact>{
      'screen': ScreenArtifact(
        path: 'child.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(screen),
      ),
    },
    states: const <String, FlowState>{
      'screen': ScreenFlowState(
        screen: 'screen',
        on: <String, FlowTransition>{
          'finish': FlowTransition.goto('done'),
        },
      ),
      'done': EndFlowState(result: <String, Object?>{}),
    },
  );
}

FlowDocument _rootWithChildDocument({
  required Uint8List screen,
  required FlowDocument child,
}) {
  return FlowDocument(
    flow: 'pro_upgrade',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'welcome',
    actions: const <String, FlowActionContract>{},
    screenArtifacts: <String, ScreenArtifact>{
      'welcome': ScreenArtifact(
        path: 'root.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(screen),
      ),
    },
    states: <String, FlowState>{
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: <String, FlowTransition>{
          'next': FlowTransition.goto('child'),
        },
      ),
      'child': SubFlowState(
        flow: child.flow,
        version: child.version,
        schemaVersion: child.schemaVersion,
        minClient: child.minClient,
        contentHash: FlowContentHash.compute(
          FlowDocumentCodec.encodeCanonicalJson(child),
        ),
        input: const {},
        onComplete: const [],
        defaultBranch: const FlowBranchTarget(target: 'done'),
      ),
      'done': const EndFlowState(result: <String, Object?>{}),
    },
  );
}

Map<String, Object?> _identityResult(Map<String, Object?> value) => value;

Uint8List _screen(String text) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "finish" {},
      child: Text(text: "$text")
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

final class _ControlledSurfaceServer {
  _ControlledSurfaceServer() {
    client = MockClient((request) {
      final pending = _PendingSurfaceRequest(request);
      requests.add(pending);
      return pending.response.future;
    });
  }

  late final MockClient client;
  final List<_PendingSurfaceRequest> requests = <_PendingSurfaceRequest>[];
}

final class _RecordingCustomFallback implements VariantResolver {
  int calls = 0;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    calls += 1;
    return ResolvedVariant(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      paywallId: id,
    );
  }
}

final class _PendingSurfaceRequest {
  _PendingSurfaceRequest(this.request);

  final http.Request request;
  final Completer<http.Response> response = Completer<http.Response>();

  void complete(http.Response value) => response.complete(value);
}

final class _ControlledPaywallBundle extends CachingAssetBundle {
  final Map<String, Uint8List> _assets = <String, Uint8List>{};
  final Map<String, Completer<void>> _holds = <String, Completer<void>>{};
  final List<String> loadedKeys = <String>[];

  void writeFlow(FlowDocument document) {
    _assets['assets/paywalls/${document.flow}.flow.json'] =
        Uint8List.fromList(utf8.encode(FlowDocumentCodec.encodePrettyJson(
      document,
    )));
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/paywalls/screens/$path'] = Uint8List.fromList(bytes);
  }

  void writeBlob(String id, Uint8List bytes) {
    _assets['assets/paywalls/$id.rfw'] = Uint8List.fromList(bytes);
  }

  void hold(String key) {
    _holds[key] = Completer<void>();
  }

  void release(String key) {
    _holds[key]!.complete();
  }

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final hold = _holds[key];
    if (hold != null) await hold.future;
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
