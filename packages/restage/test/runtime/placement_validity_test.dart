import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/render_deadline.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/measurement/placement_mount_attribution.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../surface_screen/surface_screen_test_support.dart';
import '../support/pump_until.dart';
import '../support/sent_placement_request.dart';

void main() {
  for (final expireBeforeRefresh in [true, false]) {
    testWidgets(
        expireBeforeRefresh
            ? 'screen refresh rearms validity after a previous hosted expiry'
            : 'screen refresh rearms an earlier hosted expiry', (tester) async {
      Restage.debugReset();
      addTearDown(Restage.debugReset);
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
          appName: 'test',
          packageName: 'test',
          version: '1',
          buildNumber: '42',
          buildSignature: '');
      debugResetAppBuildOrdinal();
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final original = stringScreenFixture(
          slug: 'original_notice',
          schema: SurfaceScreenEventSchema(events: []));
      final bundleBytes = original.bundleBytes();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        if (const StringCodec().decodeMessage(message) !=
            original.locator.assetKey) {
          return null;
        }
        return ByteData.sublistView(bundleBytes);
      });
      addTearDown(
          () => messenger.setMockMessageHandler('flutter/assets', null));
      Restage.configure(
          apiKey: 'rs_pk_test',
          baseUrl: 'https://example.com',
          analyticsEnabled: false,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false);
      debugResetInstallObservations();
      debugSetOsVersion(19);
      SurfaceMeteringKeyProvider.clear();
      // A fixed clock inside the shared fixture's civil validity window.
      var now = DateTime.utc(2026, 10, 4, 12);
      Restage.debugPlacementNow = () => now;
      var expiry = now.add(Duration(seconds: expireBeforeRefresh ? 10 : 20));
      final requests = <PlacementBatchRequestV1>[];
      final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((outgoing) async {
            final fixtureArtifact = placementFixtureArtifact(outgoing);
            if (fixtureArtifact != null) return fixtureArtifact;
            final request = sentPlacementRequest(outgoing.bodyBytes);
            requests.add(request);
            return http.Response.bytes(
                placementFixtureResponse(request,
                    family: DeliveryFamilySelectorV1.screenContract(
                        contractVersion: 7),
                    cacheValidityOverrides: {
                      'contentExpiresAtMicros': expiry.microsecondsSinceEpoch
                    }).canonicalBytes,
                200);
          }));
      addTearDown(client.close);
      Restage.debugRestageRpcClient = client;
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
          hostContract: readPlacementDeliveryFixture()
              .request
              .buildContract
              .contractsByHash
              .values
              .first,
          vocabulary: SurfaceVocabulary.none);
      final host = RestageScreen(
        screen: original.ref,
        placementBinding: PlacementMountBinding(definition: () => definition),
      );
      final previousOnError = FlutterError.onError;
      try {
        await tester.pumpWidget(MaterialApp(home: host));
        await _finishScreenFrames(tester);
        final state = tester.state(find.byWidget(host));
        expect(Restage.firstLaunchWaitFor(""),
            RenderDeadline.defaultFirstLaunchWait);
        expect(find.text('Welcome'), findsOneWidget);
        expect(find.text('Bundled screen'), findsNothing);
        expect(requests, hasLength(1));

        if (expireBeforeRefresh) {
          now = expiry;
          await tester.pump(const Duration(seconds: 11));
          await _finishScreenFrames(tester);
          expect(find.text('Bundled screen'), findsOneWidget);
          expect(find.text('Welcome'), findsNothing);
          expect(requests, hasLength(1));
          expect(tester.state(find.byWidget(host)), same(state));
        }

        expiry = now.add(Duration(seconds: expireBeforeRefresh ? 20 : 2));
        await SurfaceRefreshRegistry.instance.reload();
        await _finishScreenFrames(tester);
        expect(find.text('Welcome'), findsOneWidget);
        expect(find.text('Bundled screen'), findsNothing);
        expect(requests, hasLength(2));
        expect(tester.state(find.byWidget(host)), same(state));

        now = expiry;
        await tester.pump(Duration(seconds: expireBeforeRefresh ? 21 : 3));
        await _finishScreenFrames(tester);
        expect(find.text('Bundled screen'), findsOneWidget);
        expect(find.text('Welcome'), findsNothing);
        expect(tester.state(find.byWidget(host)), same(state));
        expect(requests.map((request) => request.mode),
            [PlacementBatchModeV1.mount, PlacementBatchModeV1.mount]);
      } finally {
        await tester.pumpWidget(const SizedBox());
        FlutterError.onError = previousOnError;
      }
    });
  }

  for (final acted in [false, true]) {
    testWidgets(
        acted
            ? 'a screen whose fallback sent an event is never swapped by a '
                'refresh'
            : 'a screen showing its fallback untouched takes a refresh',
        (tester) async {
      Restage.debugReset();
      addTearDown(Restage.debugReset);
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
          appName: 'test',
          packageName: 'test',
          version: '1',
          buildNumber: '42',
          buildSignature: '');
      debugResetAppBuildOrdinal();
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final original = stringScreenFixture(slug: 'original_notice');
      Restage.configure(
          apiKey: 'rs_pk_test',
          baseUrl: 'https://example.com',
          analyticsEnabled: false,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false);
      debugResetInstallObservations();
      debugSetOsVersion(19);
      SurfaceMeteringKeyProvider.clear();
      Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
      var hosted = false;
      final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((outgoing) async {
            final fixtureArtifact = placementFixtureArtifact(outgoing);
            if (fixtureArtifact != null) return fixtureArtifact;
            final request = sentPlacementRequest(outgoing.bodyBytes);
            if (!hosted) {
              return http.Response.bytes(
                  _watchedFallback(request).canonicalBytes, 200);
            }
            return http.Response.bytes(
                placementFixtureResponse(request,
                        family: DeliveryFamilySelectorV1.screenContract(
                            contractVersion: 7))
                    .canonicalBytes,
                200);
          }));
      addTearDown(client.close);
      Restage.debugRestageRpcClient = client;
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
          hostContract: readPlacementDeliveryFixture()
              .request
              .buildContract
              .contractsByHash
              .values
              .first,
          vocabulary: SurfaceVocabulary.none);
      final handled = <String>[];
      try {
        await tester.pumpWidget(MaterialApp(
            home: RestageScreen<String>(
                screen: original.ref,
                placementBinding:
                    PlacementMountBinding(definition: () => definition),
                onEvent: handled.add,
                fallbackBuilder: (_) => Builder(
                    builder: (context) => TextButton(
                        onPressed: context
                            .surfaceEvent(const SurfaceEvent<void>('tap')),
                        child: const Text('Fallback'))))));
        await _finishScreenFrames(tester);
        await tester.pump(const Duration(seconds: 4));
        await _finishScreenFrames(tester);
        expect(find.text('Fallback'), findsOneWidget);
        if (acted) {
          // A call without a pointer: only the event counts as progress.
          tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
          await tester.pump();
          expect(handled, ['tap']);
        }
        hosted = true;
        await SurfaceRefreshRegistry.instance.reload();
        await _finishScreenFrames(tester);
        expect(find.text('Fallback'), acted ? findsOneWidget : findsNothing);
        expect(find.text('Welcome'), acted ? findsNothing : findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('a screen the user interacted with keeps its content at expiry',
      (tester) async {
    Restage.debugReset();
    addTearDown(Restage.debugReset);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    debugResetAppBuildOrdinal();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    addTearDown(() => sharedSurfaceArtifactStore = null);
    final original = stringScreenFixture(
        slug: 'original_notice', schema: SurfaceScreenEventSchema(events: []));
    final bundleBytes = original.bundleBytes();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (const StringCodec().decodeMessage(message) !=
          original.locator.assetKey) {
        return null;
      }
      return ByteData.sublistView(bundleBytes);
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://example.com',
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false);
    debugResetInstallObservations();
    debugSetOsVersion(19);
    SurfaceMeteringKeyProvider.clear();
    var now = DateTime.utc(2026, 10, 4, 12);
    Restage.debugPlacementNow = () => now;
    final expiry = now.add(const Duration(seconds: 10));
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((outgoing) async {
          final fixtureArtifact = placementFixtureArtifact(outgoing);
          if (fixtureArtifact != null) return fixtureArtifact;
          final request = sentPlacementRequest(outgoing.bodyBytes);
          return http.Response.bytes(
              placementFixtureResponse(request,
                  family: DeliveryFamilySelectorV1.screenContract(
                      contractVersion: 7),
                  cacheValidityOverrides: {
                    'contentExpiresAtMicros': expiry.microsecondsSinceEpoch
                  }).canonicalBytes,
              200);
        }));
    addTearDown(client.close);
    Restage.debugRestageRpcClient = client;
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
        hostContract: readPlacementDeliveryFixture()
            .request
            .buildContract
            .contractsByHash
            .values
            .first,
        vocabulary: SurfaceVocabulary.none);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestageScreen(
              screen: original.ref,
              placementBinding:
                  PlacementMountBinding(definition: () => definition))));
      await _finishScreenFrames(tester);
      expect(find.text('Welcome'), findsOneWidget);
      // Progress in this load: the user dragged the screen.
      await tester.drag(find.text('Welcome'), const Offset(0, 40));
      await tester.pump();
      now = expiry;
      await tester.pump(const Duration(seconds: 11));
      await _finishScreenFrames(tester);
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Bundled screen'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final assigned in [false, true]) {
    testWidgets(
        assigned
            ? 'painted assigned host invalidates future cache without swapping'
            : 'painted host probes and adopts a changed decision at the same version',
        (tester) async {
      Restage.debugReset();
      addTearDown(Restage.debugReset);
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
          appName: 'test',
          packageName: 'test',
          version: '1',
          buildNumber: '42',
          buildSignature: '');
      debugResetAppBuildOrdinal();
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final channel = _RecordingDeliveryChannel();
      Restage.configure(
          apiKey: 'rs_pk_test',
          baseUrl: 'https://example.com',
          analyticsEnabled: false,
          measurementEnabled: false,
          updateChannel: channel,
          liveRefresh: {
            SurfaceRefreshTrigger.appResume,
            SurfaceRefreshTrigger.updateChannel
          });
      debugResetInstallObservations();
      debugSetOsVersion(19);
      SurfaceMeteringKeyProvider.clear();
      final assignment = assigned
          ? PresentationAssignmentCarrierV2(
              owner: PresentationAssignmentOwnerV2.path,
              outcomeLinkCarrier: 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc')
          : null;
      if (assigned) {
        SurfaceAssignmentKeyProvider.current = () => 'original_credential';
        SurfaceAssignmentKeyProvider.local = () => 'original_credential';
        SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
      }
      Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
      final fixture = readPlacementDeliveryFixture();
      final skipped = DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.surface(PublishedSurfaceIdentityV1(
              target: fixture.target, surfaceId: SurfaceId('skipped_surface'))),
          family: const DeliveryFamilySelectorV1.general());
      var digest = CanonicalDigest('c' * 64);
      var contract = 7;
      Completer<void>? hold;
      final requests = <PlacementBatchRequestV1>[];
      Restage.debugRestageRpcClient = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((outgoing) async {
            final fixtureArtifact = placementFixtureArtifact(outgoing);
            if (fixtureArtifact != null) return fixtureArtifact;
            if (!outgoing.url.path.endsWith('/placements/resolve')) {
              return http.Response('{}', 200);
            }
            final request = sentPlacementRequest(outgoing.bodyBytes);
            requests.add(request);
            if (hold != null) await hold.future;
            return http.Response.bytes(
                placementFixtureResponse(request,
                    assignment: assignment,
                    additionalDependencies: {skipped},
                    family: DeliveryFamilySelectorV1.screenContract(
                        contractVersion: contract),
                    watch: (delivery) => PlacementDeliveryWatchV1(
                            decisionIdentityDigest: digest,
                            channels: [
                              for (final scope in delivery.dependencyClosure)
                                PlacementDeliveryWatchChannelV1(
                                    scope: scope, token: _watchToken)
                            ])).canonicalBytes,
                200);
          }));
      final definition = GeneratedPlacementDefinition(
          defaultSurface: const PaywallRef('original'),
          defaultSurfaceLocator: DeliverySurfaceLocatorV1(
              surfaceType: DeliverySurfaceTypeId('paywall'),
              slug: 'original',
              family: const DeliveryFamilySelectorV1.general()),
          key: PlacementKeyV1.generatedDefault(
              surfaceType: DeliverySurfaceTypeId('paywall'), slug: 'original'),
          hostContract:
              fixture.request.buildContract.contractsByHash.values.first,
          vocabulary: SurfaceVocabulary.none);
      final controller = RestagePaywallController();
      final observed = <MountAttributionSnapshotV1?>[];
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(
              width: 80,
              height: 25,
              child: RestagePaywall(
                  id: 'original',
                  controller: controller,
                  placementBinding: PlacementMountBinding(
                      definition: () => definition, name: 'home_card'),
                  fallbackBuilder: (_) => const Text('Original'),
                  onEvent: (event) {
                    if (event is PaywallCustomEvent) {
                      observed
                          .add(MountAttributionEventContext.current?.snapshot);
                    }
                  }))));
      await pumpUntil(
        tester,
        () => channel.watches.isNotEmpty,
        reason: 'the placement watch',
      );
      final initialWatch = channel.watches.toList();
      if (assigned) {
        if (initialWatch.isEmpty) {
          final rendered = find.text('Welcome').evaluate().length;
          final keys = await sharedSurfaceArtifactStore.keys();
          await tester.pumpWidget(const SizedBox());
          Restage.debugReset();
          expect(requests.map((request) => request.assignmentKey),
              ['original_credential']);
          expect(keys.where((key) => key.surfaceType == 'placementDecision'),
              hasLength(1));
          expect(rendered, 1);
          fail('The accepted host has no scoped watch.');
        }
        final before = (await sharedSurfaceArtifactStore.keys())
            .where((key) => key.surfaceType == 'placementDecision')
            .length;
        initialWatch.first.controller.add(initialWatch.first.scope);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        final remaining = (await sharedSurfaceArtifactStore.keys())
            .where((key) => key.surfaceType == 'placementDecision')
            .length;
        controller.fireEvent('inspect');
        final rendered = find.text('Welcome').evaluate().length;
        // The next mount finds the stale copy; its new answer is late, so the
        // saved arm paints, never the compiled original.
        final firstLoadRequests = requests.length;
        hold = Completer<void>();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(
            home: SizedBox(
                width: 80,
                height: 25,
                child: RestagePaywall(
                    id: 'original',
                    placementBinding: PlacementMountBinding(
                        definition: () => definition, name: 'home_card'),
                    fallbackBuilder: (_) => const Text('Original')))));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final staleShown = find.text('Welcome').evaluate().length;
        final compiledShown = find.text('Original').evaluate().length;
        hold.complete();
        await tester.pumpWidget(const SizedBox());
        Restage.debugReset();
        expect(staleShown, 1);
        expect(compiledShown, 0);
        expect(before, 1);
        expect(remaining, 1);
        expect(rendered, 1);
        expect(firstLoadRequests, 1);
        expect(observed.single!.assignment, assignment);
        expect(observed.single!.attribution.actualSurface!.family,
            DeliveryFamilySelectorV1.screenContract(contractVersion: 7));
        return;
      }
      await SurfaceRefreshRegistry.instance.onAppResumed();
      final unchangedRequests = requests.length;
      digest = CanonicalDigest('d' * 64);
      contract = 8;
      await SurfaceRefreshRegistry.instance.onAppResumed();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final updatedWatch = channel.watches.skip(initialWatch.length).toList();
      controller.fireEvent('inspect');
      final rendered = find.text('Welcome').evaluate().length;
      await tester.pumpWidget(const SizedBox());
      Restage.debugReset();
      expect(rendered, 1);
      expect(unchangedRequests, 2);
      expect(requests.map((request) => request.mode).toList(), [
        PlacementBatchModeV1.mount,
        PlacementBatchModeV1.refresh,
        PlacementBatchModeV1.refresh,
        PlacementBatchModeV1.mount
      ]);
      expect(
          requests
              .where((request) => request.mode == PlacementBatchModeV1.refresh)
              .every((request) => request.registration == null),
          isTrue);
      expect(
          initialWatch.map((watch) => watch.scope).toSet(),
          initialWatch.first.watch.channels
              .map((channel) => channel.scope)
              .toSet());
      expect(
          initialWatch.every((watch) =>
              watch.watch.decisionIdentityDigest == CanonicalDigest('c' * 64)),
          isTrue);
      expect(initialWatch.map((watch) => watch.scope), contains(skipped));
      expect(
          updatedWatch.map((watch) => watch.scope).toSet(),
          updatedWatch.first.watch.channels
              .map((channel) => channel.scope)
              .toSet());
      expect(
          updatedWatch.every((watch) =>
              watch.watch.decisionIdentityDigest == CanonicalDigest('d' * 64)),
          isTrue);
      expect(
          observed.single!.attribution.actualPublication!.publishedVersion, 9);
      expect(observed.single!.attribution.actualSurface!.family,
          DeliveryFamilySelectorV1.screenContract(contractVersion: 8));
    });
  }

  test('local civil validity includes the lower bound and excludes the upper',
      () {
    final validity = _validity(
        notBeforeLocal: LocalCivilDateTimeV1.parse('2026-10-04T12:00:00'),
        expiresBeforeLocal: LocalCivilDateTimeV1.parse('2026-10-04T13:00:00'));
    final clock = DeliveryLocalClockV1(0);
    expect(
        placementCacheIsValid(validity,
            now: DateTime.utc(2026, 10, 4, 11, 59, 59), clock: clock),
        isFalse);
    expect(
        placementCacheIsValid(validity,
            now: DateTime.utc(2026, 10, 4, 12), clock: clock),
        isTrue);
    expect(
        placementCacheIsValid(validity,
            now: DateTime.utc(2026, 10, 4, 13), clock: clock),
        isFalse);
    expect(
        placementCacheIsValid(validity,
            now: DateTime.utc(2026, 10, 4, 12), clock: null),
        isFalse);
    expect(
        placementCacheIsValid(validity,
            now: DateTime.utc(2026, 10, 4, 12),
            clock: DeliveryLocalClockV1(60)),
        isFalse);
  });

  test('receipt, assignment and content expiry independently close reuse', () {
    final expiry = DateTime.utc(2026, 10, 4, 12);
    for (final field in [
      'receiptExpiresAtMicros',
      'assignmentExpiresAtMicros',
      'contentExpiresAtMicros'
    ]) {
      final base = _validity();
      final validity = DeliveryCacheValidityV1.fromJson(
          {...base.toJson(), field: expiry.microsecondsSinceEpoch});
      expect(
          placementCacheIsValid(validity,
              now: expiry.subtract(const Duration(microseconds: 1)),
              clock: null),
          isTrue);
      expect(
          placementCacheIsValid(validity, now: expiry, clock: null), isFalse);
    }
  });

  testWidgets(
      'one shared boundary alarm invalidates locally without remote refresh',
      (tester) async {
    var now = DateTime.utc(2026, 10, 4, 12);
    final registry = SurfaceRefreshRegistry(now: () => now);
    addTearDown(registry.debugReset);
    final boundary = now.add(const Duration(seconds: 1));
    var local = 0;
    var remote = 0;
    final handles = [
      for (final slug in ['one', 'two'])
        SurfaceRefreshHandle(
            surface: SurfaceRef(surfaceType: 'general', slug: slug),
            triggers: {},
            canSwap: () => true,
            refresh: () async => remote++,
            localValidity: () => now.isBefore(boundary),
            localBoundary: () => boundary,
            invalidateLocal: () async => local++)
    ];
    for (final handle in handles) {
      registry.register(handle);
    }
    now = boundary;
    await tester.pump(const Duration(seconds: 1));
    expect(local, 2);
    expect(remote, 0);
    await registry.checkLocalValidity();
    expect(local, 2);
    for (final handle in handles) {
      registry.unregister(handle);
    }
  });

  testWidgets(
      'resume checks expired content and preserves assignment/interaction locks',
      (tester) async {
    var valid = true;
    var canSwap = false;
    var local = 0;
    var remote = 0;
    final registry = SurfaceRefreshRegistry();
    addTearDown(registry.debugReset);
    final handle = SurfaceRefreshHandle(
        surface: SurfaceRef(surfaceType: 'general', slug: 'locked'),
        triggers: {},
        canSwap: () => canSwap,
        refresh: () async => remote++,
        localValidity: () => valid,
        invalidateLocal: () async => local++);
    registry.register(handle);
    registry.onAppBackgrounded();
    valid = false;
    await tester.pump(const Duration(minutes: 1));
    expect(local, 0);
    await registry.onAppResumed();
    expect(local, 0);
    canSwap = true;
    await registry.checkLocalValidity();
    expect(local, 1);
    expect(remote, 0);
    registry.unregister(handle);
    await tester.pump(const Duration(seconds: 30));
    expect(local, 1);
  });
}

Future<void> _finishScreenFrames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

final class _RecordingDeliveryChannel implements DeliveryUpdateChannel {
  final watches = <({
    DeliveryPolicyScopeV1 scope,
    PlacementDeliveryWatchV1 watch,
    StreamController<DeliveryPolicyScopeV1> controller
  })>[];
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
      {PlacementDeliveryWatchV1? watch,
      Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) {
    final controller = StreamController<DeliveryPolicyScopeV1>();
    watches.add((scope: scope, watch: watch!, controller: controller));
    return controller.stream;
  }
}

DeliveryCacheValidityV1 _validity(
    {LocalCivilDateTimeV1? notBeforeLocal,
    LocalCivilDateTimeV1? expiresBeforeLocal}) {
  final original = (readPlacementDeliveryFixture().response.decisions.first
          as PlacementBatchAvailableV1)
      .publicDelivery
      .cacheValidity;
  return DeliveryCacheValidityV1(
      policySelections: original.policySelections,
      hostContractHash: original.hostContractHash,
      installedCapabilityHash: original.installedCapabilityHash,
      selectionIdentityDigest: original.selectionIdentityDigest,
      notBeforeLocal: notBeforeLocal,
      expiresBeforeLocal: expiresBeforeLocal);
}

/// The service's answer that the mount shows its fallback, with a watch.
PlacementBatchResolvedV1 _watchedFallback(PlacementBatchRequestV1 request) {
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
                    token: _watchToken)
              ]))
    ],
  );
}
