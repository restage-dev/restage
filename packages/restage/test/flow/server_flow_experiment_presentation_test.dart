import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_experiment_mount.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_test_support.dart';

import '../support/hosted_artifact_delivery.dart';
import '../support/supported_policy_revisions_body.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_abc123';
const _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const _refFloor = _installed + 2;

const _flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _refFloor,
  surface: Surface.onboarding,
  decodeResult: _decodeMapResult,
);

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  setUp(debugResetAppBuildOrdinal);
  tearDown(debugResetAppBuildOrdinal);
  setUp(Restage.debugReset);

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
    server.respondJson(0, _contentBody(candidateEnvelope));
    if (firstKey == 'actor-0') {
      await _waitFor(() => server.requests.length == 2);
      server.respondJson(1, _contentBody(candidateEnvelope));
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
        surfaceType: Surface.onboarding,
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
      _contentBody(
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
      _contentBody(
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
    expect(withoutSupportedPolicyRevisions(childRequest), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
      'assignmentKey': 'actor-a',
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
      surface: Surface.onboarding,
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
        surfaceType: Surface.onboarding,
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
      _contentBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);

    actorGeneration += 1;
    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length >= 2);
    final secondBody = _requestBody(server.requests[1]);
    if (secondBody['surfaceSlug'] == 'child') {
      server.respondJson(
        1,
        _contentBody(_envelope(child, {'screen': childBytes})),
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
      _contentBody(_envelope(child, {'screen': childBytes})),
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
    expect(nextRoot.document.version, baselineRoot.version);
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
      surface: Surface.onboarding,
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
        surfaceType: Surface.onboarding,
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
      _contentBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);

    presentation.disposePresentation();
    meteringReady.complete(preferences);
    await _waitFor(() => resolutionDone || server.requests.length > 1);
    final childPublished = server.requests.length > 1;
    if (childPublished) {
      server.respondJson(
        1,
        _contentBody(_envelope(child, {'screen': childBytes})),
      );
    }
    await resolvedFuture;

    final beforeExactProbe = server.requests.length;
    final exactProbe = resolver.resolve<Object?>(childRef);
    await _waitFor(() => server.requests.length > beforeExactProbe);
    server.respondJson(
      beforeExactProbe,
      _contentBody(_envelope(child, {'screen': childBytes})),
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
      surface: Surface.onboarding,
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
        surfaceType: Surface.onboarding,
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
      _contentBody(_envelope(candidateRoot, {'welcome': rootBytes})),
    );
    await _waitFor(() => meteringLookups == 1);
    expect(server.requests, hasLength(1));

    meteringReady.complete(preferences);
    await _waitFor(() => server.requests.length == 2);
    final childRequest = _requestBody(server.requests[1]);
    server.respondJson(
      1,
      _contentBody(_envelope(child, {'screen': childBytes})),
    );
    final root = await resolvedFuture;
    final pinnedChild = await presentation.resolve<Object?>(childRef);
    presentation.publishHostedLastGood();

    final beforeCacheProbe = server.requests.length;
    final cachedChild = await resolver.resolve<Object?>(childRef);

    expect(withoutSupportedPolicyRevisions(childRequest), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
      'assignmentKey': 'actor-a',
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

  testWidgets('local child-closure parity rejection falls back to baseline',
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
        surfaceType: Surface.onboarding,
        documents: [baselineRoot, baselineChild],
        screenAssets: {'child.rfw': baselineChildBytes},
      ),
      httpClient: server.client,
    );

    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 1);
    server.respondJson(
      0,
      _contentBody(_envelope(candidateRoot, const {})),
    );
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(
      1,
      _contentBody(
        _envelope(candidateChild, {'screen': candidateChildBytes}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bundled child'), findsOneWidget);
    expect(find.text('Rejected child'), findsNothing);
    expect(server.requests, hasLength(2));
  });

  testWidgets(
      'HLG is rejected when the exact assignment key changes without '
      'generation drift', (tester) async {
    final originalFlutterErrorHandler = FlutterError.onError;
    _configureAnalytics();
    try {
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
      final firstRequest = _requestBody(server.requests.first);
      expect(firstRequest['assignmentKey'], 'actor-a');
      expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          firstRequest['sdkBuiltInsCanonicalBase64']! as String,
        )))),
        containsPair('appBuildOrdinal', 42),
      );
      expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          firstRequest['sdkBuiltInsCanonicalBase64']! as String,
        )))),
        containsPair('platform', defaultTargetPlatform.name.toLowerCase()),
      );
      expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(
          firstRequest['sdkBuiltInsCanonicalBase64']! as String,
        )))),
        containsPair('sdkApiLevel', 3),
      );
      server.respondJson(
        0,
        _contentBody(_envelope(
          _screenDocument(version: 2, screenBytes: candidateBytes),
          {'welcome': candidateBytes},
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('Actor A candidate'), findsOneWidget);

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
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      Restage.debugReset();
      FlutterError.onError = originalFlutterErrorHandler;
    }
  });

  testWidgets(
      'HLG is rejected when the exact contract hash changes without seed '
      'drift', (tester) async {
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';
    final bundledABytes = screenBlob('Bundled A', 'next');
    final bundledBBytes = screenBlob('Bundled B', 'next');
    final candidateBytes = screenBlob('Contract A candidate', 'next');
    final bundleAssets = _bundleAssets(
      surfaceType: Surface.onboarding,
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
    server.respondJson(
      0,
      _contentBody(_envelope(
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
        surfaceType: Surface.onboarding,
        documents: [_screenDocument(screenBytes: bundledBBytes)],
        screenAssets: {'welcome.rfw': bundledBBytes},
      ));
    await tester.pumpWidget(_host(resolver));
    await _waitFor(() => server.requests.length == 2);
    server.respondNotFound(1);
    await tester.pumpAndSettle();

    final observed = (
      bundled: find.text('Bundled B').evaluate().length,
      stale: find.text('Contract A candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

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
      surface: Surface.onboarding,
      decodeResult: _decodeMapResult,
    );
    const childRef = OnboardingFlowRef<Object?>(
      id: 'child',
      version: 1,
      minClient: _refFloor,
      surface: Surface.onboarding,
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
        surfaceType: Surface.onboarding,
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
      _contentBody(
        _envelope(candidateRoot, {'welcome': candidateRootBytes}),
      ),
    );
    await _waitFor(() => server.requests.length == 2);
    server.respondJson(
      1,
      _contentBody(_envelope(child, {'screen': childBytes})),
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
    expect(server.requests, hasLength(3));
  });

  testWidgets('active content renders without an identity key', (tester) async {
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
      _contentBody(_envelope(
        _screenDocument(version: 2, screenBytes: candidateBytes),
        {'welcome': candidateBytes},
      )),
    );
    await tester.pumpAndSettle();

    final observed = (
      bundled: find.text('Bundled').evaluate().length,
      candidate: find.text('Unauthorized candidate').evaluate().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(request.containsKey('assignmentKey'), isFalse);
    expect(observed.bundled, 0);
    expect(observed.candidate, 1);
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

  testWidgets('an identity retry keeps the presentation device reading',
      (tester) async {
    var actorGeneration = 0;
    var ambientReads = 0;
    final cells = <SurfaceDeliveryObservationCell?>[];
    SurfaceCanonicalCarrierProvider.installBuiltIns(() async {
      ambientReads += 1;
      return null;
    });
    addTearDown(SurfaceCanonicalCarrierProvider.clear);
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final bundledBytes = screenBlob('Bundled', 'next');
    final requests = <http.Request>[];
    final resolver = ServerFlowResolver(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      active: true,
      bundle: _bundleFor(
        _screenDocument(screenBytes: bundledBytes),
        bundledBytes,
      ),
      httpClient: _delivery.client((request) async {
        requests.add(request);
        cells.add(currentSurfaceDeliveryObservationCell());
        // Drift the identity only after the request has read the device.
        actorGeneration += 1;
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(_host(resolver));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(requests.length, greaterThan(1));
    expect(cells.first, isNotNull);
    expect(cells, everyElement(same(cells.first)));
    expect(ambientReads, 0);
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
      _contentBody(_envelope(
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
      _contentBody(_envelope(
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
      surface: Surface.message,
      decodeResult: _decodeMapResult,
    );
    const surveyRef = OnboardingFlowRef<Map<String, Object?>>(
      id: 'first_run',
      version: 1,
      minClient: _refFloor,
      surface: Surface.survey,
      decodeResult: _decodeMapResult,
    );
    final messageBundled = screenBlob('Message bundled', 'next');
    final surveyBundled = screenBlob('Survey bundled', 'next');
    final messageCandidate = screenBlob('Message candidate', 'next');
    final surveyCandidate = screenBlob('Survey candidate', 'next');
    final bundle = _TestBundle({
      ..._bundleAssets(
        surfaceType: Surface.message,
        documents: [_screenDocument(screenBytes: messageBundled)],
        screenAssets: {'welcome.rfw': messageBundled},
      ),
      ..._bundleAssets(
        surfaceType: Surface.survey,
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
            child: RestageFlowGraph<Map<String, Object?>>(
              flow: messageRef,
              resolver: resolver,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
          ),
          Expanded(
            child: RestageFlowGraph<Map<String, Object?>>(
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
    server.respondJson(
      surveyIndex,
      _contentBody(_envelope(
        _screenDocument(version: 2, screenBytes: surveyCandidate),
        {'welcome': surveyCandidate},
        surfaceType: Surface.survey,
      )),
    );
    await tester.pumpAndSettle();
    final afterSurvey = (
      survey: find.text('Survey candidate').evaluate().length,
      message: find.text('Message candidate').evaluate().length,
    );

    server.respondJson(
      messageIndex,
      _contentBody(_envelope(
        _screenDocument(version: 2, screenBytes: messageCandidate),
        {'welcome': messageCandidate},
        surfaceType: Surface.message,
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
      _contentBody(_envelope(
        _screenDocument(version: 2, screenBytes: staleBytes),
        {'welcome': staleBytes},
      )),
    );
    await _waitFor(() => server.requests.length == 2);
    final staleKey = _requestBody(server.requests[0])['assignmentKey'];
    final freshKey = _requestBody(server.requests[1])['assignmentKey'];

    server.respondJson(
      1,
      _contentBody(_envelope(
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
        surfaceType: Surface.onboarding,
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
      _contentBody(_envelope(staleRoot, {'welcome': staleRootBytes})),
    );
    await _waitFor(() => server.requests.length == 2);

    actorGeneration += 1;
    server.respondJson(
      1,
      _contentBody(_envelope(child, {'screen': childBytes})),
    );
    await _waitFor(() => server.requests.length == 3);
    final requestBodies = server.requests.map(_requestBody).toList();

    server.respondJson(
      2,
      _contentBody(_envelope(freshRoot, {'welcome': freshRootBytes})),
    );
    await _waitFor(() => server.requests.length == 4);
    server.respondJson(
      3,
      _contentBody(_envelope(child, {'screen': childBytes})),
    );
    await tester.pumpAndSettle();

    expect(requestBodies[0]['assignmentKey'], 'actor-0');
    expect(withoutSupportedPolicyRevisions(requestBodies[1]), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
      'assignmentKey': 'actor-0',
    });
    expect(requestBodies[2]['assignmentKey'], 'actor-1');
    expect(withoutSupportedPolicyRevisions(_requestBody(server.requests[3])), {
      'surfaceType': 'onboarding',
      'surfaceSlug': 'child',
      'version': 1,
      'assignmentKey': 'actor-1',
    });
    expect(find.text('Fresh root'), findsOneWidget);
    expect(find.text('Stale root'), findsNothing);
    expect(server.requests, hasLength(4));
  });

  testWidgets(
      'sustained identity churn before paint is bounded and ends bundled '
      'baseline', (tester) async {
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
          _contentBody(
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
      home: RestageFlowGraph<Map<String, Object?>>(
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
  Surface surfaceType = Surface.onboarding,
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

Map<String, Object?> _contentBody(Uint8List envelope) => {
      ..._delivery.describeEnvelope(envelope),
    };

Map<String, Object?> _requestBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

void _configureAnalytics() {
  PackageInfo.setMockInitialValues(
    appName: 'Flow assignment',
    packageName: 'com.example.flow_assignment',
    version: '1.0.0',
    buildNumber: '42',
    buildSignature: '',
  );
  Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'http://127.0.0.1:1',
  );
}

AssetBundle _bundleFor(
  FlowDocument document,
  Uint8List screenBytes, {
  Surface surfaceType = Surface.onboarding,
}) {
  return _bundleForClosure(
    surfaceType: surfaceType,
    documents: [document],
    screenAssets: {'welcome.rfw': screenBytes},
  );
}

AssetBundle _bundleForClosure({
  required Surface surfaceType,
  required List<FlowDocument> documents,
  required Map<String, Uint8List> screenAssets,
}) =>
    _TestBundle(_bundleAssets(
      surfaceType: surfaceType,
      documents: documents,
      screenAssets: screenAssets,
    ));

Map<String, Uint8List> _bundleAssets({
  required Surface surfaceType,
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
    client = _delivery.client((request) {
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
