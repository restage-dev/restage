import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_experiment_mount.dart'
    show FlowMountRevalidationBoundary;
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart'
    show registerThrowingWidget, resolvedFlow, screenBlob;
import '../support/hosted_artifact_delivery.dart';

/// The stub delivery for this file: it describes surfaces AND answers for
/// their content, so no test here can stub half a wire.
final HostedArtifactFixture _delivery = HostedArtifactFixture();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    _ResetPaintProbe.reset();
  });
  tearDown(Restage.debugReset);

  test(
      'an identity change after lease capture sends no request with the old '
      'assignment key and retries the new actor exactly once', () async {
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: const _AlwaysFailingFallback(),
    );
    final oldKey = Completer<String?>();
    final captureStarted = Completer<void>();
    SurfaceAssignmentKeyProvider.current = () {
      if (!captureStarted.isCompleted) captureStarted.complete();
      return oldKey.future;
    };

    final resolved = resolver.resolve('pro_upgrade');
    await captureStarted.future;
    SurfaceAssignmentKeyProvider.current = () => 'actor-b';
    oldKey.complete('actor-a');
    await _waitUntil(() => server.requests.length == 1);
    final firstKey = _assignmentKey(server.requests.single.request);
    if (firstKey == 'actor-a') {
      server.requests.single.complete(
        _hostedResponse(_blobEnvelope('Stale actor A', version: 1)),
      );
      await _waitUntil(() => server.requests.length == 2);
    }
    server.requests.last.complete(
      _hostedResponse(_blobEnvelope('Actor B only', version: 2)),
    );

    final variant = await resolved;
    final requestKeys = server.requests
        .map((request) => _assignmentKey(request.request))
        .toList();

    expect(variant.paywallPublishedVersion, 2);
    expect(requestKeys, orderedEquals(<String?>['actor-b']));
  });

  testWidgets(
      'a reset after blob lease validation but before host apply discards the '
      'stale payload and re-resolves', (tester) async {
    final resolver = _ControlledPayloadResolver();
    final lease = await _leaseThatResetsAfterNextValidation();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await tester.pump();
    resolver.responses.single.complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _blob('Actor A after validation'),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 1,
      ),
      assignmentLease: lease,
    ));
    await _pumpUntil(
      tester,
      () =>
          resolver.responses.length == 2 ||
          find.text('Actor A after validation').evaluate().isNotEmpty,
    );
    if (resolver.responses.length == 2) {
      resolver.responses[1].complete(BlobPaywallPayload(
        ResolvedVariant(
          bytes: _blob('Actor B after validation'),
          paywallId: 'pro_upgrade',
          paywallPublishedVersion: 2,
        ),
      ));
    }
    await tester.pumpAndSettle();

    final observed = (
      actorA: find.text('Actor A after validation').evaluate().length,
      actorB: find.text('Actor B after validation').evaluate().length,
      resolverCalls: resolver.responses.length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(observed, (actorA: 0, actorB: 1, resolverCalls: 2));
  });

  testWidgets(
      'a reset during an uncommitted blob descendant build prevents stale '
      'first paint and re-resolves', (tester) async {
    _registerResetPaintProbe(_ResetTiming.duringBuild);
    final resolver = _ControlledPayloadResolver();
    final lease = await _configuredLease();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await tester.pump();
    resolver.responses.single.complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _resettingBlob(),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 1,
      ),
      assignmentLease: lease,
    ));
    await _pumpUntil(tester, () => _ResetPaintProbe.resetTriggered);
    await tester.pump(const Duration(milliseconds: 16));
    await _pumpUntil(tester, () => resolver.responses.length == 2);
    if (resolver.responses.length == 2) {
      resolver.responses[1].complete(BlobPaywallPayload(
        ResolvedVariant(
          bytes: _blob('Actor B blob'),
          paywallId: 'pro_upgrade',
          paywallPublishedVersion: 2,
        ),
      ));
    }
    await tester.pumpAndSettle();

    final observed = (
      stalePainted: _ResetPaintProbe.paintCount > 0,
      actorB: find.text('Actor B blob').evaluate().length,
      resolverCalls: resolver.responses.length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(observed, (stalePainted: false, actorB: 1, resolverCalls: 2));
  });

  testWidgets(
      'a reset during an uncommitted flow descendant build prevents stale '
      'first paint and re-resolves', (tester) async {
    _registerResetPaintProbe(_ResetTiming.duringBuild);
    final resolver = _ControlledPayloadResolver();
    final lease = await _configuredLease();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _resettingFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
      assignmentLease: lease,
    ));
    await _pumpUntil(tester, () => _ResetPaintProbe.resetTriggered);
    await tester.pumpAndSettle();
    expect(_ResetPaintProbe.resetTriggered, isTrue);
    await tester.idle();
    expect(resolver.responses, hasLength(2));
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: resolvedFlow(welcomeText: 'Actor B flow'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await _pumpUntil(
      tester,
      () => find.text('Actor B flow').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    final observed = (
      stalePainted: _ResetPaintProbe.paintCount > 0,
      actorB: find.text('Actor B flow').evaluate().length,
      resolverCalls: resolver.responses.length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(observed, (stalePainted: false, actorB: 1, resolverCalls: 2));
  });

  testWidgets(
      'strict flow reset before first paint discards the assigned candidate, '
      'publishes only the retried actor, and reuses only that HLG',
      (tester) async {
    _registerResetPaintProbe(_ResetTiming.duringBuild);
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://surfaces.example.com',
    );
    final baselineScreen = screenBlob('Frozen bundled baseline', 'finish');
    final bundle = _StrictPaywallAssetBundle(
      document: _strictFlowDocument(screen: baselineScreen),
      screens: <String, Uint8List>{'paywall_pro_upgrade.rfw': baselineScreen},
    );
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await _pumpUntil(tester, () => server.requests.length == 1);
    expect(
        _requestJson(server.requests[0].request), contains('flowContractHash'));
    server.requests[0].complete(_hostedResponse(
      _strictFlowEnvelope(
        screen: _resettingFlowScreenBlob(),
        version: 9,
        requiredLibraries: const <LibraryRequirement>[
          LibraryRequirement(
            namespace: 'acme.identity_reset',
            minVersion: 1,
          ),
        ],
      ),
      decision: 'assigned',
      experimentId: 'experiment-a',
      variantId: 'variant-a',
      experimentEpoch: 1,
    ));

    await _pumpUntil(tester, () => _ResetPaintProbe.resetTriggered);
    await _pumpUntil(tester, () => server.requests.length == 2);
    final actorBScreen = screenBlob('Strict actor B', 'finish');
    server.requests[1].complete(_hostedResponse(
      _strictFlowEnvelope(screen: actorBScreen, version: 10),
      decision: 'assigned',
      experimentId: 'experiment-b',
      variantId: 'variant-b',
      experimentEpoch: 2,
    ));
    await tester.pumpAndSettle();

    expect(_ResetPaintProbe.paintCount, 0);
    expect(find.text('Strict actor B'), findsOneWidget);
    expect(
      events.whereType<PaywallViewed>().map((event) => (
            experimentId: event.experimentId,
            variantId: event.variantId,
            experimentEpoch: event.experimentEpoch,
          )),
      orderedEquals(<Object>[
        (
          experimentId: 'experiment-b',
          variantId: 'variant-b',
          experimentEpoch: 2,
        ),
      ]),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    events.clear();
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await _pumpUntil(tester, () => server.requests.length == 3);
    server.requests[2].complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();

    final observed = (
      actorB: find.text('Strict actor B').evaluate().length,
      requests: server.requests.length,
      cacheHits: events
          .whereType<PaywallLoadCompleted>()
          .map((event) => event.cacheHit)
          .toList(),
    );
    Restage.reset();
    await tester.pumpAndSettle();
    expect(find.text('Strict actor B'), findsOneWidget);
    await Restage.reloadSurfaces();
    expect(server.requests, hasLength(3));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await _pumpUntil(tester, () => server.requests.length == 4);
    server.requests[3].complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();
    expect(find.text('Frozen bundled baseline'), findsOneWidget);
    expect(find.text('Strict actor B'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect((actorB: observed.actorB, requests: observed.requests),
        (actorB: 1, requests: 3));
    expect(observed.cacheHits, orderedEquals(<bool>[true]));
  });

  testWidgets(
      'strict flow first-paint churn shares one frozen preflight and falls '
      'back unassigned after three total hosted attempts', (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final originalBaseline = screenBlob('Original frozen baseline', 'finish');
    final bundle = _StrictPaywallAssetBundle(
      document: _strictFlowDocument(screen: originalBaseline),
      screens: <String, Uint8List>{
        'paywall_pro_upgrade.rfw': originalBaseline,
      },
    );
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await _waitUntil(() => server.requests.length == 1);

    final mutatedBaseline = screenBlob('Mutated bundled baseline', 'finish');
    bundle.replace(
      document: _strictFlowDocument(screen: mutatedBaseline),
      screens: <String, Uint8List>{
        'paywall_pro_upgrade.rfw': mutatedBaseline,
      },
    );

    for (var attempt = 0; attempt < 3; attempt += 1) {
      await _waitUntil(() => server.requests.length == attempt + 1);
      final candidate = screenBlob('Rejected candidate $attempt', 'finish');
      server.requests[attempt].complete(_hostedResponse(
        _strictFlowEnvelope(screen: candidate, version: 10 + attempt),
        decision: 'assigned',
        experimentId: 'experiment-$attempt',
        variantId: 'variant-$attempt',
        experimentEpoch: attempt + 1,
      ));
      // Resolve and stage the candidate while its HTTP response Completer is
      // controlled, but do not draw the scheduled first-paint frame.
      await tester.idle();
      actorGeneration += 1;
      FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
      await tester.idle();
    }

    await _pumpUntil(
      tester,
      () =>
          find.text('Original frozen baseline').evaluate().isNotEmpty ||
          server.requests.length > 3,
    );
    if (server.requests.length > 3) {
      server.requests[3].complete(http.Response('unavailable', 503));
    }
    await tester.pumpAndSettle();

    final viewed = events.whereType<PaywallViewed>().toList();
    final observed = (
      requests: server.requests.length,
      loadedKeys: List<String>.of(bundle.loadedKeys),
      original: find.text('Original frozen baseline').evaluate().length,
      mutated: find.text('Mutated bundled baseline').evaluate().length,
      candidates: find.textContaining('Rejected candidate').evaluate().length,
      unavailable: events.whereType<FlowUnavailable>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      assignment: viewed.length != 1
          ? null
          : (
              viewed.single.experimentId,
              viewed.single.variantId,
              viewed.single.experimentEpoch,
            ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(observed.requests, 3);
    expect(
      observed.loadedKeys,
      orderedEquals(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]),
    );
    expect(observed.original, 1);
    expect(observed.mutated, 0);
    expect(observed.candidates, 0);
    expect(observed.unavailable, 0);
    expect(observed.failed, 0);
    expect(observed.assignment, (null, null, null));
  });

  testWidgets(
      'strict flow post-resolver identity churn retains one frozen preflight '
      'and three-attempt budget', (tester) async {
    final identity = _PostResolverIdentityDrift();
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-${identity.generation}',
      identityGeneration: identity.read,
    );
    final originalBaseline =
        screenBlob('Original resolver-gap baseline', 'finish');
    final bundle = _StrictPaywallAssetBundle(
      document: _strictFlowDocument(screen: originalBaseline),
      screens: <String, Uint8List>{
        'paywall_pro_upgrade.rfw': originalBaseline,
      },
    );
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );
    final events = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await _waitUntil(() => server.requests.length == 1);

    final mutatedBaseline =
        screenBlob('Mutated resolver-gap baseline', 'finish');
    bundle.replace(
      document: _strictFlowDocument(screen: mutatedBaseline),
      screens: <String, Uint8List>{
        'paywall_pro_upgrade.rfw': mutatedBaseline,
      },
    );

    for (var attempt = 0; attempt < 3; attempt += 1) {
      await _waitUntil(() => server.requests.length == attempt + 1);
      identity.driftAfterPresentationFinalRecapture();
      server.requests[attempt].complete(_hostedResponse(
        _strictFlowEnvelope(
          screen: screenBlob('Resolver-gap candidate $attempt', 'finish'),
          version: 20 + attempt,
        ),
        decision: 'assigned',
        experimentId: 'resolver-gap-experiment-$attempt',
        variantId: 'resolver-gap-variant-$attempt',
        experimentEpoch: attempt + 1,
      ));
      await tester.idle();
      await _waitUntil(() => identity.completedDrifts == attempt + 1);
    }

    await _pumpUntil(
      tester,
      () =>
          find.text('Original resolver-gap baseline').evaluate().isNotEmpty ||
          server.requests.length > 3,
      maxPumps: 100,
      step: const Duration(milliseconds: 1),
    );
    if (server.requests.length > 3) {
      server.requests[3].complete(http.Response('unavailable', 503));
      await _pumpUntil(
        tester,
        () =>
            find.text('Original resolver-gap baseline').evaluate().isNotEmpty ||
            find.text('Mutated resolver-gap baseline').evaluate().isNotEmpty,
        maxPumps: 100,
        step: const Duration(milliseconds: 1),
      );
    }
    await tester.pumpAndSettle();

    final viewed = events.whereType<PaywallViewed>().toList();
    final observed = (
      requests: server.requests.length,
      loadedKeys: List<String>.of(bundle.loadedKeys),
      original: find.text('Original resolver-gap baseline').evaluate().length,
      mutated: find.text('Mutated resolver-gap baseline').evaluate().length,
      candidates:
          find.textContaining('Resolver-gap candidate').evaluate().length,
      unavailable: events.whereType<FlowUnavailable>().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      assignment: viewed.length != 1
          ? null
          : (
              viewed.single.experimentId,
              viewed.single.variantId,
              viewed.single.experimentEpoch,
            ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(observed.requests, 3);
    expect(
      observed.loadedKeys,
      orderedEquals(<String>[
        'assets/paywalls/pro_upgrade.flow.json',
        'assets/paywalls/screens/paywall_pro_upgrade.rfw',
      ]),
    );
    expect(observed.original, 1);
    expect(observed.mutated, 0);
    expect(observed.candidates, 0);
    expect(observed.unavailable, 0);
    expect(observed.failed, 0);
    expect(observed.assignment, (null, null, null));
  });

  testWidgets(
      'unexpected current-epoch retained flow retry failure reaches the normal '
      'failure path', (tester) async {
    final flow = resolvedFlow(welcomeText: 'Rejected retained flow');
    final authority = _ThrowingRetryAuthority(flow);
    final resolver = _ControlledPayloadResolver();
    final events = <RestageEvent>[];
    final reportedErrors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
        loadingBuilder: (_) => const Text('Retry still loading'),
        errorBuilder: (_, __) => const Text('Retained retry failed'),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload.experimentBaseline(
      flow: flow,
      pinnedFlowResolver: authority,
      paywallId: 'pro_upgrade',
      experimentAuthority: authority,
    ));

    await _pumpUntil(tester, () => authority.retryCalls == 1);
    await tester.pumpAndSettle();
    FlutterError.onError = previousErrorHandler;

    final observed = (
      resolverCalls: resolver.responses.length,
      loading: find.text('Retry still loading').evaluate().length,
      error: find.text('Retained retry failed').evaluate().length,
      failed: events.whereType<PaywallLoadFailed>().length,
      viewed: events.whereType<PaywallViewed>().length,
      reported: reportedErrors.length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      observed,
      (
        resolverCalls: 1,
        loading: 0,
        error: 1,
        failed: 1,
        viewed: 0,
        reported: 1,
      ),
    );
  });

  testWidgets(
      'unmount while a strict first-paint retry request is pending cannot '
      'stage or request later work', (tester) async {
    var actorGeneration = 0;
    SurfaceAssignmentKeyProvider.install(
      key: () => 'actor-$actorGeneration',
      identityGeneration: () => actorGeneration,
    );
    final baseline = screenBlob('Disposal baseline', 'finish');
    final bundle = _StrictPaywallAssetBundle(
      document: _strictFlowDocument(screen: baseline),
      screens: <String, Uint8List>{'paywall_pro_upgrade.rfw': baseline},
    );
    final server = _ControlledHostedServer();
    final events = <RestageEvent>[];
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await _waitUntil(() => server.requests.length == 1);
    server.requests[0].complete(_hostedResponse(
      _strictFlowEnvelope(
        screen: screenBlob('Disposed candidate A', 'finish'),
        version: 9,
      ),
      decision: 'assigned',
      experimentId: 'experiment-a',
      variantId: 'variant-a',
      experimentEpoch: 1,
    ));
    await tester.idle();
    actorGeneration += 1;
    FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
    await tester.idle();
    await _waitUntil(() => server.requests.length == 2);

    await tester.pumpWidget(const SizedBox.shrink());
    server.requests[1].complete(_hostedResponse(
      _strictFlowEnvelope(
        screen: screenBlob('Disposed candidate B', 'finish'),
        version: 10,
      ),
      decision: 'assigned',
      experimentId: 'experiment-b',
      variantId: 'variant-b',
      experimentEpoch: 2,
    ));
    await tester.idle();
    await tester.pump();

    expect(server.requests, hasLength(2));
    expect(bundle.loadedKeys, hasLength(2));
    expect(events.whereType<PaywallLoadCompleted>(), isEmpty);
    expect(events.whereType<PaywallViewed>(), isEmpty);
    expect(events.whereType<PaywallLoadFailed>(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'strict unassigned refresh promotes while a newly assigned refresh is '
      'discarded and cannot replace HLG', (tester) async {
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://surfaces.example.com',
    );
    final baselineScreen = screenBlob('Frozen bundled baseline', 'finish');
    final bundle = _StrictPaywallAssetBundle(
      document: _strictFlowDocument(screen: baselineScreen),
      screens: <String, Uint8List>{'paywall_pro_upgrade.rfw': baselineScreen},
    );
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: AssetVariantResolver(bundle: bundle),
    );

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await _pumpUntil(tester, () => server.requests.length == 1);
    final screenA = screenBlob('Strict current A', 'finish');
    server.requests[0].complete(_hostedResponse(
      _strictFlowEnvelope(screen: screenA, version: 9),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Strict current A'), findsOneWidget);

    final promote = Restage.reloadSurfaces();
    await _pumpUntil(tester, () => server.requests.length == 2);
    final screenB = screenBlob('Strict refreshed B', 'finish');
    server.requests[1].complete(_hostedResponse(
      _strictFlowEnvelope(screen: screenB, version: 10),
    ));
    await promote;
    await tester.pumpAndSettle();
    expect(find.text('Strict refreshed B'), findsOneWidget);
    expect(find.text('Strict current A'), findsNothing);

    final rejectAssigned = Restage.reloadSurfaces();
    await _pumpUntil(tester, () => server.requests.length == 3);
    final screenC = screenBlob('Incorrect assigned refresh C', 'finish');
    server.requests[2].complete(_hostedResponse(
      _strictFlowEnvelope(screen: screenC, version: 11),
      decision: 'assigned',
      experimentId: 'experiment-c',
      variantId: 'variant-c',
      experimentEpoch: 3,
    ));
    await rejectAssigned;
    await tester.pumpAndSettle();
    expect(find.text('Strict refreshed B'), findsOneWidget);
    expect(find.text('Incorrect assigned refresh C'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
    ));
    await _pumpUntil(tester, () => server.requests.length == 4);
    server.requests[3].complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();

    expect(find.text('Strict refreshed B'), findsOneWidget);
    expect(server.requests, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a reset and blob build failure in the same build discards A, retries '
      'through the guarded path, and renders B without a terminal gap',
      (tester) async {
    _registerResetThenThrowProbe();
    final resolver = _ControlledPayloadResolver();
    final events = <RestageEvent>[];
    final lease = await _configuredLease();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        cacheLastRender: true,
        onEvent: events.add,
        loadingBuilder: (_) => const Text('Still loading'),
        errorBuilder: (_, __) => const Text('Terminal error'),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _resetThenThrowBlob(),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 1,
      ),
      assignmentLease: lease,
    ));

    await _pumpUntil(tester, () => resolver.responses.length == 2);
    if (resolver.responses.length == 2) {
      resolver.responses[1].complete(BlobPaywallPayload(
        ResolvedVariant(
          bytes: _blob('Actor B after blob failure'),
          paywallId: 'pro_upgrade',
          paywallPublishedVersion: 2,
        ),
      ));
    }
    await tester.pumpAndSettle();

    final observed = (
      actorB: find.text('Actor B after blob failure').evaluate().length,
      loading: find.text('Still loading').evaluate().length,
      error: find.text('Terminal error').evaluate().length,
      resolverCalls: resolver.responses.length,
      failed: events.whereType<PaywallLoadFailed>().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewedVersions: events
          .whereType<PaywallViewed>()
          .map((event) => event.publishedVersion)
          .toList(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (
        actorB: observed.actorB,
        loading: observed.loading,
        error: observed.error,
        resolverCalls: observed.resolverCalls,
        failed: observed.failed,
        completed: observed.completed,
      ),
      (
        actorB: 1,
        loading: 0,
        error: 0,
        resolverCalls: 2,
        failed: 0,
        completed: 1,
      ),
    );
    expect(observed.viewedVersions, orderedEquals(<int?>[2]));
  });

  testWidgets(
      'a reset and initial flow build failure in the same build discards A, '
      'retries through the guarded path, and renders B without a terminal gap',
      (tester) async {
    _registerResetThenThrowProbe();
    final resolver = _ControlledPayloadResolver();
    final events = <RestageEvent>[];
    final lease = await _configuredLease();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        cacheLastRender: true,
        onEvent: events.add,
        loadingBuilder: (_) => const Text('Still loading'),
        errorBuilder: (_, __) => const Text('Terminal error'),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _resetThenThrowFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
      assignmentLease: lease,
    ));

    await _pumpUntil(
      tester,
      () => resolver.responses.length == 2,
      maxPumps: 100,
      step: const Duration(milliseconds: 1),
    );
    expect(resolver.responses, hasLength(2));
    resolver.responses[1].complete(FlowPaywallPayload(
      flow: resolvedFlow(welcomeText: 'Actor B after flow failure'),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 2,
    ));
    await tester.idle();
    await _pumpUntil(
      tester,
      () => find.text('Actor B after flow failure').evaluate().isNotEmpty,
      maxPumps: 100,
      step: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();

    final flowViews = tester
        .widgetList<RestageFlowView<void>>(find.byType(RestageFlowView<void>))
        .toList();
    final observed = (
      actorB: find.text('Actor B after flow failure').evaluate().length,
      loading: find.text('Still loading').evaluate().length,
      error: find.text('Terminal error').evaluate().length,
      resolverCalls: resolver.responses.length,
      failed: events.whereType<PaywallLoadFailed>().length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewedVersions: events
          .whereType<PaywallViewed>()
          .map((event) => event.publishedVersion)
          .toList(),
      flowViews: flowViews.length,
      currentEntry: flowViews.isEmpty
          ? null
          : flowViews.single.controller.currentScreenEntryId,
      unavailable:
          flowViews.isEmpty ? null : flowViews.single.controller.isUnavailable,
      rendered: flowViews.isEmpty
          ? null
          : flowViews.single.controller.hasRenderedContent,
      escaped: tester.takeException(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (
        actorB: observed.actorB,
        loading: observed.loading,
        error: observed.error,
        resolverCalls: observed.resolverCalls,
        failed: observed.failed,
        completed: observed.completed,
        flowViews: observed.flowViews,
        unavailable: observed.unavailable,
        rendered: observed.rendered,
        escaped: observed.escaped,
      ),
      (
        actorB: 1,
        loading: 0,
        error: 0,
        resolverCalls: 2,
        failed: 0,
        completed: 1,
        flowViews: 1,
        unavailable: false,
        rendered: true,
        escaped: null,
      ),
    );
    expect(observed.currentEntry, isNotNull);
    expect(observed.viewedVersions, orderedEquals(<int?>[2]));
  });

  testWidgets(
      'a reset after accepted first paint but before deferred flow host commit '
      'pins the rendered presentation', (tester) async {
    _registerResetPaintProbe(_ResetTiming.afterFirstPaintAcceptance);
    final resolver = _ControlledPayloadResolver();
    final events = <RestageEvent>[];
    final lease = await _configuredLease();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(FlowPaywallPayload(
      flow: _resettingFlow(),
      paywallId: 'pro_upgrade',
      paywallPublishedVersion: 1,
      assignmentLease: lease,
    ));
    await _pumpUntil(tester, () => _ResetPaintProbe.resetTriggered);
    await _pumpUntil(tester, () => resolver.responses.length == 2);
    if (resolver.responses.length == 2) {
      resolver.responses[1].complete(FlowPaywallPayload(
        flow: resolvedFlow(welcomeText: 'Incorrect retry'),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 2,
      ));
    }
    await tester.pumpAndSettle();

    final observed = (
      stalePainted: _ResetPaintProbe.paintCount > 0,
      retry: find.text('Incorrect retry').evaluate().length,
      resolverCalls: resolver.responses.length,
      completed: events.whereType<PaywallLoadCompleted>().length,
      viewed: events.whereType<PaywallViewed>().length,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      observed,
      (
        stalePainted: true,
        retry: 0,
        resolverCalls: 1,
        completed: 1,
        viewed: 1,
      ),
    );
  });

  testWidgets(
      'an unrendered stale actor response re-enters hosted resolution and '
      'falls through stale HLG to bundled content', (tester) async {
    final server = _ControlledHostedServer();
    final fallback = _ControlledFallback();
    final hosted = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: fallback,
    );
    final resolver = _HeldFirstPayloadResolver(hosted);
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          loadingBuilder: (_) => const Text('Loading'),
          errorBuilder: (_, __) => const Text('Error'),
        ),
      ),
    );
    await _pumpUntil(tester, () => server.requests.length == 1);
    if (server.requests.isNotEmpty) {
      server.requests[0].complete(
        _hostedResponse(
          _blobEnvelope('Actor A', version: 1),
          experimentId: 'experiment-a',
          variantId: 'variant-a',
          experimentEpoch: 1,
        ),
      );
    }
    await _pumpUntil(tester, () => resolver.firstPayloadReady.isCompleted);

    // The hosted response and its HLG entry now belong to actor A, but the
    // widget has not received or rendered the payload yet.
    SurfaceAssignmentKeyProvider.current = () => 'actor-b';
    resolver.releaseFirstPayload.complete();
    await _pumpUntil(
      tester,
      () => resolver.calls == 2 || find.text('Actor A').evaluate().isNotEmpty,
    );
    if (resolver.calls >= 2) {
      await _pumpUntil(tester, () => server.requests.length >= 2);
    }

    // B's fresh tier fails. The A-generation HLG must not reappear or loop;
    // resolution continues through the existing ladder to the bundled tier.
    if (server.requests.length >= 2) {
      server.requests[1].complete(http.Response('unavailable', 503));
      await _pumpUntil(tester, () => fallback.calls == 1);
    }
    if (fallback.hasPending) {
      fallback.complete(
        ResolvedVariant(
          bytes: _blob('Bundled'),
          paywallId: 'pro_upgrade',
        ),
      );
    }
    await tester.pumpAndSettle();

    final observed = (
      actorA: find.text('Actor A').evaluate().length,
      bundled: find.text('Bundled').evaluate().length,
      loading: find.text('Loading').evaluate().length,
      error: find.text('Error').evaluate().length,
      resolverCalls: resolver.calls,
      requestKeys: server.requests
          .map((entry) => _assignmentKey(entry.request))
          .toList(),
      fallbackCalls: fallback.calls,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (
        actorA: observed.actorA,
        bundled: observed.bundled,
        loading: observed.loading,
        error: observed.error,
        resolverCalls: observed.resolverCalls,
        fallbackCalls: observed.fallbackCalls,
      ),
      (
        actorA: 0,
        bundled: 1,
        loading: 0,
        error: 0,
        resolverCalls: 2,
        fallbackCalls: 1,
      ),
    );
    expect(
        observed.requestKeys, orderedEquals(<String?>['actor-a', 'actor-b']));
  });

  testWidgets(
      'an already-rendered presentation stays pinned when refresh crosses '
      'an actor generation change', (tester) async {
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: _ControlledFallback(),
    );
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
      ),
    );
    await _pumpUntil(tester, () => server.requests.length == 1);
    if (server.requests.isNotEmpty) {
      server.requests[0].complete(
        _hostedResponse(_blobEnvelope('Current', version: 1)),
      );
    }
    await tester.pumpAndSettle();

    final refresh = Restage.reloadSurfaces();
    await _pumpUntil(tester, () => server.requests.length == 2);

    SurfaceAssignmentKeyProvider.current = () => 'actor-b';
    if (server.requests.length >= 2) {
      server.requests[1].complete(
        _hostedResponse(_blobEnvelope('Stale refresh', version: 2)),
      );
    }
    await _pumpUntil(
      tester,
      () =>
          server.requests.length == 3 ||
          find.text('Stale refresh').evaluate().isNotEmpty,
    );

    // Even a valid B response cannot replace the already-rendered A
    // presentation. The new identity takes effect on a later remount.
    if (server.requests.length >= 3) {
      server.requests[2].complete(
        _hostedResponse(_blobEnvelope('Actor B', version: 3)),
      );
    }
    await refresh;
    await tester.pumpAndSettle();

    final observed = (
      current: find.text('Current').evaluate().length,
      stale: find.text('Stale refresh').evaluate().length,
      actorB: find.text('Actor B').evaluate().length,
      requestKeys: server.requests
          .map((entry) => _assignmentKey(entry.request))
          .toList(),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (
        current: observed.current,
        stale: observed.stale,
        actorB: observed.actorB
      ),
      (current: 1, stale: 0, actorB: 0),
    );
    expect(
      observed.requestKeys,
      orderedEquals(<String?>['actor-a', 'actor-a', 'actor-b']),
    );
  });

  testWidgets('a stale actor entry in the widget render cache is not re-hosted',
      (tester) async {
    final server = _ControlledHostedServer();
    final hosted = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: _ControlledFallback(),
    );
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: hosted,
          cacheLastRender: true,
        ),
      ),
    );
    await _pumpUntil(tester, () => server.requests.length == 1);
    if (server.requests.isNotEmpty) {
      server.requests[0].complete(
        _hostedResponse(_blobEnvelope('Actor A cached', version: 1)),
      );
    }
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    SurfaceAssignmentKeyProvider.current = () => 'actor-b';
    final failing = _ControlledFailureResolver();
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'pro_upgrade',
          resolver: failing,
          cacheLastRender: true,
          errorBuilder: (_, __) => const Text('Current actor error'),
        ),
      ),
    );
    failing.completeError(
      const RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable,
        message: 'No current-generation payload.',
      ),
    );
    await tester.pumpAndSettle();

    final observed = (
      actorA: find.text('Actor A cached').evaluate().length,
      error: find.text('Current actor error').evaluate().length,
      resolverCalls: failing.calls,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(observed, (actorA: 0, error: 1, resolverCalls: 1));
  });

  testWidgets(
      'a build-throwing fresh hosted blob never replaces resolver last-good',
      (tester) async {
    registerThrowingWidget();
    final server = _ControlledHostedServer();
    final resolver = RestageVariantResolver(
      apiKey: 'rs_pk_test',
      environment: RestageEnvironment.sandbox,
      baseUrl: 'https://surfaces.example.com',
      httpClient: server.client,
      assetFallback: const _AlwaysFailingFallback(),
    );
    final events = <RestageEvent>[];
    SurfaceAssignmentKeyProvider.current = () => 'actor-a';

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
        errorBuilder: (_, __) => const Text('Hosted render unavailable'),
      ),
    ));
    await _pumpUntil(tester, () => server.requests.length == 1);
    server.requests[0].complete(
      _hostedResponse(_blobEnvelope('Resolver last-good', version: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resolver last-good'), findsOneWidget);

    events.clear();
    final refresh = Restage.reloadSurfaces();
    await _pumpUntil(tester, () => server.requests.length == 2);
    server.requests[1].complete(
      _hostedResponse(
        _rawBlobEnvelope(_throwingBlob(), version: 2),
      ),
    );
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('Resolver last-good'), findsOneWidget);
    expect(events.whereType<PaywallLoadFailed>(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    events.clear();
    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: resolver,
        onEvent: events.add,
        errorBuilder: (_, __) => const Text('Hosted render unavailable'),
      ),
    ));
    await _pumpUntil(tester, () => server.requests.length == 3);
    server.requests[2].complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();

    final observed = (
      lastGood: find.text('Resolver last-good').evaluate().length,
      error: find.text('Hosted render unavailable').evaluate().length,
      viewedVersions: events
          .whereType<PaywallViewed>()
          .map((event) => event.publishedVersion)
          .toList(),
      loadCacheHits: events
          .whereType<PaywallLoadCompleted>()
          .map((event) => event.cacheHit)
          .toList(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (lastGood: observed.lastGood, error: observed.error),
      (
        lastGood: 1,
        error: 0,
      ),
    );
    expect(observed.viewedVersions, orderedEquals(<int?>[1]));
    expect(observed.loadCacheHits, orderedEquals(<bool>[true]));
  });

  testWidgets(
      'a rejected staged blob is layout-neutral under loose constraints and '
      'never paints stale content', (tester) async {
    _registerLayoutResetProbe();
    final resolver = _ControlledPayloadResolver();
    final lease = await _configuredLease();
    const paywallKey = ValueKey<String>('loose-paywall');

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RestagePaywall(
          key: paywallKey,
          id: 'pro_upgrade',
          resolver: resolver,
        ),
      ),
    ));
    await tester.pump();
    resolver.responses.single.complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _sizedBlob('Last good size', width: 80, height: 40),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 1,
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(paywallKey)), const Size(80, 40));

    final refresh = Restage.reloadSurfaces();
    await tester.pump();
    resolver.responses[1].complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _layoutResetBlob(),
        paywallId: 'pro_upgrade',
        paywallPublishedVersion: 2,
      ),
      assignmentLease: lease,
    ));
    await refresh;
    await tester.pump();

    final rejectedObserved = (
      size: tester.getSize(find.byKey(paywallKey)),
      lastGood: find.text('Last good size').evaluate().length,
      stalePaints: _LayoutResetProbe.paintCount,
    );

    await _pumpUntil(tester, () => resolver.responses.length == 3);
    if (resolver.responses.length == 3) {
      resolver.responses[2].complete(BlobPaywallPayload(
        ResolvedVariant(
          bytes: _sizedBlob('Actor B size', width: 90, height: 50),
          paywallId: 'pro_upgrade',
          paywallPublishedVersion: 3,
        ),
      ));
    }
    await tester.pumpAndSettle();
    final actorB = find.text('Actor B size').evaluate().length;
    final resolverCalls = resolver.responses.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      (
        rejected: rejectedObserved,
        actorB: actorB,
        resolverCalls: resolverCalls,
      ),
      (
        rejected: (
          size: const Size(80, 40),
          lastGood: 1,
          stalePaints: 0,
        ),
        actorB: 1,
        resolverCalls: 3,
      ),
    );
  });

  testWidgets(
      'unmounting uncommitted blob and flow candidates tears down silently '
      'without a retry', (tester) async {
    final lease = await _configuredLease();
    final events = <RestageEvent>[];
    final blobResolver = _ControlledPayloadResolver();
    final flowResolver = _ControlledPayloadResolver();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pending_blob',
        resolver: blobResolver,
        onEvent: events.add,
      ),
    ));
    await tester.pump();
    blobResolver.responses.single.complete(BlobPaywallPayload(
      ResolvedVariant(
        bytes: _blob('Never painted blob'),
        paywallId: 'pending_blob',
      ),
      assignmentLease: lease,
    ));
    // Drain resolution and staging without pumping the scheduled paint frame.
    await tester.idle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: RestagePaywall(
        id: 'pending_flow',
        resolver: flowResolver,
        onEvent: events.add,
      ),
    ));
    await tester.pump();
    flowResolver.responses.single.complete(FlowPaywallPayload(
      flow: resolvedFlow(welcomeText: 'Never painted flow'),
      paywallId: 'pending_flow',
      assignmentLease: lease,
    ));
    // The controller may resolve its entry in idle, but authority remains
    // pending because the guard can commit only from paint.
    await tester.idle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    Restage.reset();
    await tester.idle();
    await tester.pump();

    expect(
      (
        blobResolverCalls: blobResolver.responses.length,
        flowResolverCalls: flowResolver.responses.length,
        completed: events.whereType<PaywallLoadCompleted>().length,
        viewed: events.whereType<PaywallViewed>().length,
        failed: events.whereType<PaywallLoadFailed>().length,
        dismissed: events.whereType<PaywallDismissed>().length,
        escaped: tester.takeException(),
      ),
      (
        blobResolverCalls: 1,
        flowResolverCalls: 1,
        completed: 0,
        viewed: 0,
        failed: 0,
        dismissed: 0,
        escaped: null,
      ),
    );
  });
}

final class _HeldFirstPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _HeldFirstPayloadResolver(this._inner);

  final RestageVariantResolver _inner;
  final Completer<void> firstPayloadReady = Completer<void>();
  final Completer<void> releaseFirstPayload = Completer<void>();
  int calls = 0;

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    calls += 1;
    final payload = await _inner.resolvePayload(
      id,
      placementId: placementId,
      locale: locale,
    );
    if (calls == 1) {
      firstPayloadReady.complete();
      await releaseFirstPayload.future;
    }
    return payload;
  }

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      _inner.resolve(id, placementId: placementId, locale: locale);
}

final class _ControlledPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  final List<Completer<ResolvedPaywallPayload>> responses = [];

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    final response = Completer<ResolvedPaywallPayload>();
    responses.add(response);
    return response.future;
  }
}

enum _ResetTiming { duringBuild, afterFirstPaintAcceptance }

final class _ResetPaintProbe extends StatelessWidget {
  const _ResetPaintProbe();

  static _ResetTiming timing = _ResetTiming.duringBuild;
  static bool resetTriggered = false;
  static int paintCount = 0;

  static void reset() {
    timing = _ResetTiming.duringBuild;
    resetTriggered = false;
    paintCount = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!resetTriggered) {
      resetTriggered = true;
      switch (timing) {
        case _ResetTiming.duringBuild:
          Restage.reset();
        case _ResetTiming.afterFirstPaintAcceptance:
          WidgetsBinding.instance.addPostFrameCallback((_) => Restage.reset());
      }
    }
    return const _PaintProbe();
  }
}

final class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbeRenderBox();
}

final class _PaintProbeRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(48));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _ResetPaintProbe.paintCount += 1;
    context.canvas.drawRect(
      offset & size,
      Paint()..color = Colors.orange,
    );
  }
}

void _registerResetPaintProbe(_ResetTiming timing) {
  _ResetPaintProbe.reset();
  _ResetPaintProbe.timing = timing;
  Restage.registerWidgetLibrary(
    const WidgetLibrary.custom('acme.identity_reset'),
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ResetPaintProbe',
        builder: (_, __) => const _ResetPaintProbe(),
      ),
    ],
    capabilityVersion: 1,
  );
}

Future<SurfaceAssignmentResolutionLease> _configuredLease() async {
  Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'http://127.0.0.1:1',
  );
  return SurfaceAssignmentKeyProvider.captureLease();
}

Future<SurfaceAssignmentResolutionLease>
    _leaseThatResetsAfterNextValidation() async {
  Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'http://127.0.0.1:1',
  );
  var generation = 0;
  var resetAfterNextCheck = false;
  SurfaceAssignmentKeyProvider.install(
    key: () => 'actor-a',
    identityGeneration: () {
      final captured = generation;
      if (resetAfterNextCheck) {
        resetAfterNextCheck = false;
        scheduleMicrotask(() {
          generation += 1;
          Restage.reset();
        });
      }
      return captured;
    },
  );
  final lease = await SurfaceAssignmentKeyProvider.captureLease();
  resetAfterNextCheck = true;
  return lease;
}

Uint8List _resettingBlob() {
  const source = '''
    import acme.identity_reset;
    widget Paywall = ResetPaintProbe();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

ResolvedFlow _resettingFlow() {
  final welcome = _resettingFlowScreenBlob();
  return resolvedFlow(
    screenBlobs: <String, Uint8List>{
      'welcome': welcome,
      'profile': screenBlob('Profile', 'finish'),
    },
  );
}

Uint8List _resettingFlowScreenBlob() {
  const source = '''
    import acme.identity_reset;
    widget OnboardingScreen = ResetPaintProbe();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

final class _ControlledHostedServer {
  _ControlledHostedServer() {
    client = _delivery.client((request) {
      final pending = _PendingHostedRequest(request);
      requests.add(pending);
      return pending.response.future;
    });
  }

  late final MockClient client;
  final List<_PendingHostedRequest> requests = <_PendingHostedRequest>[];
}

final class _PostResolverIdentityDrift {
  int generation = 0;
  int completedDrifts = 0;
  int? _remainingReads;

  int read() {
    final captured = generation;
    final remaining = _remainingReads;
    if (remaining == null) return captured;
    if (remaining > 1) {
      _remainingReads = remaining - 1;
      return captured;
    }
    _remainingReads = null;
    // The strict presentation's final recapture receives [captured]. Advance
    // the backing generation immediately afterward so the host's first
    // post-await recapture is the first observer of the new identity.
    generation += 1;
    completedDrifts += 1;
    return captured;
  }

  void driftAfterPresentationFinalRecapture() {
    assert(_remainingReads == null, 'Only one drift may be armed at a time.');
    // Response acceptance, prefetch entry, closure completion, prefetch
    // completion, then the presentation's final pending-promotion recapture.
    _remainingReads = 5;
  }
}

final class _ThrowingRetryAuthority
    implements FlowPaywallExperimentRetryAuthority, FlowResolver {
  _ThrowingRetryAuthority(this.flow);

  final ResolvedFlow flow;
  int retryCalls = 0;
  bool _disposed = false;

  @override
  bool revalidate(FlowMountRevalidationBoundary boundary) =>
      !_disposed && boundary != FlowMountRevalidationBoundary.firstPaint;

  @override
  Future<FlowPaywallPayload?> resolveNextPayload() {
    retryCalls += 1;
    throw StateError('retained retry failed');
  }

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> requestedFlow) async =>
      flow;

  @override
  void publishHostedLastGood() {}

  @override
  void abandonHostedLastGood() {}

  @override
  void disposePresentation() => _disposed = true;
}

final class _PendingHostedRequest {
  _PendingHostedRequest(this.request);

  final http.Request request;
  final Completer<http.Response> response = Completer<http.Response>();

  void complete(http.Response value) => response.complete(value);
}

final class _ControlledFallback implements VariantResolver {
  int calls = 0;
  Completer<ResolvedVariant>? _pending;

  bool get hasPending => _pending != null && !_pending!.isCompleted;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    calls += 1;
    return (_pending = Completer<ResolvedVariant>()).future;
  }

  void complete(ResolvedVariant value) => _pending!.complete(value);
}

final class _AlwaysFailingFallback implements VariantResolver {
  const _AlwaysFailingFallback();

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    throw const RestagePaywallError(
      code: RestageErrorCodes.deliveryUnavailable,
      message: 'No bundled fallback.',
    );
  }
}

final class _ControlledFailureResolver implements VariantResolver {
  int calls = 0;
  final Completer<ResolvedVariant> _pending = Completer<ResolvedVariant>();

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    calls += 1;
    return _pending.future;
  }

  void completeError(RestagePaywallError error) =>
      _pending.completeError(error);
}

String? _assignmentKey(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  return body['assignmentKey'] as String?;
}

http.Response _hostedResponse(
  Uint8List envelope, {
  String? decision,
  String? experimentId,
  String? variantId,
  int? experimentEpoch,
}) {
  return http.Response(
    jsonEncode({
      ..._delivery.describeEnvelope(envelope),
      if (decision != null) 'decision': decision,
      if (experimentId != null) 'experimentId': experimentId,
      if (variantId != null) 'variantId': variantId,
      if (experimentEpoch != null) 'experimentEpoch': experimentEpoch,
    }),
    200,
  );
}

Map<String, Object?> _requestJson(http.Request request) =>
    (jsonDecode(request.body) as Map).cast<String, Object?>();

Uint8List _strictFlowEnvelope({
  required Uint8List screen,
  required int version,
  List<LibraryRequirement> requiredLibraries = const <LibraryRequirement>[],
}) {
  final document = _strictFlowDocument(screen: screen);
  return SurfaceDocumentCodec.encode(SurfaceDocument(
    surfaceType: Surface.paywall,
    surfaceSlug: 'pro_upgrade',
    version: version,
    minClient: document.minClient,
    requiredLibraries: requiredLibraries,
    payload: FlowSurfacePayload(
      flowDocument: document,
      screenBlobs: <String, Uint8List>{'welcome': screen},
      requiredLibraries: requiredLibraries,
    ),
    publishedAt: DateTime.utc(2026),
  ));
}

FlowDocument _strictFlowDocument({required Uint8List screen}) {
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

final class _StrictPaywallAssetBundle extends CachingAssetBundle {
  _StrictPaywallAssetBundle({
    required FlowDocument document,
    required Map<String, Uint8List> screens,
  }) : _assets = <String, Uint8List>{
          'assets/paywalls/${document.flow}.flow.json': Uint8List.fromList(
            FlowDocumentCodec.encodeCanonicalJson(document),
          ),
          for (final entry in screens.entries)
            'assets/paywalls/screens/${entry.key}':
                Uint8List.fromList(entry.value),
        };

  final Map<String, Uint8List> _assets;
  final List<String> loadedKeys = <String>[];

  void replace({
    required FlowDocument document,
    required Map<String, Uint8List> screens,
  }) {
    _assets
      ..clear()
      ..['assets/paywalls/${document.flow}.flow.json'] =
          Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document))
      ..addAll(<String, Uint8List>{
        for (final entry in screens.entries)
          'assets/paywalls/screens/${entry.key}':
              Uint8List.fromList(entry.value),
      });
  }

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final bytes = _assets[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Uint8List _blobEnvelope(String text, {required int version}) {
  return _rawBlobEnvelope(_blob(text), version: version);
}

Uint8List _rawBlobEnvelope(Uint8List blob, {required int version}) {
  const minClient = RestageBuiltInCatalogCapabilities.currentVersion;
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: Surface.paywall,
      surfaceSlug: 'pro_upgrade',
      version: version,
      minClient: minClient,
      payload: BlobSurfacePayload(minClient: minClient, blob: blob),
      publishedAt: DateTime.utc(2026),
    ),
  );
}

Uint8List _blob(String text) {
  final source = '''
    import restage.core;
    widget Paywall = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _throwingBlob() {
  const source = '''
    import acme.throwing;
    widget Paywall = ThrowingWidget();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

final class _ResetThenThrowProbe extends StatelessWidget {
  const _ResetThenThrowProbe();

  static bool resetTriggered = false;

  @override
  Widget build(BuildContext context) {
    if (!resetTriggered) {
      resetTriggered = true;
      Restage.reset();
    }
    throw StateError('stale actor build failed');
  }
}

void _registerResetThenThrowProbe() {
  _ResetThenThrowProbe.resetTriggered = false;
  Restage.registerWidgetLibrary(
    const WidgetLibrary.custom('acme.reset_then_throw'),
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'ResetThenThrowProbe',
        builder: (_, __) => const _ResetThenThrowProbe(),
      ),
    ],
  );
}

Uint8List _resetThenThrowBlob() {
  const source = '''
    import acme.reset_then_throw;
    widget Paywall = ResetThenThrowProbe();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

ResolvedFlow _resetThenThrowFlow() {
  final welcome = _resetThenThrowFlowScreenBlob();
  return resolvedFlow(
    screenBlobs: <String, Uint8List>{
      'welcome': welcome,
      'profile': screenBlob('Profile', 'finish'),
    },
  );
}

Uint8List _resetThenThrowFlowScreenBlob() {
  const source = '''
    import acme.reset_then_throw;
    widget OnboardingScreen = ResetThenThrowProbe();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

final class _LayoutResetProbe extends LeafRenderObjectWidget {
  const _LayoutResetProbe();

  static bool resetTriggered = false;
  static int paintCount = 0;

  static void reset() {
    resetTriggered = false;
    paintCount = 0;
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    if (!resetTriggered) {
      resetTriggered = true;
      Restage.reset();
    }
    return _LayoutResetRenderBox();
  }
}

final class _LayoutResetRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size(300, 200));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _LayoutResetProbe.paintCount += 1;
    context.canvas.drawRect(
      offset & size,
      Paint()..color = Colors.red,
    );
  }
}

void _registerLayoutResetProbe() {
  _LayoutResetProbe.reset();
  Restage.registerWidgetLibrary(
    const WidgetLibrary.custom('acme.layout_reset'),
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'LayoutResetProbe',
        builder: (_, __) => const _LayoutResetProbe(),
      ),
    ],
  );
}

Uint8List _layoutResetBlob() {
  const source = '''
    import acme.layout_reset;
    widget Paywall = LayoutResetProbe();
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _sizedBlob(
  String text, {
  required double width,
  required double height,
}) {
  final source = '''
    import restage.core;
    widget Paywall = SizedBox(
      width: $width,
      height: $height,
      child: Text(text: "$text"),
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
  Duration step = Duration.zero,
}) async {
  for (var attempt = 0; attempt < maxPumps && !condition(); attempt += 1) {
    await tester.pump(step);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
