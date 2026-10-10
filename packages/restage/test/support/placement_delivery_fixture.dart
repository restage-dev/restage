import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// The shared wire corpus decoded through the actual public codecs.
({
  PlacementBatchRequestV1 request,
  PlacementBatchResolvedV1 response,
  TargetCoordinate target,
}) readPlacementDeliveryFixture(
    {String fileName = 'shared_blob_two_mounts_v1.json'}) {
  final wire = jsonDecode(File(
    '../restage_shared/test/fixtures/placements/$fileName',
  ).readAsStringSync()) as Map<String, dynamic>;
  final target = TargetCoordinate.fromJson(
    wire['response']['decisions'][0]['descriptor']['placement']['target']
        as Map<String, Object?>,
  );
  final request = PlacementBatchRequestV1.fromCanonicalBytes(
    CanonicalJsonCodec.encode(wire['request']),
  );
  return (
    request: request,
    response: PlacementBatchResponseV1.fromCanonicalBytes(
      CanonicalJsonCodec.encode(wire['response']),
      request: request,
      expectedTarget: target,
    ) as PlacementBatchResolvedV1,
    target: target,
  );
}

/// Correlates the real shared content to the mount declarations a host sends.
PlacementBatchResolvedV1 placementFixtureResponse(
    PlacementBatchRequestV1 request,
    {SurfacePayload? payload,
    SurfaceFitRequirementV1? requirement,
    DeliveryFamilySelectorV1? family,
    DeliveryPublicationReferenceV1? publicationOverride,
    PresentationAssignmentCarrierV2? assignment,
    String? routingSelectionReceipt,
    PlacementDeliveryWatchV1? Function(PublicPlacementDeliveryV1)? watch,
    Set<DeliveryPolicyScopeV1> additionalDependencies = const {},
    Map<String, Object?> cacheValidityOverrides = const {},
    String flowSurfaceType = 'onboarding'}) {
  final fixture = readPlacementDeliveryFixture();
  final base = fixture.response.decisions.first as PlacementBatchAvailableV1;
  final originalReference = base.artifactClosure.single;
  final selected = publicationOverride?.surface ??
      DeliverySurfaceReferenceV1(
          surfaceIdentity: base.publicDelivery.selectedSurface.surfaceIdentity,
          family: family ?? base.publicDelivery.selectedSurface.family);
  final bytes = payload == null
      ? fixture.response.artifacts.single.bytes
      : Uint8List.fromList(payload.canonicalBytes);
  final identity = payload == null
      ? fixture.response.artifacts.single.identity
      : ArtifactIdentityV1(
          payloadFormatVersion: surfaceArtifactPayloadFormatVersionFor(payload),
          contentHash: payload.contentHash);
  final target = selected.target;
  final publication = publicationOverride ??
      DeliveryPublicationReferenceV1(
          surface: selected,
          publishedVersion: originalReference.publication!.publishedVersion,
          payloadFormatVersion: identity.payloadFormatVersion,
          contentHash: CanonicalDigest(identity.contentHash.substring(7)));
  final reference = PlacementArtifactReferenceV1(
      publication: publication,
      descriptor: SurfaceArtifactDescriptorV1Codec.decode({
        ...originalReference.descriptor.toJson(),
        'payloadFormatVersion': identity.payloadFormatVersion,
        'contentHash': identity.contentHash,
        'version': publication.publishedVersion,
        if (payload != null) 'payloadKind': payload.payloadKind,
        if (payload is FlowSurfacePayload)
          'surfaceSlug': payload.flowDocument.flow,
        if (payload is FlowSurfacePayload) 'surfaceType': flowSurfaceType,
      }));
  return PlacementBatchResolvedV1(
      request: request,
      expectedTarget: target,
      decisions: [
        for (final mount in request.mounts)
          () {
            final descriptor = PlacementMountDescriptorV1(
                placement: PlacementIdentityV1(target: target, key: mount.key),
                hostContractHash: mount.hostContractHash,
                defaultSurface: mount.defaultSurface == null
                    ? null
                    : DeliverySurfaceReferenceV1(
                        surfaceIdentity: PublishedSurfaceIdentityV1(
                            target: target,
                            surfaceId: base.descriptor.defaultSurface!
                                .surfaceIdentity.surfaceId),
                        family: mount.defaultSurface!.family));
            final json =
                jsonDecode(jsonEncode(base.publicDelivery.path.toJson()))
                    as Map<String, Object?>;
            final steps = json['steps']! as List;
            ((steps.first as Map)['scope'] as Map)['root'] = {
              'kind': 'placement',
              'placement': descriptor.placement.toJson()
            };
            ((steps.last as Map)['scope'] as Map)['family'] =
                selected.family.toJson();
            ((steps.last as Map)['scope'] as Map)['root'] = {
              'kind': 'surface',
              'surface': selected.surfaceIdentity.toJson()
            };
            json['actualPublication'] = publication.toJson();
            final path = PublicDeliveryDecisionPathV1.fromJson(json);
            final validity = DeliveryCacheValidityV1.fromJson({
              ...base.publicDelivery.cacheValidity.toJson(),
              'hostContractHash': mount.hostContractHash,
              'installedCapabilityHash':
                  request.buildContract.installedCapabilityHash,
              'selectionIdentityDigest': path.selectionIdentityDigest.hex,
              ...cacheValidityOverrides,
            });
            final delivery = PublicPlacementDeliveryV1(
                mount: descriptor,
                path: path,
                selectedSurface: selected,
                actualPublication: publication,
                cacheValidity: validity,
                fitRequirement:
                    requirement ?? base.publicDelivery.fitRequirement,
                dependencyClosure: {
                  ...path.steps.map((step) => step.scope),
                  ...additionalDependencies
                },
                assignment: assignment,
                routingSelectionReceipt: routingSelectionReceipt);
            return PlacementBatchAvailableV1(descriptor, delivery, [reference],
                watch: watch?.call(delivery));
          }()
      ],
      artifacts: [
        PlacementBatchArtifactV1(identity: identity, bytes: bytes)
      ]);
}
