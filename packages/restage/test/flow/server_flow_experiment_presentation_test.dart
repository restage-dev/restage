import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_experiment_mount.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_shared/flow_experiment.dart'
    show FlowExperimentClientContractV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_abc123';
const _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const _refFloor = _installed + 2;

const _flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _refFloor,
  decodeResult: _decodeMapResult,
);

void main() {
  setUp(Restage.debugReset);

  testWidgets(
      'contract cache miss uploads the sealed bytes once and retries once',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Candidate', 'next');
    final candidateEnvelope = _envelope(
      _screenDocument(version: 2, screenBytes: candidateBytes),
      {'welcome': candidateBytes},
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    final warm = _requestBody(server.requests[0]);
    expect(warm['assignmentKey'], 'actor-a');
    expect(warm['flowContractHash'], startsWith('sha256:'));
    expect(warm.containsKey('flowContractBytes'), isFalse);

    server.respondJson(0, {
      ..._assignedBody(candidateEnvelope),
      'flowContractRequired': true,
    });
    await _waitFor(() => server.requests.length == 2);
    final retry = _requestBody(server.requests[1]);
    expect(retry['assignmentKey'], warm['assignmentKey']);
    expect(retry['flowContractHash'], warm['flowContractHash']);
    final uploaded = base64Url.decode(
      base64Url.normalize(retry['flowContractBytes']! as String),
    );
    expect(
      FlowExperimentClientContractV1.decode(uploaded).contentHash.value,
      warm['flowContractHash'],
    );

    server.respondJson(1, _assignedBody(candidateEnvelope));
    await tester.pumpAndSettle();

    expect(find.text('Candidate'), findsOneWidget);
    expect(server.requests, hasLength(2));
  });

  testWidgets('a repeated contract miss never creates a third request',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Candidate', 'next');
    final candidateEnvelope = _envelope(
      _screenDocument(version: 2, screenBytes: candidateBytes),
      {'welcome': candidateBytes},
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(0, {
      ..._assignedBody(candidateEnvelope),
      'flowContractRequired': true,
    });
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(1, {
      ..._assignedBody(candidateEnvelope),
      'flowContractRequired': true,
    });
    await tester.pumpAndSettle();

    expect(find.text('Bundled'), findsOneWidget);
    expect(find.text('Candidate'), findsNothing);
    expect(server.requests, hasLength(2));
  });

  testWidgets(
      'identity drift during metering lookup publishes no stale warm request',
      (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    addTearDown(SurfaceMeteringKeyProvider.clear);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Fresh candidate', 'next');
    final candidateEnvelope = _envelope(
      _screenDocument(version: 2, screenBytes: candidateBytes),
      {'welcome': candidateBytes},
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => meteringLookups == 1);
    final requestsBeforeMeteringCompleted = server.requests.length;
    actorGeneration = 1;
    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.isNotEmpty);

    final firstKey = _requestBody(server.requests[0])['assignmentKey'];
    server.respondJson(0, _assignedBody(candidateEnvelope));
    if (firstKey == 'actor-0') {
      await _waitFor(() => server.requests.length == 2);
      server.respondJson(1, _assignedBody(candidateEnvelope));
    }
    await tester.pumpAndSettle();

    final observed = (
      requestBodies: server.requests.map(_requestBody).toList(),
      candidate: find.text('Fresh candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(requestsBeforeMeteringCompleted, 0);
    expect(observed.requestBodies, hasLength(1));
    expect(observed.requestBodies.single['assignmentKey'], 'actor-1');
    expect(observed.candidate, 1);
  });

  testWidgets(
      'identity drift during retry metering lookup publishes no stale upload',
      (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    addTearDown(SurfaceMeteringKeyProvider.clear);
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Fresh retry candidate', 'next');
    final candidateEnvelope = _envelope(
      _screenDocument(version: 2, screenBytes: candidateBytes),
      {'welcome': candidateBytes},
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    server.respondJson(0, {
      ..._assignedBody(candidateEnvelope),
      'flowContractRequired': true,
    });
    await _waitFor(() => meteringLookups == 1);
    final requestsBeforeMeteringCompleted = server.requests.length;
    actorGeneration = 1;
    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length >= 2);

    final secondBody = _requestBody(server.requests[1]);
    server.respondJson(1, _assignedBody(candidateEnvelope));
    if (secondBody['assignmentKey'] == 'actor-0') {
      await _waitFor(() => server.requests.length == 3);
      server.respondJson(2, _assignedBody(candidateEnvelope));
    }
    await tester.pumpAndSettle();

    final observed = (
      requestBodies: server.requests.map(_requestBody).toList(),
      candidate: find.text('Fresh retry candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(requestsBeforeMeteringCompleted, 1);
    expect(observed.requestBodies, hasLength(2));
    expect(
      observed.requestBodies.map((body) => body['assignmentKey']),
      ['actor-0', 'actor-1'],
    );
    expect(observed.requestBodies[1].containsKey('flowContractBytes'), isFalse);
    expect(observed.candidate, 1);
  });

  test(
      'a throwing production recapture is typed and restarts without a stale '
      'publish', () async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    addTearDown(SurfaceMeteringKeyProvider.clear);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );
    final source = FlowMountRuntimeSeedSource(
      flow: _flowRef,
      actions: null,
      installedSignalNames: const {},
    );
    var throwNextCapture = false;
    FlowMountLeaseSeed captureSeed() {
      if (throwNextCapture) {
        throwNextCapture = false;
        actorGeneration = 1;
        throw StateError('recapture failed');
      }
      return source.capture();
    }

    final presentation = resolver.createExperimentPresentation(
      flow: _flowRef,
      captureSeed: captureSeed,
    );
    addTearDown(presentation.disposePresentation);
    final resolvedFuture = presentation.resolveActiveRoot(_flowRef);
    await _waitFor(() => meteringLookups == 1);
    throwNextCapture = true;
    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length == 1);
    server.respondNotFound(0);
    final outcome =
        await resolvedFuture.then<({Object? error, ResolvedFlow? resolved})>(
      (resolved) => (resolved: resolved, error: null),
      onError: (Object error) => (resolved: null, error: error),
    );

    expect(outcome.error, isNull);
    expect(outcome.resolved, isNotNull);
    expect(_requestBody(server.requests.single)['assignmentKey'], 'actor-1');
    expect(server.requests, hasLength(1));
  });

  testWidgets(
      'candidate root waits for its exact child and later uses only the pinned '
      'closure', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final baselineRootBytes = screenBlob('Bundled root', 'next');
    final candidateRootBytes = screenBlob('Candidate root', 'next');
    final candidateChildBytes = screenBlob('Pinned child', 'next');
    final baselineChild = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: candidateChildBytes,
    );
    final baselineRoot = _screenThenChildDocument(
      child: baselineChild,
      screenBytes: baselineRootBytes,
    );
    final candidateRoot = _screenThenChildDocument(
      version: 2,
      child: baselineChild,
      screenBytes: candidateRootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, baselineChild],
        screenAssets: {
          'root.rfw': baselineRootBytes,
          'child.rfw': candidateChildBytes,
        },
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(
        _envelope(candidateRoot, {'welcome': candidateRootBytes}),
      ),
    );
    await _waitFor(() => server.requests.length == 2);

    await tester.pump();
    final candidateBeforeChild = find.text('Candidate root').evaluate().length;
    final rootRequest = _requestBody(server.requests[0]);
    final childRequest = _requestBody(server.requests[1]);

    server.respondJson(
      1,
      _unassignedBody(
        _envelope(baselineChild, {'screen': candidateChildBytes}),
      ),
    );
    await tester.pumpAndSettle();

    final observed = (
      candidateBeforeChild: candidateBeforeChild,
      candidateAfterChild: find.text('Candidate root').evaluate().length,
      bundledAfterChild: find.text('Bundled root').evaluate().length,
      requestCount: server.requests.length,
      texts: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .toList(),
    );
    await tester.tap(find.text('Candidate root'));
    await tester.pumpAndSettle();
    final pinnedChild = find.text('Pinned child').evaluate().length;
    final finalRequestCount = server.requests.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.candidateBeforeChild, 0);
    expect(rootRequest.containsKey('version'), isFalse);
    expect(childRequest, {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
    });
    expect(
      observed.candidateAfterChild,
      1,
      reason: '${observed.texts}',
    );
    expect(observed.bundledAfterChild, 0);
    expect(observed.requestCount, 2);
    expect(pinnedChild, 1);
    expect(finalRequestCount, 2);
  });

  test(
      'identity reset during exact-child metering lookup publishes no child '
      'request, exact cache, or HLG', () async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    addTearDown(SurfaceMeteringKeyProvider.clear);
    final rootBytes = screenBlob('Candidate root', 'next');
    final bundledBytes = screenBlob('Bundled root', 'next');
    final childBytes = screenBlob('Candidate child', 'next');
    final child = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: childBytes,
    );
    final childRef = OnboardingFlowRef<Object?>(
      id: child.flow,
      version: child.version,
      minClient: child.minClient,
      decodeResult: _decodeMapResult,
    );
    final baselineRoot = _screenThenChildDocument(
      child: child,
      screenBytes: bundledBytes,
    );
    final candidateRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: rootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, child],
        screenAssets: {
          'root.rfw': bundledBytes,
          'child.rfw': childBytes,
        },
      ),
      httpClient: server.client,
    );
    final source = FlowMountRuntimeSeedSource(
      flow: _flowRef,
      actions: null,
      installedSignalNames: const {},
    );
    final presentation = resolver.createExperimentPresentation(
      flow: _flowRef,
      captureSeed: source.capture,
    );
    addTearDown(presentation.disposePresentation);

    final resolvedFuture = presentation.resolveActiveRoot(_flowRef);
    await _waitFor(() => server.requests.length == 1);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    server.respondJson(
      0,
      _assignedBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);

    actorGeneration += 1;
    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length >= 2);
    final secondBody = _requestBody(server.requests[1]);
    if (secondBody['surfaceSlug'] == 'child') {
      server.respondJson(
        1,
        _unassignedBody(_envelope(child, {'screen': childBytes})),
      );
      await _waitFor(() => server.requests.length == 3);
      server.respondNotFound(2);
    } else {
      server.respondNotFound(1);
    }
    final resolved = await resolvedFuture;

    presentation.publishHostedLastGood();
    final beforeExactProbe = server.requests.length;
    final exactProbe = resolver.resolve<Object?>(childRef);
    await _waitFor(() => server.requests.length > beforeExactProbe);
    server.respondJson(
      beforeExactProbe,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    await exactProbe;
    final exactProbePublished = server.requests.length == beforeExactProbe + 1;

    final nextPresentation = resolver.createExperimentPresentation(
      flow: _flowRef,
      captureSeed: source.capture,
    );
    addTearDown(nextPresentation.disposePresentation);
    final beforeNextPresentation = server.requests.length;
    final next = nextPresentation.resolveActiveRoot(_flowRef);
    await _waitFor(() => server.requests.length > beforeNextPresentation);
    server.respondNotFound(server.requests.length - 1);
    final nextRoot = await next;

    expect(secondBody['surfaceSlug'], 'first_run');
    expect(secondBody.containsKey('version'), isFalse);
    expect(exactProbePublished, isTrue);
    expect(resolved.document.version, baselineRoot.version);
    expect(resolved.assignment, isNull);
    expect(nextRoot.document.version, baselineRoot.version);
    expect(nextRoot.assignment, isNull);
  });

  test(
      'disposing during exact-child metering lookup publishes no child request '
      'or exact cache entry', () async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    addTearDown(SurfaceMeteringKeyProvider.clear);
    final rootBytes = screenBlob('Disposed root', 'next');
    final bundledBytes = screenBlob('Bundled root', 'next');
    final childBytes = screenBlob('Disposed child', 'next');
    final child = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: childBytes,
    );
    final childRef = OnboardingFlowRef<Object?>(
      id: child.flow,
      version: child.version,
      minClient: child.minClient,
      decodeResult: _decodeMapResult,
    );
    final baselineRoot = _screenThenChildDocument(
      child: child,
      screenBytes: bundledBytes,
    );
    final candidateRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: rootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, child],
        screenAssets: {
          'root.rfw': bundledBytes,
          'child.rfw': childBytes,
        },
      ),
      httpClient: server.client,
    );
    final source = FlowMountRuntimeSeedSource(
      flow: _flowRef,
      actions: null,
      installedSignalNames: const {},
    );
    final presentation = resolver.createExperimentPresentation(
      flow: _flowRef,
      captureSeed: source.capture,
    );

    var resolutionDone = false;
    final resolvedFuture = presentation
        .resolveActiveRoot(_flowRef)
        .then(
          (_) => null,
          onError: (_) => null,
        )
        .whenComplete(() => resolutionDone = true);
    await _waitFor(() => server.requests.length == 1);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    server.respondJson(
      0,
      _assignedBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);

    presentation.disposePresentation();
    meteringReady.complete(preferences);
    await _waitFor(() => resolutionDone || server.requests.length > 1);
    final childPublished = server.requests.length > 1;
    if (childPublished) {
      server.respondJson(
        1,
        _unassignedBody(_envelope(child, {'screen': childBytes})),
      );
    }
    await resolvedFuture;

    final beforeExactProbe = server.requests.length;
    final exactProbe = resolver.resolve<Object?>(childRef);
    await _waitFor(() => server.requests.length > beforeExactProbe);
    server.respondJson(
      beforeExactProbe,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    await exactProbe;

    expect(childPublished, isFalse);
    expect(server.requests.length, beforeExactProbe + 1);
  });

  test(
      'current exact-child metering lookup publishes, caches, and pins the '
      'complete candidate closure', () async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    addTearDown(SurfaceMeteringKeyProvider.clear);
    final rootBytes = screenBlob('Current root', 'next');
    final bundledBytes = screenBlob('Bundled root', 'next');
    final childBytes = screenBlob('Current child', 'next');
    final child = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: childBytes,
    );
    final childRef = OnboardingFlowRef<Object?>(
      id: child.flow,
      version: child.version,
      minClient: child.minClient,
      decodeResult: _decodeMapResult,
    );
    final baselineRoot = _screenThenChildDocument(
      child: child,
      screenBytes: bundledBytes,
    );
    final candidateRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: rootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, child],
        screenAssets: {
          'root.rfw': bundledBytes,
          'child.rfw': childBytes,
        },
      ),
      httpClient: server.client,
    );
    final source = FlowMountRuntimeSeedSource(
      flow: _flowRef,
      actions: null,
      installedSignalNames: const {},
    );
    final presentation = resolver.createExperimentPresentation(
      flow: _flowRef,
      captureSeed: source.capture,
    );
    addTearDown(presentation.disposePresentation);

    final resolvedFuture = presentation.resolveActiveRoot(_flowRef);
    await _waitFor(() => server.requests.length == 1);
    SharedPreferences.setMockInitialValues(const {
      'restage.metering_token': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    final preferences = await SharedPreferences.getInstance();
    final meteringReady = Completer<SharedPreferences>();
    var meteringLookups = 0;
    SurfaceMeteringKeyProvider.install(
      store: MeteringTokenStore(
        prefsProvider: () {
          meteringLookups += 1;
          return meteringReady.future;
        },
      ),
    );
    server.respondJson(
      0,
      _assignedBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);
    expect(server.requests, hasLength(1));

    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length == 2);
    final childRequest = _requestBody(server.requests[1]);
    server.respondJson(
      1,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    final root = await resolvedFuture;
    final pinnedChild = await presentation.resolve<Object?>(childRef);
    presentation.publishHostedLastGood();

    final beforeCacheProbe = server.requests.length;
    final cachedChild = await resolver.resolve<Object?>(childRef);

    expect(childRequest, {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
      'meteringKey': 'd9428888-122b-4b0b-8b7f-3e23441121e8',
    });
    expect(
      root.contentHash,
      FlowContentHash.compute(
        FlowDocumentCodec.encodeCanonicalJson(candidateRoot),
      ),
    );
    expect(
      pinnedChild.contentHash,
      FlowContentHash.compute(FlowDocumentCodec.encodeCanonicalJson(child)),
    );
    expect(cachedChild.contentHash, pinnedChild.contentHash);
    expect(server.requests, hasLength(beforeCacheProbe));
  });

  testWidgets('local child-closure parity rejection falls back unassigned',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final baselineChildBytes = screenBlob('Bundled child', 'next');
    final candidateChildBytes = screenBlob('Rejected child', 'next');
    final baselineChild = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: baselineChildBytes,
    );
    final candidateChild = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: candidateChildBytes,
      terminalResult: const {'completed': true, 'extra': 1},
    );
    final baselineRoot = _parentDocument(child: baselineChild);
    final candidateRoot = _parentDocument(version: 2, child: candidateChild);
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, baselineChild],
        screenAssets: {'child.rfw': baselineChildBytes},
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(candidateRoot, const {})),
    );
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(
      1,
      _unassignedBody(
        _envelope(candidateChild, {'screen': candidateChildBytes}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bundled child'), findsOneWidget);
    expect(find.text('Rejected child'), findsNothing);
    expect(server.requests, hasLength(2));
  });

  testWidgets('successful paint publishes the exact assigned artifact as HLG',
      (tester) async {
    final analyticsRequests = <http.Request>[];
    _configureAnalytics(analyticsRequests);
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Painted candidate', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('Painted candidate'), findsOneWidget);
    final freshPresentations =
        _canonicalEvents(await _capturedAnalytics(analyticsRequests));
    expect(freshPresentations, hasLength(1));
    final freshSession = freshPresentations.single['surfaceSessionId'];
    analyticsRequests.clear();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    expect(find.text('Painted candidate'), findsOneWidget);
    expect(find.text('Bundled'), findsNothing);
    expect(server.requests, hasLength(2));
    final hlgPresentations =
        _canonicalEvents(await _capturedAnalytics(analyticsRequests));
    expect(hlgPresentations, hasLength(1));
    expect(hlgPresentations.single['surface'], 'onboarding');
    expect(hlgPresentations.single['surfaceId'], 'first_run');
    expect(hlgPresentations.single['surfaceVersion'], '2');
    expect(hlgPresentations.single['surfaceSessionId'], isNot(freshSession));
    expect(hlgPresentations.single['experimentId'], 'exp_copy');
    expect(hlgPresentations.single['variantId'], 'variant_a');
    expect(hlgPresentations.single['experimentEpoch'], 3);
  });

  testWidgets(
      'HLG is rejected when the exact assignment key changes without '
      'generation drift', (tester) async {
    final analyticsRequests = <http.Request>[];
    _configureAnalytics(analyticsRequests);
    var assignmentKey = 'actor-a';
    SurfaceAssignmentKeyProvider.install(
      key: () => assignmentKey,
      identityGeneration: () => 0,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Actor A candidate', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('Actor A candidate'), findsOneWidget);
    expect(
      _canonicalEvents(await _capturedAnalytics(analyticsRequests)),
      hasLength(1),
    );
    analyticsRequests.clear();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    assignmentKey = 'actor-b';
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    final observed = (
      assignmentKey: _requestBody(server.requests[1])['assignmentKey'],
      bundled: find.text('Bundled').evaluate().length,
      stale: find.text('Actor A candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.assignmentKey, 'actor-b');
    expect(observed.bundled, 1);
    expect(observed.stale, 0);
    final bundledPresentations =
        _canonicalEvents(await _capturedAnalytics(analyticsRequests));
    expect(bundledPresentations, hasLength(1));
    expect(bundledPresentations.single['surface'], 'onboarding');
    expect(bundledPresentations.single['surfaceId'], 'first_run');
    expect(bundledPresentations.single['surfaceVersion'], '1');
    expect(bundledPresentations.single['surfaceSessionId'], isNotNull);
    expect(bundledPresentations.single['experimentId'], isNull);
    expect(bundledPresentations.single['variantId'], isNull);
    expect(bundledPresentations.single['experimentEpoch'], isNull);
  });

  testWidgets(
      'HLG is rejected when the exact contract hash changes without seed '
      'drift', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledABytes = screenBlob('Bundled A', 'next');
    final bundledBBytes = screenBlob('Bundled B', 'next');
    final candidateBytes = screenBlob('Contract A candidate', 'next');
    final bundleAssets = _bundleAssets(
      surfaceType: SurfaceType.onboarding,
      documents: [_screenDocument(screenBytes: bundledABytes)],
      screenAssets: {'welcome.rfw': bundledABytes},
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _TestBundle(bundleAssets),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    final firstHash =
        _requestBody(server.requests[0])['flowContractHash']! as String;
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contract A candidate'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    bundleAssets
      ..clear()
      ..addAll(_bundleAssets(
        surfaceType: SurfaceType.onboarding,
        documents: [_screenDocument(screenBytes: bundledBBytes)],
        screenAssets: {'welcome.rfw': bundledBBytes},
      ));
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    final secondHash =
        _requestBody(server.requests[1])['flowContractHash']! as String;
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    final observed = (
      bundled: find.text('Bundled B').evaluate().length,
      stale: find.text('Contract A candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(secondHash, isNot(firstHash));
    expect(observed.bundled, 1);
    expect(observed.stale, 0);
  });

  test('HLG marks the complete pinned root and child closure as cache hits',
      () async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    const rootRef = OnboardingFlowRef<Object?>(
      id: 'first_run',
      version: 1,
      minClient: _refFloor,
      decodeResult: _decodeMapResult,
    );
    const childRef = OnboardingFlowRef<Object?>(
      id: 'child',
      version: 1,
      minClient: _refFloor,
      decodeResult: _decodeMapResult,
    );
    final baselineRootBytes = screenBlob('Bundled root', 'next');
    final candidateRootBytes = screenBlob('Candidate root', 'next');
    final childBytes = screenBlob('Pinned child', 'next');
    final child = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: childBytes,
    );
    final baselineRoot = _screenThenChildDocument(
      child: child,
      screenBytes: baselineRootBytes,
    );
    final candidateRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: candidateRootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [baselineRoot, child],
        screenAssets: {
          'root.rfw': baselineRootBytes,
          'child.rfw': childBytes,
        },
      ),
      httpClient: server.client,
    );

    FlowExperimentPresentationResolver createPresentation() {
      final source = FlowMountRuntimeSeedSource(
        flow: rootRef,
        actions: null,
        installedSignalNames: const {},
      );
      return resolver.createExperimentPresentation(
        flow: rootRef,
        captureSeed: source.capture,
      );
    }

    final freshPresentation = createPresentation();
    final freshRootFuture =
        freshPresentation.resolveActiveRoot<Object?>(rootRef);
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(
        _envelope(candidateRoot, {'welcome': candidateRootBytes}),
      ),
    );
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(
      1,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    final freshRoot = await freshRootFuture;
    final freshChild = await freshPresentation.resolve<Object?>(childRef);
    freshPresentation.publishHostedLastGood();

    final heldPresentation = createPresentation();
    final heldRootFuture = heldPresentation.resolveActiveRoot<Object?>(rootRef);
    await _waitFor(() => server.requests.length == 3);
    server.respondNotFound(2);
    final heldRoot = await heldRootFuture;
    final heldChild = await heldPresentation.resolve<Object?>(childRef);

    expect(freshRoot.cacheHit, isFalse);
    expect(freshChild.cacheHit, isFalse);
    expect(heldRoot.cacheHit, isTrue);
    expect(heldChild.cacheHit, isTrue);
    expect(heldRoot.contentHash, freshRoot.contentHash);
    expect(heldChild.contentHash, freshChild.contentHash);
    expect(
      FlowDocumentCodec.encodeCanonicalJson(heldRoot.document),
      orderedEquals(FlowDocumentCodec.encodeCanonicalJson(freshRoot.document)),
    );
    expect(
      FlowDocumentCodec.encodeCanonicalJson(heldChild.document),
      orderedEquals(FlowDocumentCodec.encodeCanonicalJson(freshChild.document)),
    );
    expect(
      heldRoot.screenBlobs['welcome'],
      orderedEquals(freshRoot.screenBlobs['welcome']!),
    );
    expect(
      heldChild.screenBlobs['screen'],
      orderedEquals(freshChild.screenBlobs['screen']!),
    );
    expect(heldRoot.assignment, freshRoot.assignment);
    expect(heldChild.assignment, freshChild.assignment);
    expect(server.requests, hasLength(3));
  });

  testWidgets(
      'an assigned response cannot create authority without a sealed '
      'assignment key', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => null;
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Unauthorized candidate', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    final request = _requestBody(server.requests.single);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();

    final observed = (
      bundled: find.text('Bundled').evaluate().length,
      unauthorized: find.text('Unauthorized candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(request.containsKey('assignmentKey'), isFalse);
    expect(observed.bundled, 1);
    expect(observed.unauthorized, 0);
  });

  testWidgets(
      'three snapshot-sealing drifts restart once into bundled fallback',
      (tester) async {
    var actorGeneration = 0;
    var keyResolutionAttempts = 0;
    final globalEvents = <RestageEvent>[];
    final unavailableErrors = <FlowUnavailableError>[];
    final subscription = Restage.events.listen(globalEvents.add);
    addTearDown(subscription.cancel);
    SurfaceAssignmentKeyProvider.install(
      key: () {
        keyResolutionAttempts += 1;
        actorGeneration += 1;
        return 'actor-$actorGeneration';
      },
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(
      resolver,
      onFlowUnavailable: unavailableErrors.add,
    ));
    await tester.pumpAndSettle();

    final observed = (
      bundled: find.text('Bundled').evaluate().length,
      unavailable:
          find.text('UNAVAILABLE:unstable_mount_identity').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(keyResolutionAttempts, 3);
    expect(server.requests, isEmpty);
    expect(globalEvents.whereType<FlowUnavailable>(), isEmpty);
    expect(unavailableErrors, isEmpty);
    expect(observed.unavailable, 0);
    expect(observed.bundled, 1);
  });

  testWidgets('disposing an in-flight request cannot publish HLG',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Disposed candidate', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.idle();

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    expect(find.text('Bundled'), findsOneWidget);
    expect(find.text('Disposed candidate'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a painted assigned root locks refresh before another fetch',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Assigned', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();

    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();

    expect(find.text('Assigned'), findsOneWidget);
    expect(server.requests, hasLength(1));
  });

  testWidgets(
      'an installed assigned root locks refresh before its frame commits',
      (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Installed assigned', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    // Let the assigned artifact install without drawing its scheduled frame.
    await tester.idle();

    final refresh = Restage.reloadSurfaces();
    await tester.idle();
    final requestCountBeforePaint = server.requests.length;
    server.completeOutstandingWithNotFound();
    await refresh;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(requestCountBeforePaint, 1);
  });

  testWidgets(
      'refresh may fetch but cannot stage, promote, or publish a newly assigned '
      'candidate', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledBytes = screenBlob('Bundled', 'next');
    final currentBytes = screenBlob('Current unassigned', 'next');
    final candidateBytes = screenBlob('Refresh assigned', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _unassignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: currentBytes),
        {'welcome': currentBytes},
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current unassigned'), findsOneWidget);

    await Restage.reloadSurfaces();
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(
      1,
      _assignedBody(_envelope(
        _screenDocument(version: 3, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();
    final afterRefresh = (
      current: find.text('Current unassigned').evaluate().length,
      candidate: find.text('Refresh assigned').evaluate().length,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 3);
    server.respondNotFound(2);
    await tester.pumpAndSettle();
    final afterRemount = (
      current: find.text('Current unassigned').evaluate().length,
      candidate: find.text('Refresh assigned').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(afterRefresh.current, 1);
    expect(afterRefresh.candidate, 0);
    expect(afterRemount.current, 1);
    expect(afterRemount.candidate, 0);
  });

  testWidgets(
      'reset after paint leaves the mounted UI pinned but rejects its HLG for '
      'the next actor', (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final candidateBytes = screenBlob('Painted actor zero', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();

    actorGeneration += 1;
    FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
    await tester.pump();
    final paintedAfterReset = find.text('Painted actor zero').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    expect(paintedAfterReset, 1);
    expect(find.text('Bundled'), findsOneWidget);
    expect(find.text('Painted actor zero'), findsNothing);
    expect(_requestBody(server.requests[1])['assignmentKey'], 'actor-1');
  });

  testWidgets(
      'concurrent message and survey roots with the same slug keep request, '
      'snapshot, and paint authority isolated', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    const messageRef = OnboardingFlowRef<Map<String, Object?>>(
      id: 'first_run',
      version: 1,
      minClient: _refFloor,
      surfaceType: SurfaceType.message,
      decodeResult: _decodeMapResult,
    );
    const surveyRef = OnboardingFlowRef<Map<String, Object?>>(
      id: 'first_run',
      version: 1,
      minClient: _refFloor,
      surfaceType: SurfaceType.survey,
      decodeResult: _decodeMapResult,
    );
    final messageBundled = screenBlob('Message bundled', 'next');
    final surveyBundled = screenBlob('Survey bundled', 'next');
    final messageCandidate = screenBlob('Message candidate', 'next');
    final surveyCandidate = screenBlob('Survey candidate', 'next');
    final bundle = _TestBundle({
      ..._bundleAssets(
        surfaceType: SurfaceType.message,
        documents: [_screenDocument(screenBytes: messageBundled)],
        screenAssets: {'welcome.rfw': messageBundled},
      ),
      ..._bundleAssets(
        surfaceType: SurfaceType.survey,
        documents: [_screenDocument(screenBytes: surveyBundled)],
        screenAssets: {'welcome.rfw': surveyBundled},
      ),
    });
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: bundle,
      httpClient: server.client,
    );

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          Expanded(
            child: RestageSurfaceFlow<Map<String, Object?>>(
              flow: messageRef,
              resolver: resolver,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
          ),
          Expanded(
            child: RestageSurfaceFlow<Map<String, Object?>>(
              flow: surveyRef,
              resolver: resolver,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
          ),
        ],
      ),
    ));
    await _waitFor(() => server.requests.length == 2);
    final messageIndex = server.requests.indexWhere(
      (request) => _requestBody(request)['surfaceType'] == 'message',
    );
    final surveyIndex = server.requests.indexWhere(
      (request) => _requestBody(request)['surfaceType'] == 'survey',
    );
    final messageHash =
        _requestBody(server.requests[messageIndex])['flowContractHash'];
    final surveyHash =
        _requestBody(server.requests[surveyIndex])['flowContractHash'];

    server.respondJson(
      surveyIndex,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: surveyCandidate),
        {'welcome': surveyCandidate},
        surfaceType: SurfaceType.survey,
      )),
    );
    await tester.pumpAndSettle();
    final afterSurvey = (
      survey: find.text('Survey candidate').evaluate().length,
      message: find.text('Message candidate').evaluate().length,
    );

    server.respondJson(
      messageIndex,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: messageCandidate),
        {'welcome': messageCandidate},
        surfaceType: SurfaceType.message,
      )),
    );
    await tester.pumpAndSettle();

    final observed = (
      message: find.text('Message candidate').evaluate().length,
      survey: find.text('Survey candidate').evaluate().length,
      requestCount: server.requests.length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(messageIndex, isNonNegative);
    expect(surveyIndex, isNonNegative);
    expect(messageHash, isNot(surveyHash));
    expect(afterSurvey.survey, 1);
    expect(afterSurvey.message, 0);
    expect(observed.message, 1);
    expect(observed.survey, 1);
    expect(observed.requestCount, 2);
  });

  testWidgets('stale request completion restarts under the new generation',
      (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final staleBytes = screenBlob('Stale candidate', 'next');
    final freshBytes = screenBlob('Fresh candidate', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    actorGeneration += 1;
    server.respondJson(
      0,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: staleBytes),
        {'welcome': staleBytes},
      )),
    );
    await _waitFor(() => server.requests.length == 2);
    final staleKey = _requestBody(server.requests[0])['assignmentKey'];
    final freshKey = _requestBody(server.requests[1])['assignmentKey'];

    server.respondJson(
      1,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: freshBytes),
        {'welcome': freshBytes},
      )),
    );
    await tester.pumpAndSettle();

    expect(staleKey, 'actor-0');
    expect(freshKey, 'actor-1');
    expect(find.text('Fresh candidate'), findsOneWidget);
    expect(find.text('Stale candidate'), findsNothing);
  });

  testWidgets('generation drift during upload retry rejects both old responses',
      (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final staleBytes = screenBlob('Stale retry', 'next');
    final freshBytes = screenBlob('Fresh retry', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    final staleEnvelope = _envelope(
      _screenDocument(version: 2, screenBytes: staleBytes),
      {'welcome': staleBytes},
    );
    server.respondJson(0, {
      ..._assignedBody(staleEnvelope),
      'flowContractRequired': true,
    });
    await _waitFor(() => server.requests.length == 2);

    actorGeneration += 1;
    server.respondJson(1, _assignedBody(staleEnvelope));
    await _waitFor(() => server.requests.length == 3);
    final requestBodies = server.requests.map(_requestBody).toList();

    server.respondJson(
      2,
      _assignedBody(_envelope(
        _screenDocument(version: 2, screenBytes: freshBytes),
        {'welcome': freshBytes},
      )),
    );
    await tester.pumpAndSettle();

    expect(requestBodies[0]['assignmentKey'], 'actor-0');
    expect(requestBodies[1]['assignmentKey'], 'actor-0');
    expect(requestBodies[1].containsKey('flowContractBytes'), isTrue);
    expect(requestBodies[2]['assignmentKey'], 'actor-1');
    expect(requestBodies[2].containsKey('flowContractBytes'), isFalse);
    expect(find.text('Fresh retry'), findsOneWidget);
    expect(find.text('Stale retry'), findsNothing);
  });

  testWidgets(
      'generation drift during exact-child prefetch rejects the stale root '
      'before paint', (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledRootBytes = screenBlob('Bundled root', 'next');
    final staleRootBytes = screenBlob('Stale root', 'next');
    final freshRootBytes = screenBlob('Fresh root', 'next');
    final childBytes = screenBlob('Pinned child', 'next');
    final child = _screenDocument(
      flow: 'child',
      screenId: 'screen',
      artifactPath: 'child.rfw',
      screenBytes: childBytes,
    );
    final bundledRoot = _screenThenChildDocument(
      child: child,
      screenBytes: bundledRootBytes,
    );
    final staleRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: staleRootBytes,
    );
    final freshRoot = _screenThenChildDocument(
      version: 2,
      child: child,
      screenBytes: freshRootBytes,
    );
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleForClosure(
        surfaceType: SurfaceType.onboarding,
        documents: [bundledRoot, child],
        screenAssets: {
          'root.rfw': bundledRootBytes,
          'child.rfw': childBytes,
        },
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _assignedBody(_envelope(staleRoot, {'welcome': staleRootBytes})),
    );
    await _waitFor(() => server.requests.length == 2);

    actorGeneration += 1;
    server.respondJson(
      1,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    await _waitFor(() => server.requests.length == 3);
    final requestBodies = server.requests.map(_requestBody).toList();

    server.respondJson(
      2,
      _assignedBody(_envelope(freshRoot, {'welcome': freshRootBytes})),
    );
    await _waitFor(() => server.requests.length == 4);
    server.respondJson(
      3,
      _unassignedBody(_envelope(child, {'screen': childBytes})),
    );
    await tester.pumpAndSettle();

    expect(requestBodies[0]['assignmentKey'], 'actor-0');
    expect(requestBodies[1], {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
    });
    expect(requestBodies[2]['assignmentKey'], 'actor-1');
    expect(_requestBody(server.requests[3]), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
    });
    expect(find.text('Fresh root'), findsOneWidget);
    expect(find.text('Stale root'), findsNothing);
    expect(server.requests, hasLength(4));
  });

  testWidgets(
      'sustained identity churn before paint is bounded and ends bundled '
      'unassigned', (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final server = _ControlledServer();
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
          _screenDocument(
            screenBytes: bundledBytes,
          ),
          bundledBytes),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));

    for (var attempt = 0; attempt < 3; attempt += 1) {
      await _waitFor(() => server.requests.length == attempt + 1);
      final candidateBytes = screenBlob('Candidate $attempt', 'next');
      server.respondJson(
          attempt,
          _assignedBody(
            _envelope(
              _screenDocument(version: 2, screenBytes: candidateBytes),
              {'welcome': candidateBytes},
            ),
          ));
      // Resolve and install the candidate without drawing the scheduled frame.
      await tester.idle();

      actorGeneration += 1;
      FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
      await tester.idle();
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 10));
    final observed = (
      requests: server.requests.length,
      bundled: find.text('Bundled').evaluate().length,
      candidates: find.textContaining('Candidate').evaluate().length,
      texts: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .toList(),
    );

    server.completeOutstandingWithNotFound();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.requests, 3);
    expect(observed.bundled, 1, reason: '${observed.texts}');
    expect(observed.candidates, 0);
  });
}

Widget _host(
  FlowResolver resolver, {
  void Function(FlowUnavailableError error)? onFlowUnavailable,
}) =>
    MaterialApp(
      home: RestageSurfaceFlow<Map<String, Object?>>(
        flow: _flowRef,
        resolver: resolver,
        onFlowUnavailable: onFlowUnavailable,
        unavailable: FlowUnavailablePolicy.fallback(
          builder: (_, error) => Text('UNAVAILABLE:${error.reason}'),
        ),
      ),
    );

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

FlowDocument _screenDocument({
  required Uint8List screenBytes,
  String flow = 'first_run',
  int version = 1,
  String screenId = 'welcome',
  String artifactPath = 'welcome.rfw',
  Map<String, Object?> terminalResult = const {'completed': true},
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: screenId,
    actions: const {},
    screenArtifacts: {
      screenId: ScreenArtifact(
        path: artifactPath,
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      screenId: ScreenFlowState(
        screen: screenId,
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: terminalResult),
    },
  );
}

FlowDocument _parentDocument({
  required FlowDocument child,
  int version = 1,
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'child',
    actions: const {},
    screenArtifacts: const {},
    states: {
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
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

FlowDocument _screenThenChildDocument({
  required FlowDocument child,
  required Uint8List screenBytes,
  int version = 1,
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'root.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('child')},
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
      'done': const EndFlowState(result: {'completed': true}),
    },
  );
}

Uint8List _envelope(
  FlowDocument document,
  Map<String, Uint8List> screenBlobs, {
  SurfaceType surfaceType = SurfaceType.onboarding,
}) {
  return SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: surfaceType,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: screenBlobs,
    ),
    publishedAt: DateTime.utc(2026),
  ));
}

Map<String, Object?> _assignedBody(Uint8List envelope) => {
      'envelope': base64Encode(envelope),
      'decision': 'assigned',
      'experimentId': 'exp_copy',
      'variantId': 'variant_a',
      'experimentEpoch': 3,
    };

Map<String, Object?> _unassignedBody(Uint8List envelope) => {
      'envelope': base64Encode(envelope),
    };

Map<String, Object?> _requestBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

void _configureAnalytics(List<http.Request> requests) {
  Restage.debugAnalyticsHttpClient = MockClient((request) async {
    requests.add(request);
    return http.Response('', 200);
  });
  Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'http://127.0.0.1:1',
  );
}

Future<List<Map<String, Object?>>> _capturedAnalytics(
  List<http.Request> requests,
) async {
  await Restage.debugFlushAnalytics();
  return <Map<String, Object?>>[
    for (final request in requests)
      for (final event in (jsonDecode(request.body)
          as Map<String, Object?>)['events']! as List)
        (event! as Map).cast<String, Object?>(),
  ];
}

List<Map<String, Object?>> _canonicalEvents(
  List<Map<String, Object?>> events,
) =>
    events.where((event) => event['name'] == 'surface_presented').toList();

AssetBundle _bundleFor(
  FlowDocument document,
  Uint8List screenBytes, {
  SurfaceType surfaceType = SurfaceType.onboarding,
}) {
  return _bundleForClosure(
    surfaceType: surfaceType,
    documents: [document],
    screenAssets: {'welcome.rfw': screenBytes},
  );
}

AssetBundle _bundleForClosure({
  required SurfaceType surfaceType,
  required List<FlowDocument> documents,
  required Map<String, Uint8List> screenAssets,
}) =>
    _TestBundle(_bundleAssets(
      surfaceType: surfaceType,
      documents: documents,
      screenAssets: screenAssets,
    ));

Map<String, Uint8List> _bundleAssets({
  required SurfaceType surfaceType,
  required List<FlowDocument> documents,
  required Map<String, Uint8List> screenAssets,
}) {
  final surface = surfaceType.wireName;
  return {
    for (final document in documents)
      'assets/$surface/flows/${document.flow}.flow.json':
          Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    for (final entry in screenAssets.entries)
      'assets/$surface/screens/${entry.key}': entry.value,
  };
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.value();
  }
  fail('Controlled test boundary did not become ready.');
}

final class _ControlledServer {
  _ControlledServer() {
    client = MockClient((request) {
      requests.add(request);
      final response = Completer<http.Response>();
      responses.add(response);
      return response.future;
    });
  }

  late final MockClient client;
  final List<http.Request> requests = [];
  final List<Completer<http.Response>> responses = [];

  void respondJson(int index, Map<String, Object?> body) {
    responses[index].complete(http.Response(jsonEncode(body), 200));
  }

  void respondNotFound(int index) {
    responses[index].complete(http.Response('', 404));
  }

  void completeOutstandingWithNotFound() {
    for (final response in responses) {
      if (!response.isCompleted) response.complete(http.Response('', 404));
    }
  }
}

final class _TestBundle extends CachingAssetBundle {
  _TestBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
