import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/placement_mount_attribution.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/restage_rpc_client/placement_delivery_adapter.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
  });
  tearDown(Restage.debugReset);

  test('shared blob bytes retain separate placement leaves and cache evidence',
      () {
    final fixture = readPlacementDeliveryFixture();
    final deliveries = fixture.response.decisions
        .cast<PlacementBatchAvailableV1>()
        .map((row) => row.publicDelivery)
        .toList();
    final bytes = fixture.response.artifacts.single.bytes;
    final leaves = [
      for (final delivery in deliveries)
        attachResolvedPlacementDelivery(
            ResolvedVariant(
                bytes: bytes,
                paywallId: 'welcome',
                surfaceVersion: delivery.actualPublication.contentHash.hex,
                paywallPublishedVersion:
                    delivery.actualPublication.publishedVersion),
            delivery)
    ];
    expect(resolvedPlacementDeliveryFor(BlobPaywallPayload(leaves.first)),
        deliveries.first);
    expect(resolvedPlacementDeliveryFor(leaves.last), deliveries.last);
    expect(() => attachResolvedPlacementDelivery(leaves.first, deliveries.last),
        throwsStateError);
    final cached = leaves.first.copyWith(cacheHit: true);
    final original = MountAttributionSnapshotV1.fromResolved(
        resolved: leaves.first,
        mount: fixture.request.mounts.first,
        mountInstanceNonce: 'a' * 43);
    final replay = MountAttributionSnapshotV1.fromResolved(
        resolved: BlobPaywallPayload(cached),
        mount: fixture.request.mounts.first,
        mountInstanceNonce: 'b' * 43);
    expect(replay.attribution.placementKey, original.attribution.placementKey);
    expect(replay.attribution.actualPublication,
        deliveries.first.actualPublication);
    expect(replay.attribution.actualSurface!.family,
        DeliveryFamilySelectorV1.screenContract(contractVersion: 7));
    expect(replay.attribution.actualSurface!.family,
        isNot(original.defaultSurface!.family));
    expect(replay.attribution.resolutionKind, MountResolutionKindV1.cached);
    expect(original.attribution.resolutionKind, MountResolutionKindV1.hosted);
    expect(replay.attribution.resolvedSelectionDigest,
        deliveries.first.publicProjectionDigest);
    expect(original.attribution.mountNonceDigest.hex,
        crypto.sha256.convert(utf8.encode('a' * 43)).toString());
    expect(replay.attribution.mountNonceDigest,
        isNot(original.attribution.mountNonceDigest));
    expect(
        resolvedPlacementDeliveryFor(
            leaves.first.copyWith(surfaceVersion: 'changed')),
        isNull);
  });

  test('actual flow asset cache copies opaque selection and original lease',
      () async {
    final fixture = readPlacementDeliveryFixture(
        fileName: 'retained_flow_dependencies_v1.json');
    final artifacts = await assemblePlacementDeliveryArtifacts(fixture.response,
        publicationGuard: () => true);
    final decision =
        fixture.response.decisions.first as PlacementBatchAvailableV1;
    final document =
        artifacts!.publications[decision.publicDelivery.actualPublication]!;
    final payload = document.payload as FlowSurfacePayload;
    final flow = OnboardingFlowRef<Map<String, Object?>>(
        id: payload.flowDocument.flow,
        version: payload.flowDocument.version,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: (data) => data);
    final bundle = _FlowBundle({
      'assets/onboarding/flows/${flow.id}.flow.json': Uint8List.fromList(
          FlowDocumentCodec.encodeCanonicalJson(payload.flowDocument)),
      for (final entry in payload.flowDocument.screenArtifacts.entries)
        'assets/onboarding/screens/${entry.value.path}':
            payload.screenBlobs[entry.key]!,
    });
    final resolver = AssetFlowResolver(bundle: bundle);
    final resolved = await resolver.resolve(flow);
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 1)).replaceAll('=', ''));
    final base = decision.publicDelivery;
    final delivery = PublicPlacementDeliveryV1(
        mount: base.mount,
        path: base.path,
        selectedSurface: base.selectedSurface,
        actualPublication: base.actualPublication,
        cacheValidity: base.cacheValidity,
        fitRequirement: base.fitRequirement,
        dependencyClosure: base.dependencyClosure,
        routingSelectionReceipt: 'opaque.original.receipt',
        assignment: assignment);
    final lease = SurfaceAssignmentKeyProvider.captureKeylessLease();
    attachResolvedPlacementDelivery(resolved, delivery,
        selectedDocument: document);
    attachMeasurementPublicationBindingReference(resolved, null,
        registrationFingerprint: 'c' * 64,
        routingSelectionReceipt: delivery.routingSelectionReceipt);
    attachSurfaceAssignmentLease(resolved, lease);

    final cached = await resolver.resolve(flow);

    expect(cached.cacheHit, isTrue);
    expect(cached, isNot(same(resolved)));
    expect(
        resolvedPlacementDeliveryFor(
            FlowPaywallPayload(flow: cached, paywallId: 'first_root')),
        delivery);
    expect(routingSelectionReceiptFor(cached), 'opaque.original.receipt');
    expect(measurementRegistrationFingerprintFor(cached), 'c' * 64);
    expect(surfaceAssignmentLeaseFor(cached), same(lease));
    expect(surfaceResolutionSourceFor(cached),
        SurfaceResolutionSource.holdLastGood);
  });

  test('delayed Measurement opens with the nonce reserved by its mount',
      () async {
    Restage.configure(analyticsEnabled: true, measurementEnabled: true);
    final fixture = readPlacementDeliveryFixture();
    final publication = AdmittedBundledPublicationFixture.build(
        artifact: fixture.response.artifacts.single.bytes);
    final delayed = _DelayedReadPort(publication);
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
        publicationContext: publication.publicationContextRef,
        hostedBindingReadPortLookup: () => delayed);
    addTearDown(harness.close);
    final delivery = _withBinding(
        (fixture.response.decisions.first as PlacementBatchAvailableV1)
            .publicDelivery,
        publication);
    final leaf = attachResolvedPlacementDelivery(
        ResolvedVariant(
            bytes: fixture.response.artifacts.single.bytes,
            paywallId: 'welcome',
            surfaceVersion: 'selected'),
        delivery);
    attachMeasurementPublicationBindingReference(
        leaf, publication.binding.reference,
        routingSelectionReceipt: delivery.routingSelectionReceipt);
    final snapshot = captureMountAttribution(fixture.request.mounts.first,
        resolved: BlobPaywallPayload(leaf))!;
    final session = MeasurementHostSessionController.openDeferred(
        BlobPaywallPayload(leaf),
        mountAttribution: snapshot);
    expect(session.debugState, MeasurementHostSessionDebugState.pending);
    expect(harness.worker.registrations, isEmpty);
    delayed.release.complete();
    for (var i = 0; i < 50 && harness.worker.registrations.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    final registration = harness.worker.registrations.single;
    expect(registration.captureSessionNonce, snapshot.mountInstanceNonce);
    expect(
        MountSelectionAttributionV1.fromCanonicalBytes(
            registration.attributionCanonicalBytes!),
        snapshot.attribution);
    expect(
        registration.routingSelectionReceipt, delivery.routingSelectionReceipt);
    expect(registration.presentationContextCanonicalBytes, isNull);
    await session.teardown();
  });

  test('local fallback has no fabricated publication or Measurement binding',
      () {
    final fixture = readPlacementDeliveryFixture();
    final snapshot = captureMountAttribution(fixture.request.mounts.first)!;
    expect(snapshot.attribution.placementKey, fixture.request.mounts.first.key);
    expect(snapshot.attribution.evidenceStrength,
        MountEvidenceStrengthV1.reportedLocal);
    expect(snapshot.attribution.resolutionKind,
        MountResolutionKindV1.compiledFallback);
    expect(snapshot.attribution.actualPublication, isNull);
    expect(snapshot.attribution.actualSurface, isNull);
    expect(snapshot.attribution.resolvedTarget, isNull);
    expect(snapshot.attribution.measurementBinding, isNull);
    expect(snapshot.routingSelectionReceipt, isNull);
  });
}

PublicPlacementDeliveryV1 _withBinding(
    PublicPlacementDeliveryV1 base, AdmittedBundledPublicationFixture fixture) {
  final selected = DeliverySurfaceReferenceV1(
      surfaceIdentity: fixture.binding.publishedSurfaceRevision.surfaceIdentity,
      family: base.selectedSurface.family);
  final publication = DeliveryPublicationReferenceV1(
      surface: selected,
      publishedVersion: 2,
      payloadFormatVersion: base.actualPublication.payloadFormatVersion,
      contentHash: base.actualPublication.contentHash,
      publicationBindingRef: fixture.binding.reference);
  final mount = PlacementMountDescriptorV1(
      placement: PlacementIdentityV1(
          target: fixture.target, key: base.mount.placement.key),
      hostContractHash: base.mount.hostContractHash,
      defaultSurface: DeliverySurfaceReferenceV1(
          surfaceIdentity: PublishedSurfaceIdentityV1(
              target: fixture.target,
              surfaceId: base.mount.defaultSurface!.surfaceIdentity.surfaceId),
          family: base.mount.defaultSurface!.family));
  final pathJson =
      jsonDecode(jsonEncode(base.path.toJson())) as Map<String, Object?>;
  final steps = pathJson['steps'] as List;
  (steps.first as Map)['scope'] = DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.placement(mount.placement),
          family: DeliveryFamilySelectorV1.none())
      .toJson();
  (steps.last as Map)['scope'] = DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.surface(selected.surfaceIdentity),
          family: selected.family)
      .toJson();
  pathJson['actualPublication'] = publication.toJson();
  final path = PublicDeliveryDecisionPathV1.fromJson(pathJson);
  return PublicPlacementDeliveryV1(
      mount: mount,
      path: path,
      selectedSurface: selected,
      actualPublication: publication,
      fitRequirement: base.fitRequirement,
      cacheValidity: DeliveryCacheValidityV1.fromJson({
        ...base.cacheValidity.toJson(),
        'selectionIdentityDigest': path.selectionIdentityDigest.hex
      }),
      dependencyClosure: path.steps.map((step) => step.scope).toSet(),
      routingSelectionReceipt: 'opaque.exact.receipt');
}

final class _FlowBundle extends CachingAssetBundle {
  _FlowBundle(this.assets);
  final Map<String, Uint8List> assets;
  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing $key');
    return ByteData.sublistView(bytes);
  }
}

final class _DelayedReadPort implements MeasurementPublicationBindingReadPort {
  _DelayedReadPort(this.fixture);
  final AdmittedBundledPublicationFixture fixture;
  final release = Completer<void>();
  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
      MeasurementPublicationBindingReferenceV1 reference) async {
    await release.future;
    return MeasurementPublicationBindingReadAccepted(
        reference: fixture.binding.reference,
        binding: fixture.binding,
        registeredPublicationAttestation:
            fixture.entry.registeredPublicationAttestation);
  }
}
