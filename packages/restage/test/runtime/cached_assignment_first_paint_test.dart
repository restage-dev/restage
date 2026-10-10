import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Locale;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_store_key.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';
import '../flow/flow_test_support.dart' show resolvedFlow, screenBlob;
import '../support/canonical_assignment_fixture.dart';
import '../support/hosted_artifact_delivery.dart';
import '../surface_screen/surface_screen_test_support.dart';

final _handle = 'ic1.${'a' * 64}';
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('cached-paint');
  });
  tearDown(Restage.debugReset);
  for (final flowShaped in [false, true]) {
    testWidgets(
        'cached ${flowShaped ? 'nonbaseline flow' : 'blob'} paywall loses expired credential before deadline promotion',
        (tester) async {
      final credentials = await _Credentials.create();
      var rejectedArmPaints = 0;
      Restage.registerWidgetLibrary(
          const WidgetLibrary.custom('acme.cachepaint'),
          capabilityVersion: 1,
          widgets: [
            RestageWidgetFactory(
                name: 'ArmProbe',
                builder: (_, __) => _PaintCounter(() => rejectedArmPaints++))
          ]);
      const armLibraries = [
        LibraryRequirement(namespace: 'acme.cachepaint', minVersion: 1)
      ];
      final delivery = HostedArtifactFixture();
      final pendingFresh = Completer<http.Response>();
      var fetches = 0;
      final bundledScreen = screenBlob('Bundled flow', 'finish');
      final hostedScreen = rfwSourceBlob(
          'import restage.core; import acme.cachepaint; '
          'widget OnboardingScreen = Column(children: [Text(text: "Assigned cache"), ArmProbe()]);');
      final document = SurfaceDocument(
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro_upgrade',
        version: 7,
        minClient: 3,
        requiredLibraries: armLibraries,
        payload: flowShaped
            ? FlowSurfacePayload(
                flowDocument: _flow(hostedScreen),
                screenBlobs: {'welcome': hostedScreen},
                requiredLibraries: armLibraries)
            : BlobSurfacePayload(
                minClient: 3,
                blob: _paywallBlob('Assigned cache'),
                requiredLibraries: armLibraries),
        publishedAt: DateTime.utc(2026),
      );
      final real = RestageVariantResolver(
        apiKey: 'rs_pk_cached',
        environment: RestageEnvironment.sandbox,
        baseUrl: 'https://edge.example.test',
        assetFallback:
            flowShaped ? _FlowFallback(_flow(bundledScreen)) : _NoFallback(),
        httpClient: delivery.client((request) async {
          fetches++;
          if (fetches > 1) return pendingFresh.future;
          return http.Response(
              jsonEncode({
                ...delivery.describe(document),
                'assignment': canonicalAssignmentFixture().toJson()
              }),
              200);
        }),
      );
      final key = real.storeKeyFor('pro_upgrade');
      expect(await real.fresh(key, sendAssignmentKey: true), isNotNull);
      final observed = _ObservedPaywall(real, key);
      final events = <RestageEvent>[];
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'pro_upgrade',
        resolver: observed,
        fallbackBuilder: (_) => const Text('Compiled paywall'),
        onEvent: events.add,
      )));
      await tester.pump();
      expect(observed.local, isNotNull);
      final capturedKey = observed.local!.assignmentLease?.assignmentKey;
      expect(observed.local!.assignmentLease!.isCurrent, isTrue);
      expect(fetches, 2);
      credentials.now += Duration.microsecondsPerHour;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
      final local = observed.local;
      final localLeaf = switch (local) {
        BlobPaywallPayload(:final variant) => variant,
        FlowPaywallPayload(:final flow) => flow,
        null => null,
      };
      final fallbackAssignment = localLeaf == null
          ? null
          : measurementExperimentAssignmentFor(localLeaf);
      final actual = (
        assigned: find.text('Assigned cache').evaluate().length,
        floor: find
            .text(flowShaped ? 'Bundled flow' : 'Compiled paywall')
            .evaluate()
            .length,
        views: events.whereType<PaywallViewed>().length,
        handle: credentials.store.currentHandle
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pendingFresh.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      expect(rejectedArmPaints, 0);
      expect(fallbackAssignment, isNull);
      expect(actual.assigned, 0);
      expect(capturedKey, _handle);
      expect(actual, (assigned: 0, floor: 1, views: 1, handle: null));
    });
  }
  for (final mode in [
    'expired credential',
    'reset identity',
    'refused credential',
    'expiry during descendant build',
    'expiry after first paint',
    'expiry with stalled local reread',
    'reset with stalled local reread',
    'recovery with remaining original budget'
  ]) {
    testWidgets('cached typed screen preserves authority across $mode',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(onSurfaceResolution: reports.add);
      SurfaceCanonicalCarrierProvider.enableAssignmentRetention('cached-paint');
      final batch = SurfaceDeliveryReceiptBatch.instance
        ..enabled = true
        ..deviceSource = () async => (platform: 'android', appBuild: 42);
      final credentials = await _Credentials.create();
      final stalled = mode.endsWith('stalled local reread');
      final remainingBudget = mode == 'recovery with remaining original budget';
      final originalSource = remainingBudget
          ? SurfaceResolutionSource.fresh
          : SurfaceResolutionSource.holdLastGood;
      final reread = Completer<ResolvedSurfaceScreen?>();
      var paints = 0;
      var expiredDuringBuild = false;
      final expireDuringBuild = mode == 'expiry during descendant build';
      Restage.registerWidgetLibrary(
          const WidgetLibrary.custom('acme.cachepaint'),
          capabilityVersion: 1,
          widgets: [
            RestageWidgetFactory(
                name: 'ArmProbe',
                builder: (_, __) {
                  if (expireDuringBuild && !expiredDuringBuild) {
                    expiredDuringBuild = true;
                    credentials.now += Duration.microsecondsPerHour;
                  }
                  return _PaintCounter(() => paints++);
                })
          ]);
      final fixture = stringScreenFixture(
          text: 'Bundled screen',
          capabilities: CapabilityManifest(
              builtInFloor: 1,
              requiredLibraries: const [
                LibraryRequirement(namespace: 'acme.cachepaint', minVersion: 1)
              ]));
      final hostedBlob = expireDuringBuild
          ? rfwSourceBlob(
              'import acme.cachepaint; widget OnboardingScreen = ArmProbe();')
          : rfwScreenBlob(text: 'Assigned cache', event: 'tap');

      final pendingFresh = Completer<http.Response>();
      var fetches = 0;
      final client = RestageRpcClient(
        baseUrl: 'https://edge.example.test',
        apiKey: 'rs_pk_cached',
        httpClient: fixture.hostedDelivery.client((request) async {
          fetches++;
          if (fetches > 1) return pendingFresh.future;
          return http.Response(
              jsonEncode({
                ...SurfaceScreenDeliveryDescriptorV1Codec.encode(
                    fixture.delivery(hostedBlob: hostedBlob)),
                'assignment': canonicalAssignmentFixture().toJson(),
              }),
              200);
        }),
      );
      final real = RestageSurfaceScreenResolver(
        apiKey: 'rs_pk_cached',
        environment: RestageEnvironment.sandbox,
        baseUrl: 'https://edge.example.test',
        assetFallback: FixedBundledScreenResolver(fixture.bundled()),
        rpcClientProvider: () => client,
      );
      final key = real.storeKeyFor(fixture.ref);
      expect(await real.fresh(key, sendAssignmentKey: true), isNotNull);
      final observed = _ObservedScreen(
        real,
        key,
        reread: stalled || remainingBudget ? reread.future : null,
        afterFresh: remainingBudget
            ? () => credentials.now += Duration.microsecondsPerHour
            : null,
      );
      await tester.pumpWidget(MaterialApp(
          home: RestageScreen<String>(
        screen: fixture.ref,
        resolver: observed,
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, __) => const Text('Compiled screen')),
      )));
      await tester.pump();
      expect(observed.local, isNotNull);
      expect(measurementExperimentAssignmentFor(observed.local!), isNotNull);
      final capturedLease = surfaceAssignmentLeaseFor(observed.local!);
      final capturedCurrent = capturedLease?.isCurrent;
      expect(fetches, 2);
      if (mode == 'refused credential') {
        await credentials.store.refuse((await credentials.store.capture())!);
      } else if (mode == 'reset identity' ||
          mode == 'reset with stalled local reread') {
        credentials.identity++;
      } else if (mode == 'expired credential' ||
          mode == 'expiry with stalled local reread') {
        credentials.now += Duration.microsecondsPerHour;
      }
      if (stalled) {
        observed.raced.freshRefused(
            Restage.storeKeyFor(fixture.ref, resolver: observed),
            SurfaceDeliveryReceiptReason.throttled);
      }
      int? readsBeforeRecovery;
      int? floorBeforeRecovery;
      if (remainingBudget) {
        await tester.pump(const Duration(milliseconds: 100));
        pendingFresh.complete(http.Response(
            jsonEncode({
              ...SurfaceScreenDeliveryDescriptorV1Codec.encode(
                  fixture.delivery(hostedBlob: hostedBlob)),
              'assignment': canonicalAssignmentFixture().toJson(),
            }),
            200));
        await tester.pump();
        await tester.pump();
        readsBeforeRecovery = observed.localReads;
        floorBeforeRecovery = find.text('Compiled screen').evaluate().length;
        await tester.pump(const Duration(milliseconds: 100));
        reread.complete(fixture.bundled());
        await tester.pump();
        await tester.pump();
      } else {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.pump();
      }
      final floorAtDeadline = find.text('Compiled screen').evaluate().length;
      final secondReadStarted = observed.localReads == 2;
      SurfaceDeliveryReceiptHandle? refusalProbe;
      if (stalled) {
        // The next bundled presentation observes the host-floor refusal.
        refusalProbe = batch.open(
            surfaceType: Surface.general,
            surfaceSlug: fixture.ref.slug,
            publishedVersion: 1,
            source: SurfaceResolutionSource.bundled,
            reason: SurfaceDeliveryReceiptReason.offline,
            routeId: 'refusal-probe');
        reread.complete(fixture.bundled());
        await tester.pump();
        await tester.pump();
      }
      if (mode == 'expiry after first paint') {
        credentials.now += Duration.microsecondsPerHour;
        await tester.pump();
      }
      final actual = (
        assigned: find.text('Assigned cache').evaluate().length,
        bundled: find.text('Bundled screen').evaluate().length,
        paints: paints,
        expiredDuringBuild: expiredDuringBuild,
        compiled: find.text('Compiled screen').evaluate().length,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      if (!pendingFresh.isCompleted)
        pendingFresh.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      final receipts = (await batch.drain()).counts.keys.toList();
      expect(actual.paints, 0);
      if (stalled) expect(floorAtDeadline, 1);
      expect(actual.assigned, mode == 'expiry after first paint' ? 1 : 0);
      expect(actual.bundled,
          mode == 'expiry after first paint' || stalled ? 0 : 1);
      expect(capturedCurrent, isTrue);
      expect(actual.expiredDuringBuild, expireDuringBuild);
      if (remainingBudget) {
        expect(readsBeforeRecovery, 2);
        expect(floorBeforeRecovery, 0);
      }
      if (stalled) {
        expect(secondReadStarted, isTrue);
        expect(floorAtDeadline, 1);
        expect(actual.compiled, 1,
            reason: 'late local content cannot swap into the host floor');
        expect(
            receipts.where(
                (r) => r.outcome == SurfaceDeliveryReceiptOutcome.painted),
            isEmpty);
        expect(receipts.singleWhere((r) => r.routeId == 'refusal-probe').reason,
            SurfaceDeliveryReceiptReason.throttled);
        expect(refusalProbe!.isClosed, isTrue);
        expect(reports.map((r) => r.source),
            [SurfaceResolutionSource.holdLastGood]);
      } else {
        expect(measurementExperimentAssignmentFor(observed.local!),
            mode == 'expiry after first paint' ? isNotNull : isNull);
        expect(
            receipts
                .where(
                    (r) => r.outcome == SurfaceDeliveryReceiptOutcome.painted)
                .map((r) => r.source),
            [
              mode == 'expiry after first paint'
                  ? SurfaceResolutionSource.holdLastGood
                  : SurfaceResolutionSource.bundled
            ]);
        expect(
            reports.map((r) => r.source),
            mode == 'expiry after first paint'
                ? [SurfaceResolutionSource.holdLastGood]
                : [originalSource, SurfaceResolutionSource.bundled]);
        if (mode != 'expiry after first paint') {
          expect(
              receipts.singleWhere((r) => r.source == originalSource).outcome,
              SurfaceDeliveryReceiptOutcome.notPainted);
        }
      }
    });
  }
}

final class _Credentials {
  var now = DateTime.now().microsecondsSinceEpoch;
  var identity = 0;
  late final store = SurfaceAssignmentCredentialStore(
    namespace: 'cached-paint',
    actor: () async => 'actor-$identity',
    identityGeneration: () => identity,
    onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
    nowMicros: () => now,
  );
  static Future<_Credentials> create() async {
    final value = _Credentials();
    final attempt = (await value.store.capture())!;
    expect(
        await value.store.confirm(
            attempt: attempt,
            localRequestStartMicros: value.now,
            credentialHandle: _handle,
            expiresAtMicros: value.now + Duration.microsecondsPerMinute,
            serverNowMicros: value.now),
        isTrue);
    SurfaceAssignmentKeyProvider.install(
      key: value.store.resolve,
      localKey: value.store.resolveLocal,
      identityGeneration: () => value.store.generation,
      registration: value.store.capture,
      confirmedKey: () => value.store.currentHandle,
      confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
          value.store.confirm(
              attempt: attempt,
              localRequestStartMicros: start,
              credentialHandle: handle,
              expiresAtMicros: expiry,
              serverNowMicros: serverNow),
      refuseRegistration: value.store.refuse,
    );
    return value;
  }
}

final class _ObservedPaywall implements VariantResolver {
  _ObservedPaywall(this.real, this.key) {
    registerRacedResolver(
        this,
        RacedSurfaceDelegate<ResolvedPaywallPayload>(
          bestLocal: (_) async => local = await real.bestLocal(key),
          fresh: (_, {required sendAssignmentKey, keyDeadline}) => real.fresh(
              key,
              sendAssignmentKey: sendAssignmentKey,
              keyDeadline: keyDeadline),
        ));
  }
  final RestageVariantResolver real;
  final SurfaceStoreKey key;
  ResolvedPaywallPayload? local;
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      real.resolve(id);
}

final class _ObservedScreen implements SurfaceScreenResolver {
  _ObservedScreen(this.real, this.key,
      {Future<ResolvedSurfaceScreen?>? reread, VoidCallback? afterFresh}) {
    raced = RacedSurfaceDelegate<ResolvedSurfaceScreen>(
      surfaceFor: (_) => Surface.general,
      bestLocal: (_) async {
        localReads++;
        if (localReads > 1 && reread != null) return local = await reread;
        return local = await real.bestLocal(key);
      },
      fresh: (_, {required sendAssignmentKey, keyDeadline}) async {
        final resolved = await real.fresh(key,
            sendAssignmentKey: sendAssignmentKey, keyDeadline: keyDeadline);
        afterFresh?.call();
        return resolved;
      },
    );
    registerRacedResolver(this, raced);
  }
  late final RacedSurfaceDelegate<ResolvedSurfaceScreen> raced;
  var localReads = 0;
  final RestageSurfaceScreenResolver real;
  final SurfaceStoreKey key;
  ResolvedSurfaceScreen? local;
  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) =>
      real.resolve(screen);
}

final class _NoFallback implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      throw RestagePaywallError(code: 'missing', message: 'No bundled blob');
}

final class _FlowFallback
    implements VariantResolver, FlowCapableVariantResolver {
  _FlowFallback(FlowDocument document)
      : payload = FlowPaywallPayload(
            flow: resolvedFlow(
                document: document,
                screenBlobs: {'welcome': screenBlob('Bundled flow', 'finish')}),
            paywallId: 'pro_upgrade');
  final FlowPaywallPayload payload;
  @override
  Future<ResolvedPaywallPayload> resolvePayload(String id,
          {String? placementId, Locale? locale}) async =>
      payload;
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      throw RestagePaywallError(code: 'flow', message: 'Flow only');
}

FlowDocument _flow(Uint8List screen) => FlowDocument(
      flow: 'pro_upgrade',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'welcome',
      actions: const {},
      screenArtifacts: {
        'welcome': ScreenArtifact(
            path: 'welcome.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: 3,
            contentHash: FlowContentHash.compute(screen))
      },
      states: const {
        'welcome': ScreenFlowState(
            screen: 'welcome', on: {'finish': FlowTransition.goto('done')}),
        'done': EndFlowState(result: {})
      },
    );
Uint8List _paywallBlob(String text) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(
        'import restage.core; import acme.cachepaint; widget Paywall = Column(children: [Text(text: "$text"), ArmProbe()]);')));

final class _PaintCounter extends LeafRenderObjectWidget {
  const _PaintCounter(this.onPaint);
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) => _CounterBox(onPaint);
}

final class _CounterBox extends RenderBox {
  _CounterBox(this.onPaint);
  final VoidCallback onPaint;
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(48));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
  }
}
