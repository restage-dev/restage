import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as m
    show RuntimePlane;
import 'package:restage_shared/restage_shared.dart';

const operationId = '4d1f28ea-0c97-4d87-8fd7-15164749e440';
const sampleId = '86505cf7-c04b-45d0-83c8-529ec1b8db1c';

TargetCoordinate sampleTarget({
  bool live = false,
  int appId = 11,
  int? targetId,
  int? namedId,
}) => TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(appId),
  environmentTargetId: EnvironmentTargetId(targetId ?? (live ? 44 : 42)),
  namedEnvironmentId: NamedEnvironmentId(namedId ?? (live ? 440 : 420)),
  runtimePlane: live ? m.RuntimePlane.live : m.RuntimePlane.sandbox,
);

Uint8List samplePng([int red = 0]) {
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> data) {
    final body = [...ascii.encode(name), ...data];
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
      }
    }
    final length = ByteData(4)..setUint32(0, data.length);
    final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    out
      ..add(length.buffer.asUint8List())
      ..add(body)
      ..add(checksum.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert([0, red, 0, 0, 255]));
  chunk('IEND', const []);
  return out.takeBytes();
}

PlacementScreenCaptureV1 sampleCapture(Uint8List png) {
  final host = SurfaceHostContractV1(
    hosting: const SurfaceHostingV1(
      contentKind: SurfaceContentKindV1.single,
      presentation: SurfacePresentationV1.inline,
    ),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []),
  );
  final capability = InstalledCapability(
    builtInCatalogVersion: 4,
    installedLibraries: const [],
  );
  final key = PlacementKeyV1.named(slug: 'welcome');
  final build = PlacementBuildContractV1(
    platform: 'ios',
    mounts: [
      PlacementMountRequestV1(key: key, hostContractHash: host.contentHash),
    ],
    contractsByHash: {host.contentHash: host},
    installedCapability: capability,
    installedCapabilityHash: capability.contentHash,
  );
  return PlacementScreenCaptureV1(
    buildContract: build,
    appBuildContractHash: build.appBuildContractHash,
    screenLabel: 'Welcome',
    captureScope: PlacementScreenCaptureScopeV1.explicitBoundary,
    logicalViewport: PlacementLogicalSizeV1.fromLogical(width: 1, height: 1),
    rasterScale: PlacementRasterScaleV1.fromRequestedScale(1),
    pngWidth: 1,
    pngHeight: 1,
    pngByteLength: png.length,
    pngSha256: validatePlacementScreenSamplePng(png).contentHash,
    mounts: [
      PlacementSampleMountV1(
        key: key,
        hostContractHash: host.contentHash,
        rect: PlacementLogicalRectV1.fromLogical(
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
        occurrenceIndex: 0,
      ),
    ],
  );
}

PlacementSampleDraftV1 sampleDraft(TargetCoordinate target, Uint8List png) {
  final capture = sampleCapture(png);
  final manifest = capture.bindTarget(target);
  return PlacementSampleDraftV1(
    manifest: manifest,
    buildContract: capture.buildContract,
    reviewedDigest: manifest.reviewDigest,
  );
}

PlacementSampleUploadTicketV1 sampleTicket(PlacementSampleDraftV1 draft) =>
    PlacementSampleUploadTicketV1(
      ticketId: 'dc0bdfb5-d815-4e7b-8d9f-76647d28c68b',
      manifestDigest: draft.manifestDigest,
      imageSha256: draft.manifest.pngSha256,
      expiresAtMicros: DateTime.utc(2027).microsecondsSinceEpoch,
      limits: PlacementSampleUploadLimitsV1(),
    );

DeliveryPolicyScopeV1 placementScope({
  PlacementKeyV1? key,
  bool live = false,
}) => DeliveryPolicyScopeV1(
  root: DeliveryRootIdentityV1.placement(
    PlacementIdentityV1(
      target: sampleTarget(live: live),
      key: key ?? PlacementKeyV1.named(slug: 'welcome'),
    ),
  ),
  family: const DeliveryFamilySelectorV1.none(),
);

DeliveryPolicyScopeV1 surfaceScope({bool live = false}) =>
    DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.surface(
        PublishedSurfaceIdentityV1(
          target: sampleTarget(live: live),
          surfaceId: SurfaceId('welcome'),
        ),
      ),
      family: DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
    );

DeliveryPolicyPlanV1 policyPlan(
  DeliveryPolicyScopeV1 scope,
) => DeliveryPolicyPlanV1(
  scope: scope,
  snapshots: [
    DeliveryPolicySnapshotInputV1(
      effectiveFromLocal: null,
      documentCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
    ),
    DeliveryPolicySnapshotInputV1(
      effectiveFromLocal: LocalCivilDateTimeV1.parse('2027-01-04T09:30:00'),
      documentCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
    ),
  ],
);

DeliveryPolicyRevisionRefV1 policyRevision(
  DeliveryPolicyScopeV1 scope,
  int ordinal,
) => DeliveryPolicyRevisionRefV1(
  scope: scope,
  ordinal: ordinal,
  revisionId: 'revision-$ordinal',
  canonicalPolicyDigest: CanonicalDigest('a' * 64),
);

DeliveryPolicyReadV1 policyRead(DeliveryPolicyScopeV1 scope, int ordinal) =>
    DeliveryPolicyReadV1(
      scope: scope,
      headId: 9,
      revision: policyRevision(scope, ordinal),
      policyCanonicalBytes: CanonicalJsonCodec.encode({'rules': <Object>[]}),
      publishedAtMicros: 100,
    );

DeliveryPolicyReviewV1 policyReview(
  DeliveryPolicyScopeV1 scope, {
  int? expectedHeadOrdinal,
  String reason = 'Restore complete plan',
  DeliveryMeasurementImpactReviewV1? impact,
}) => DeliveryPolicyReviewV1(
  scope: scope,
  expectedHeadOrdinal: expectedHeadOrdinal,
  candidatePlan: policyPlan(scope),
  candidateRevision: policyRevision(scope, (expectedHeadOrdinal ?? 0) + 1),
  reviewedAuthorityDigest: CanonicalDigest('b' * 64),
  measurementImpact:
      impact ??
      DeliveryMeasurementImpactReviewV1(
        scope: scope,
        operation: 'policyPublish',
        dependencyDigest: CanonicalDigest('c' * 64),
      ),
  reason: reason,
  reviewedAtMicros: 120,
);

DeliveryMeasurementImpactReviewV1 warningImpact(DeliveryPolicyScopeV1 scope) =>
    DeliveryMeasurementImpactReviewV1(
      scope: scope,
      operation: 'policyPublish',
      dependencyDigest: CanonicalDigest('d' * 64),
      affectedSources: [
        DeliveryMeasurementSourceImpactV1(
          experimentReference: ExperimentLiveReadReferenceV1.fromJson({
            'kind': 'experimentLiveReadReference',
            'target': scope.target.toJson(),
            'experimentId': 'welcome-experiment',
            'activationOrdinal': 2,
            'receiptDigest': 'e' * 64,
          }),
          experimentName: 'Welcome experiment',
          metricName: 'Completed welcome',
          metricBindingReference:
              ExperimentExactMetricBindingReferenceV1.fromJson({
                'canonicalDigest': 'f' * 64,
                'metricBindingId': 'completed-welcome',
                'metricBindingRevisionId': 'completed-welcome-2',
                'semanticDigest': 'a' * 64,
              }, path: 'metricBindingReference'),
          affectedPublications: const [],
          warningCode: 'metricSourceUnavailable',
        ),
      ],
    );

PlacementManagementCutV1 directoryCut() => PlacementManagementCutV1(
  asOfMicros: 200,
  publicationGeneration: 7,
  publishedAsOfMicros: 190,
  validUntilMicros: 300,
  sourceDigest: 'd' * 64,
);

String text(CallToolResult result) =>
    (result.content.single as TextContent).text;
Map<String, Object?> targetArguments({bool live = false}) => {
  'projectSlug': 'demo',
  'appSlug': 'mobile',
  'organizationId': 7,
  'environmentSlug': live ? 'production' : 'staging',
  'runtimePlane': live ? 'live' : 'sandbox',
};
