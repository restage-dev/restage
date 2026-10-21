import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/delivery/placement_decision_store.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/runtime/placement_discovery.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart' as flows;
import '../fixtures/compiled_surfaces/native_flow.dart' as native;
import '../support/placement_delivery_fixture.dart';
import '../surface_screen/surface_screen_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    Restage.debugReset();
    debugResetAppBuildOrdinal();
    debugResetOsVersion();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  });
  tearDown(() {
    Restage.debugReset();
    sharedSurfaceArtifactStore = null;
  });

  for (final surfaceExperiment in [false, true]) {
    testWidgets(
        'painted placement exposes its nearest experiment ($surfaceExperiment)',
        (tester) async {
      final placementSelection = PublicExperimentSelectionV1(
        experimentId: ExperimentPublicIdV1('experiment.placement'),
        experimentRevisionId:
            ExperimentPublicRevisionIdV1('revision.placement'),
        experimentEpochId: ExperimentPublicEpochIdV1('epoch.placement'),
        armId: ExperimentPublicArmIdV1('arm.placement'),
      );
      final surfaceSelection = PublicExperimentSelectionV1(
        experimentId: ExperimentPublicIdV1('experiment.surface'),
        experimentRevisionId: ExperimentPublicRevisionIdV1('revision.surface'),
        experimentEpochId: ExperimentPublicEpochIdV1('epoch.surface'),
        armId: ExperimentPublicArmIdV1('arm.surface'),
      );
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) => placementFixtureResponse(
                request,
                placementExperiment: placementSelection,
                surfaceExperiment: surfaceExperiment ? surfaceSelection : null,
              ));
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final definition = _paywallDefinition('original', host);
      final events = <RestageEvent>[];
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          isNull);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        onEvent: events.add,
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      expect(find.text('Welcome'), findsOneWidget);
      final expected =
          surfaceExperiment ? surfaceSelection : placementSelection;
      final assignment =
          Restage.assignmentFor('original', surfaceType: Surface.paywall)!;
      expect(assignment.experimentId, expected.experimentId.value);
      expect(
          assignment.experimentRevisionId, expected.experimentRevisionId.value);
      expect(assignment.experimentEpochId, expected.experimentEpochId.value);
      expect(assignment.variantId, expected.armId.value);
      final viewed = events.whereType<PaywallViewed>().single;
      expect(viewed.assignment, assignment);
      expect(
          viewed.analyticsProperties['restage_variant'], expected.armId.value);
      await tester.pumpWidget(const SizedBox());
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          assignment);
      Restage.reset();
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          isNull);
    });
  }

  testWidgets(
      'configure sends one keyless batch for generated and remembered mounts',
      (tester) async {
    final fixture = readPlacementDeliveryFixture();
    final host = fixture.request.buildContract.contractsByHash.values.first;
    final definitions = <GeneratedPlacementDefinition>[
      for (final name in ['one', 'two']) _paywallDefinition(name, host),
    ];
    final requests = <PlacementBatchRequestV1>[];
    final dynamicMount = PlacementMountBinding(
            definition: () => definitions.first, name: 'seen_card')
        .capture();
    await PlacementDecisionStore(
            scope: SurfaceStoreKey.scopeFor(
                apiKey: 'rs_pk_test',
                environment: 'production',
                baseUrl: 'https://example.com'),
            store: sharedSurfaceArtifactStore)
        .remember(dynamicMount.mount, dynamicMount.host, () => true);
    _configure(requests, surfaces: definitions);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.mounts, hasLength(3));
    expect(request.mode, PlacementBatchModeV1.prefetch);
    expect(request.assignmentKey, isNull);
    expect(request.registration, isNull);
    expect(request.heldAssignments, isEmpty);
    expect(request.buildContract.mounts, hasLength(3));
    expect(request.buildContract.contractsByHash, hasLength(1));
    expect(
        request.mounts.any((mount) => mount.key.slug == 'seen_card'), isTrue);
  });

  testWidgets(
      'dynamic paywall mount posts its named binding and renders selected content',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
            id: 'original',
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'home_card'),
            fallbackBuilder: (_) => const Text('Original'))));
    await _finish(tester);
    final rendered = find.text('Welcome').evaluate().length;
    final originals = find.text('Original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(rendered, 1,
        reason: 'requests: ${requests.length}, originals: $originals');
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.key.slug, 'home_card');
    expect(requests.single.mode, PlacementBatchModeV1.mount);
    expect(originals, 0);
    final keys = await sharedSurfaceArtifactStore.keys();
    expect(
        keys.where((key) => key.surfaceType == 'placementMount'), hasLength(1));
  });

  testWidgets('an unhosted paywall default adopts a pushed publication',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request)
            : _watchedFallback(request));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Welcome'), findsNothing);
      expect(requests, hasLength(1));
      final scope = channel.controllers.keys.single;
      expect(scope.root.placement!.key, definition.key);
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(find.text('Welcome'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a paywall adopts a pushed flow from its settled fallback',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                payload: payload,
                requirement: requirement,
                family: const DeliveryFamilySelectorV1.general(),
                watch: (delivery) => PlacementDeliveryWatchV1(
                        decisionIdentityDigest: CanonicalDigest('e' * 64),
                        channels: [
                          for (final scope in delivery.dependencyClosure)
                            PlacementDeliveryWatchChannelV1(
                                scope: scope, token: _watchToken)
                        ]))
            : _watchedFallback(request));
    final definition = _paywallDefinition('original', host);
    final flowView =
        find.byWidgetPredicate((widget) => widget is RestageFlowView);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Original'), findsOneWidget);
      final scope = channel.controllers.keys.single;
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(find.text('Selected journey'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
      final painted = tester.state(flowView);
      // An unchanged push neither stages nor replaces the painted flow.
      for (final scope in channel.controllers.keys) {
        channel.controllers[scope]!.add(scope);
      }
      await tester.pump();
      expect(flowView, findsOneWidget);
      await _finish(tester);
      expect(requests.length, greaterThan(2));
      expect(flowView, findsOneWidget);
      expect(tester.state(flowView), same(painted));
      expect(find.text('Selected journey'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a watched fallback renews its socket without resolving after a drop',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _ReconnectingChannel();
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: _watchedFallback);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Original'), findsOneWidget);
      expect(requests, hasLength(1));
      final scope = channel.subscriptions.keys.single;
      // A token expiry and a socket drop, then ten quiet minutes.
      await channel.drop(scope);
      await _finish(tester);
      await channel.drop(scope);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(requests.where((r) => r.mode == PlacementBatchModeV1.mount),
          hasLength(1));
      expect(requests.where((r) => r.mode == PlacementBatchModeV1.refresh),
          hasLength(2));
      expect(channel.reconnects, 2);
      expect(find.text('Original'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a resolve that renews the fallback token resubscribes its watch',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _ReconnectingChannel();
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => _watchedFallback(request,
            token: requests.length == 1 ? _watchToken : _renewedWatchToken));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      final scope = channel.subscriptions.keys.single;
      channel.subscriptions[scope]!.controller.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(
          channel.watches.map((watch) => watch!.channels.single.token).toList(),
          [_watchToken, _renewedWatchToken]);
      expect(find.text('Original'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final screen in [false, true]) {
    testWidgets(
        'generated ${screen ? 'screen' : 'paywall'} wrapper owns its presented first paint across rebuilds',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final requirement = SurfaceFitRequirementV1.fromJson({
        ...readPlacementDeliveryFixture()
            .response
            .decisions
            .whereType<PlacementBatchAvailableV1>()
            .first
            .publicDelivery
            .fitRequirement
            .toJson(),
        'hosting': {
          'contentKind': 'single',
          'allowedPresentations': ['inline', 'presented']
        }
      });
      _configure(requests,
          requirement: requirement,
          family: screen
              ? DeliveryFamilySelectorV1.screenContract(contractVersion: 1)
              : const DeliveryFamilySelectorV1.general());
      final receipts = SurfaceDeliveryReceiptBatch.instance
        ..enabled = true
        ..deviceSource = () async => (platform: 'android', appBuild: 42);
      late BuildContext hostContext;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        hostContext = context;
        return const Text('Home');
      })));
      late PlacementPresentationController presentation;
      final pending =
          Restage.presentPlacement(hostContext, builder: (context, controller) {
        presentation = controller;
        return screen
            ? const native.NativeNoticeSurface.atPlacement(
                'notice_slot', 'Notice original', 3)
            : const native.NativeOfferSurface.atPlacement('offer_slot');
      });
      try {
        await _finish(tester);
        await tester.pumpAndSettle();
        expect(find.text('Welcome'), findsOneWidget);
        expect(requests, hasLength(1));
        final request = requests.single;
        final mount = request.mounts.single;
        expect(mount.key.slug, screen ? 'notice_slot' : 'offer_slot');
        expect(
            request.buildContract.contractsByHash[mount.hostContractHash]!
                .hosting.presentation,
            SurfacePresentationV1.presented);
        final firstPaint = await receipts.drain();
        expect(firstPaint.presentations, 1);
        expect(firstPaint.entries().single.receipt.outcome,
            SurfaceDeliveryReceiptOutcome.painted);
        expect(firstPaint.entries().single.receipt.attribution!.placementKey,
            mount.key);
        final wrapper = screen
            ? find.byType(native.NativeNoticeSurface)
            : find.byType(native.NativeOfferSurface);
        final actualHost = screen
            ? find.byWidgetPredicate((widget) => widget is RestageScreen)
            : find.byType(RestagePaywall);
        final hostState = tester.state(actualHost);
        tester.element(wrapper).markNeedsBuild();
        await _finish(tester);
        expect(tester.state(actualHost), same(hostState));
        expect(find.text('Welcome'), findsOneWidget);
        expect((await receipts.drain()).isEmpty, isTrue,
            reason: 'An unchanged generated getter must not open a new paint.');
        expect(requests, hasLength(1));
        expect(Restage.renderDeadline, const Duration(milliseconds: 300));
      } finally {
        presentation.close();
        await tester.pumpAndSettle();
        await pending;
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
      'emitted flow accepts hosted first paint and renews only for a changed name',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <Object>[];
    final selected = flows.childScreenFlow(text: 'Hosted generated flow');
    final document = selected.document
        .copyWith(flow: 'selected_generated_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: FlowHostBoundaryV1.fromDocument(document, signals: {}));
    _configure(requests,
        payload: payload,
        requirement: requirement,
        family: const DeliveryFamilySelectorV1.general());
    final receipts = SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = () async => (platform: 'android', appBuild: 42);
    final completions = <native.NativeClassResult>[];
    Widget build(String placement) => MaterialApp(
        home: native.NativeClassFlowSurface.atPlacement(placement,
            onFlowUnavailable: failures.add, onComplete: completions.add));
    try {
      await tester.pumpWidget(build('journey_slot'));
      final host = find.byType(native.NativeClassFlowSurface);
      final hostState = tester.state(host);
      final emitted = tester.widget<native.NativeClassFlowSurface>(host);
      expect(emitted.placementBinding, isNot(same(emitted.placementBinding)));
      await _finish(tester);
      expect(find.text('Hosted generated flow'), findsOneWidget,
          reason: failures.toString());
      expect(find.text('Preferences original'), findsNothing);
      expect(requests, hasLength(1), reason: failures.toString());
      expect(requests.single.mounts.single.key.slug, 'journey_slot');
      final firstPaint = await receipts.drain();
      expect(firstPaint.presentations, 1);
      final firstReceipt = firstPaint.entries().single.receipt;
      expect(firstReceipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
      expect(firstReceipt.attribution!.placementKey!.slug, 'journey_slot');
      await tester.pumpWidget(build('journey_slot'));
      await _finish(tester);
      expect(tester.state(host), same(hostState));
      expect(find.text('Hosted generated flow'), findsOneWidget);
      expect((await receipts.drain()).isEmpty, isTrue);
      expect(requests, hasLength(1));
      await tester.pumpWidget(build('changed_journey'));
      await _finish(tester);
      expect(tester.state(host), same(hostState));
      expect(requests, hasLength(2));
      expect(requests.last.mounts.single.key.slug, 'changed_journey');
      final changedPaint = await receipts.drain();
      expect(changedPaint.presentations, 1);
      final changedReceipt = changedPaint.entries().single.receipt;
      expect(changedReceipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
      expect(changedReceipt.attribution!.placementKey!.slug, 'changed_journey');
      expect(changedReceipt.attribution!.mountNonceDigest,
          isNot(firstReceipt.attribution!.mountNonceDigest));
      expect(Restage.renderDeadline, const Duration(milliseconds: 300));
      await tester.tap(find.text('Hosted generated flow'));
      await _finish(tester);
      expect(completions, hasLength(1));
      expect(failures, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'screen host consumes the selected own family through its original race',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final original = stringScreenFixture(
        slug: 'original_notice', schema: SurfaceScreenEventSchema(events: []));
    final channel = _PlacementWatchRecorder();
    var contract = 7;
    var digest = CanonicalDigest('c' * 64);
    var failRefresh = false;
    _configure(requests,
        liveRefresh: {
          SurfaceRefreshTrigger.appResume,
          SurfaceRefreshTrigger.updateChannel
        },
        updateChannel: channel, respond: (request) {
      if (failRefresh) throw StateError('The refresh is unavailable.');
      return placementFixtureResponse(request,
          family: DeliveryFamilySelectorV1.screenContract(
              contractVersion: contract),
          watch: (delivery) => PlacementDeliveryWatchV1(
                  decisionIdentityDigest: digest,
                  channels: [
                    for (final scope in delivery.dependencyClosure)
                      PlacementDeliveryWatchChannelV1(
                          scope: scope, token: _watchToken)
                  ]));
    });
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family: DeliveryFamilySelectorV1.screenContract(
                contractVersion: original.ref.contractVersion)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageScreen(
            screen: original.ref,
            placementBinding:
                PlacementMountBinding(definition: () => definition),
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
                builder: (_, __) => const Text('Original')))));
    await _finish(tester);
    expect(requests, hasLength(1));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
    expect(requests.single.mounts.single.defaultSurface!.family.contractVersion,
        1);
    failRefresh = true;
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final retained = find.text('Welcome').evaluate().length;
    failRefresh = false;
    contract = 8;
    digest = CanonicalDigest('d' * 64);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final updated = find.text('Welcome').evaluate().length;
    final accepted = channel.watches.toList();
    await tester.pumpWidget(const SizedBox());
    Restage.debugReset();
    expect(retained, 1);
    expect(updated, 1);
    expect(requests.map((request) => request.mode).toList(), [
      PlacementBatchModeV1.mount,
      PlacementBatchModeV1.refresh,
      PlacementBatchModeV1.mount,
      PlacementBatchModeV1.refresh,
      PlacementBatchModeV1.mount
    ]);
    expect(accepted.last.decisionIdentityDigest, digest);
    expect(accepted.last.channels.map((entry) => entry.scope.family),
        contains(DeliveryFamilySelectorV1.screenContract(contractVersion: 8)));
  });

  testWidgets('mounted expiry uses local fallback without another request',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    var now = DateTime.utc(2026, 10, 4, 12);
    _configure(requests, now: () => now, cacheValidityOverrides: {
      'contentExpiresAtMicros':
          now.add(const Duration(seconds: 1)).microsecondsSinceEpoch
    });
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement(
            id: 'expiring_card', fallback: (_) => const Text('Original'))));
    await _finish(tester);
    final selectedBefore = find.text('Welcome').evaluate().length;
    now = now.add(const Duration(seconds: 1));
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final originalAfter = find.text('Original').evaluate().length;
    final selectedAfter = find.text('Welcome').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(selectedBefore, 1);
    expect(originalAfter, 1);
    expect(selectedAfter, 0);
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.surfaceType, isNull);
  });

  testWidgets('renderless fallbacks remain capturable without painted claims',
      (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final reports = <PlacementDiscoveryReportV1>[];
    PlacementDiscovery.instance.configure(
        installedCapability: currentInstalledCapability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        });
    final original = stringScreenFixture(
        slug: 'fallback_notice', schema: SurfaceScreenEventSchema(events: []));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final screenDefinition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family:
                DeliveryFamilySelectorV1.screenContract(contractVersion: 1)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    const flow = SurfaceFlowRef<void>(
        id: 'fallback_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final document = flows.childScreenFlow().document;
    final flowHost = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: FlowHostBoundaryV1.fromDocument(document, signals: {}));
    final flowDefinition = GeneratedPlacementDefinition(
        defaultSurface: flow,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: flow.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'), slug: flow.id),
        hostContract: flowHost,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      RestageScreen(
          screen: original.ref,
          placementBinding:
              PlacementMountBinding(definition: () => screenDefinition),
          resolver: const _UnavailableScreen(),
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, __) =>
                  const Expanded(child: Text('Screen fallback')))),
      RestageFlowGraph<void>(
          flow: flow,
          placementBinding:
              PlacementMountBinding(definition: () => flowDefinition),
          resolver: const _UnavailableFlow(),
          unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, __) =>
                  const Expanded(child: Text('Flow fallback')))),
    ])));
    await _finish(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final frame = PlacementDiscovery.instance
        .captureFrame(view: tester.binding.renderViews.single);
    final screenFallback = find.text('Screen fallback').evaluate().length;
    final flowFallback = find.text('Flow fallback').evaluate().length;
    final captured = frame.mounts.length;
    final claimedPaint = reports.any((report) => report.bounds.isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(screenFallback, 1);
    expect(flowFallback, 1);
    expect(captured, 2);
    expect(claimedPaint, isFalse);
  });

  for (final milliseconds in [300, 550]) {
    testWidgets(
        'placement preserves the configured $milliseconds ms fallback deadline',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      _configure(requests,
          deadline: Duration(milliseconds: milliseconds),
          delay: response.future);
      await tester.pumpWidget(MaterialApp(
          home: RestagePlacement(
              id: 'slow_card',
              loadingBuilder: (_) => const Text('Loading'),
              fallback: (_) => const Text('Original'))));
      await tester.pump(Duration(milliseconds: milliseconds - 1));
      expect(find.text('Original'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);
      response.complete();
      await _finish(tester);
      expect(
          requests
              .where((request) => request.mode == PlacementBatchModeV1.mount),
          hasLength(1));
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
    });
  }

  testWidgets(
      'flow host keeps its typed boundary while loading selected root identity',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <FlowUnavailableError>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    _configure(requests,
        payload: payload,
        requirement: requirement,
        family: const DeliveryFamilySelectorV1.general());
    const original = SurfaceFlowRef<void>(
        id: 'original_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<void>(
            flow: original,
            onFlowUnavailable: failures.add,
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'journey_slot'),
            unavailable: FlowUnavailablePolicy.fallback(
                builder: (_, __) => const Text('Original journey')))));
    await _finish(tester);
    final selectedCount = find.text('Selected journey').evaluate().length;
    final originalCount = find.text('Original journey').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1), reason: failures.toString());
    expect(requests.single.mounts.single.key.slug, 'journey_slot');
    expect(selectedCount, 1, reason: failures.toString());
    expect(originalCount, 0);
  });

  testWidgets('an unhosted flow default adopts a pushed publication',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <FlowUnavailableError>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                payload: payload,
                requirement: requirement,
                family: const DeliveryFamilySelectorV1.general())
            : _watchedFallback(request));
    const original = SurfaceFlowRef<void>(
        id: 'original_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<void>(
            flow: original,
            onFlowUnavailable: failures.add,
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'journey_slot'),
            unavailable: FlowUnavailablePolicy.fallback(
                builder: (_, __) => const Text('Original journey')))));
    await _finish(tester);
    expect(find.text('Original journey'), findsOneWidget);
    expect(requests, hasLength(1), reason: failures.toString());
    final scope = channel.controllers.keys.single;
    expect(scope.root.placement!.key.slug, 'journey_slot');
    hosted = true;
    channel.controllers[scope]!.add(scope);
    await _finish(tester);
    final selectedCount = find.text('Selected journey').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(2), reason: failures.toString());
    expect(selectedCount, 1, reason: failures.toString());
  });

  testWidgets('a flow placement hosts a typed flow and decodes its result',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final results = <Map<String, Object?>>[];
    final received = <RestageEvent>[];
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document = selected.document;
    expect(document.deliveryMode, FlowDeliveryMode.typed);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: selected.screenBlobs,
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general());
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flowForSurface(
            surfaceType: Surface.onboarding,
            surfaceId: 'original_journey',
            contract: served.host,
            onComplete: results.add,
            onEvent: received.add,
            fallback: (_) => const Text('Original journey'))));
    await _finish(tester);
    expect(find.text('Selected journey'), findsOneWidget);
    await tester.tap(find.text('Selected journey'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.surfaceType?.value, 'onboarding');
    expect(results, [<String, Object?>{}]);
    expect(received, isNotEmpty);
    expect(received.whereType<FlowStarted>(), hasLength(1));
    expect(events, containsAll(received));
  });

  testWidgets('a paywall flow placement delivers continue to the app',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final events = <RestageEvent>[];
    final received = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final offer = flows.screenBlob('Get Plus', 'continue');
    final document = _paywallFlowDocument(offer);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: {'offer': offer},
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general(),
        flowSurfaceType: 'paywall');
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flowForSurface(
            surfaceType: Surface.paywall,
            surfaceId: 'plus_offer',
            contract: served.host,
            onEvent: received.add,
            fallback: (_) => const Text('Original offer'))));
    await _finish(tester);
    expect(find.text('Get Plus'), findsOneWidget);
    await tester.tap(find.text('Get Plus'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1));
    final custom = events.whereType<PaywallCustomEvent>().single;
    expect(custom.eventName, 'continue');
    expect(custom.paywallId, 'plus_offer');
    expect(received.whereType<PaywallCustomEvent>().single, same(custom));
  });

  test('a paywall flow placement refuses flow-only callbacks', () {
    final document = flows.childScreenFlow().document;
    expect(
        () => RestagePlacement.flowForSurface(
            surfaceType: Surface.paywall,
            surfaceId: 'plus_offer',
            contract: _flowHost(document).host,
            onComplete: (_) {},
            fallback: (_) => const SizedBox()),
        throwsArgumentError);
  });

  testWidgets('a named paywall slot hosts a served paywall flow',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final received = <RestageEvent>[];
    final offer = flows.screenBlob('Get Plus', 'continue');
    final document = _paywallFlowDocument(offer);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: {'offer': offer},
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general(),
        flowSurfaceType: 'paywall');
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flow(
            id: 'upsell_slot',
            surfaceType: Surface.paywall,
            contract: served.host,
            onEvent: received.add,
            fallback: (_) => const Text('Original offer'))));
    await _finish(tester);
    await tester.tap(find.text('Get Plus'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests.single.mounts.single.key.slug, 'upsell_slot');
    expect(requests.single.mounts.single.defaultSurface, isNull);
    expect(requests.single.mounts.single.surfaceType?.value, 'paywall');
    expect(
        received.whereType<PaywallCustomEvent>().single.eventName, 'continue');
  });

  testWidgets('a named flow slot hosts a served onboarding flow',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final results = <Map<String, Object?>>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final served = _flowHost(selected.document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: selected.document,
            screenBlobs: selected.screenBlobs,
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general());
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flow(
            id: 'journey_slot',
            contract: served.host,
            onComplete: results.add,
            fallback: (_) => const Text('Original journey'))));
    await _finish(tester);
    await tester.tap(find.text('Selected journey'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests.single.mounts.single.key.slug, 'journey_slot');
    expect(requests.single.mounts.single.surfaceType?.value, 'onboarding');
    expect(results, [<String, Object?>{}]);
  });
}

FlowDocument _paywallFlowDocument(Uint8List offer) => FlowDocument(
        flow: 'plus_offer',
        version: 1,
        schemaVersion: 1,
        minClient: flows.firstRunFlowRef.minClient,
        initial: 'offer',
        actions: const {},
        screenArtifacts: {
          'offer': ScreenArtifact(
              path: 'offer.rfw',
              version: 1,
              schemaVersion: 1,
              minClient: flows.firstRunFlowRef.minClient,
              contentHash: FlowContentHash.compute(offer))
        },
        states: const {
          'offer': ScreenFlowState(
              screen: 'offer', on: {'skip': FlowTransition.goto('done')}),
          'done': EndFlowState(result: <String, Object?>{}),
        });

({SurfaceHostContractV1 host, SurfaceFitRequirementV1 requirement}) _flowHost(
    FlowDocument document) {
  final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
  return (
    host: SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary),
    requirement: SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary),
  );
}

void _decodeVoid(Map<String, Object?> value) {}

GeneratedPlacementDefinition _paywallDefinition(
        String name, SurfaceHostContractV1 host) =>
    GeneratedPlacementDefinition(
        defaultSurface: PaywallRef(name),
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('paywall'),
            slug: name,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('paywall'), slug: name),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);

void _configure(List<PlacementBatchRequestV1> requests,
    {List<RestageSurfaceRef> surfaces = const [],
    Duration deadline = const Duration(milliseconds: 300),
    Future<void>? delay,
    SurfacePayload? payload,
    SurfaceFitRequirementV1? requirement,
    DeliveryFamilySelectorV1? family,
    Set<SurfaceRefreshTrigger> liveRefresh = const {},
    SurfaceUpdateChannel? updateChannel,
    PlacementBatchResolvedV1 Function(PlacementBatchRequestV1)? respond,
    DateTime Function()? now,
    Map<String, Object?> cacheValidityOverrides = const {},
    String flowSurfaceType = 'onboarding'}) {
  Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://example.com',
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
      surfaces: surfaces,
      liveRefresh: liveRefresh,
      updateChannel: updateChannel,
      renderDeadline: deadline);
  debugResetInstallObservations();
  debugSetOsVersion(19);
  SurfaceMeteringKeyProvider.clear();
  Restage.debugPlacementNow = now ?? () => DateTime.utc(2026, 10, 4, 12);
  final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (request.method != 'POST' ||
            request.url.path != '/sdk/v1/placements/resolve') {
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        }
        final batch =
            PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
        requests.add(batch);
        if (delay != null) await delay;
        if (respond != null) {
          return http.Response.bytes(respond(batch).canonicalBytes, 200);
        }
        return http.Response.bytes(
            placementFixtureResponse(batch,
                    payload: payload,
                    requirement: requirement,
                    family: family,
                    cacheValidityOverrides: cacheValidityOverrides,
                    flowSurfaceType: flowSurfaceType)
                .canonicalBytes,
            200);
      }));
  Restage.debugRestageRpcClient = client;
  addTearDown(client.close);
}

Future<void> _finish(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

final class _UnavailableScreen implements SurfaceScreenResolver {
  const _UnavailableScreen();
  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async =>
      throw const SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.missing,
          message: 'Unavailable');
}

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

const _renewedWatchToken =
    'v2.i5p7lxR3.1767232800.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

final class _PlacementWatchRecorder implements DeliveryUpdateChannel {
  final watches = <PlacementDeliveryWatchV1>[];
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
      {PlacementDeliveryWatchV1? watch,
      Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) {
    watches.add(watch!);
    return const Stream.empty();
  }
}

final class _UnavailableFlow implements FlowResolver {
  const _UnavailableFlow();
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw StateError('Unavailable');
}

PlacementBatchResolvedV1 _watchedFallback(PlacementBatchRequestV1 request,
    {String token = _watchToken}) {
  final target = readPlacementDeliveryFixture().target;
  final mount = request.mounts.single;
  final descriptor = PlacementMountDescriptorV1(
      placement: PlacementIdentityV1(target: target, key: mount.key),
      hostContractHash: mount.hostContractHash);
  return PlacementBatchResolvedV1(
      request: request,
      expectedTarget: target,
      decisions: [
        PlacementBatchEntryV1.useFallback(
            descriptor, PlacementBatchRefusalReasonV1.unavailable, const [],
            watch: PlacementDeliveryWatchV1(
                decisionIdentityDigest: CanonicalDigest('f' * 64),
                channels: [
                  PlacementDeliveryWatchChannelV1(
                      scope: DeliveryPolicyScopeV1(
                          root: DeliveryRootIdentityV1.placement(
                              descriptor.placement),
                          family: const DeliveryFamilySelectorV1.none()),
                      token: token)
                ]))
      ],
      artifacts: const []);
}

final class _PlacementPushChannel implements DeliveryUpdateChannel {
  final controllers =
      <DeliveryPolicyScopeV1, StreamController<DeliveryPolicyScopeV1>>{};
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
          {PlacementDeliveryWatchV1? watch,
          Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) =>
      (controllers[scope] ??= StreamController.broadcast()).stream;
}

/// Reconnects as the hosted channel does: a renewed watch reconnects quietly;
/// anything else asks for resolution and retries at the backoff cap.
final class _ReconnectingChannel implements DeliveryUpdateChannel {
  final subscriptions = <DeliveryPolicyScopeV1,
      ({
    StreamController<DeliveryPolicyScopeV1> controller,
    Future<PlacementRefreshProbeV1> Function() probe
  })>{};
  final _retries = <DeliveryPolicyScopeV1, Timer>{};
  final watches = <PlacementDeliveryWatchV1?>[];
  var reconnects = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
      {PlacementDeliveryWatchV1? watch,
      Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) {
    late final StreamController<DeliveryPolicyScopeV1> controller;
    controller = StreamController(onCancel: () {
      if (identical(subscriptions[scope]?.controller, controller)) {
        subscriptions.remove(scope);
        _retries.remove(scope)?.cancel();
      }
    });
    _retries.remove(scope)?.cancel();
    subscriptions[scope] = (controller: controller, probe: reconnectProbe!);
    watches.add(watch);
    return controller.stream;
  }

  Future<void> drop(DeliveryPolicyScopeV1 scope) async {
    final subscription = subscriptions[scope];
    if (subscription == null) return;
    final probe = await subscription.probe();
    if (!identical(subscriptions[scope], subscription)) return;
    if (probe is PlacementRefreshUnchangedV1 &&
        probe.watch?.decisionIdentityDigest == probe.decisionIdentityDigest) {
      reconnects++;
      return;
    }
    subscription.controller.add(scope);
    _retries[scope] =
        Timer(const Duration(seconds: 60), () => unawaited(drop(scope)));
  }
}
