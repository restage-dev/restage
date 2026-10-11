// Test-only transport and cache hooks keep hosted delivery deterministic.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

List<PlacementBatchRequestV1> configureHostedPaywall({
  required GeneratedPlacementDefinition definition,
  required String fixture,
  int version = 1,
  bool unavailable = false,
  ({String fixture, int version}) Function()? publication,
}) {
  Restage.debugReset();
  PackageInfo.setMockInitialValues(
    appName: 'Example',
    packageName: 'example',
    version: '1.0',
    buildNumber: '1',
    buildSignature: '',
  );
  sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  addTearDown(() => sharedSurfaceArtifactStore = null);
  Restage.configureWithInstalledCatalog(
    apiKey: 'rs_pk_test',
    baseUrl: 'https://example.com',
    surfaces: [definition],
    analyticsEnabled: false,
    measurementEnabled: false,
    deliveryReceiptsEnabled: false,
  );
  debugResetInstallObservations();
  debugResetAppBuildOrdinal();
  debugSetOsVersion(19);
  SurfaceMeteringKeyProvider.clear();
  final requests = <PlacementBatchRequestV1>[];
  final client = RestageRpcClient(
    apiKey: 'rs_pk_test',
    baseUrl: 'https://example.com',
    httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/sdk/v1/placements/resolve');
      final batch = PlacementBatchRequestV1.fromCanonicalBytes(
        request.bodyBytes,
      );
      requests.add(batch);
      final selected =
          publication?.call() ?? (fixture: fixture, version: version);
      final response = _response(
        batch,
        definition: definition,
        fixture: selected.fixture,
        version: selected.version,
        unavailable: unavailable,
      );
      return http.Response.bytes(response.canonicalBytes, 200);
    }),
  );
  Restage.debugRestageRpcClient = client;
  addTearDown(client.close);
  return requests;
}

PlacementBatchResolvedV1 _response(
  PlacementBatchRequestV1 request, {
  required GeneratedPlacementDefinition definition,
  required String fixture,
  required int version,
  required bool unavailable,
}) {
  final blob = File('test/fixtures/$fixture.rfw').readAsBytesSync();
  final sidecar = CapabilitySidecar.fromJson(
    jsonDecode(
          File('test/fixtures/$fixture.capability.json').readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  expect(CapabilitySidecar.hashBlob(blob), sidecar.blobSha256);
  final payload = BlobSurfacePayload(
    minClient: sidecar.manifest.builtInFloor,
    requiredLibraries: sidecar.manifest.requiredLibraries,
    blob: blob,
  );
  final target = TargetCoordinate(
    organizationId: OrganizationId(1),
    appId: ApplicationId(2),
    environmentTargetId: EnvironmentTargetId(3),
    namedEnvironmentId: NamedEnvironmentId(4),
    runtimePlane: RuntimePlane.live,
  );
  final surface = DeliverySurfaceReferenceV1(
    surfaceIdentity: PublishedSurfaceIdentityV1(
      target: target,
      surfaceId: SurfaceId('surface.v1.example-paywall'),
    ),
    family: const DeliveryFamilySelectorV1.general(),
  );
  final publication = DeliveryPublicationReferenceV1(
    surface: surface,
    publishedVersion: version,
    payloadFormatVersion: 1,
    contentHash: CanonicalDigest(payload.contentHash.substring(7)),
  );
  final reference = PlacementArtifactReferenceV1(
    publication: publication,
    descriptor: SurfaceArtifactDescriptor(
      payloadFormatVersion: 1,
      payloadKind: payload.payloadKind,
      surfaceType: Surface.paywall,
      surfaceSlug: definition.defaultSurfaceLocator.slug,
      version: version,
      publishedAtMicros: 1,
      contentHash: payload.contentHash,
      artifactUrl: 'https://example.com/paywall',
      artifactPass: 'test-artifact',
    ),
  );
  return PlacementBatchResolvedV1(
    request: request,
    expectedTarget: target,
    decisions: [
      for (final mount in request.mounts)
        () {
          final descriptor = PlacementMountDescriptorV1(
            placement: PlacementIdentityV1(target: target, key: mount.key),
            hostContractHash: mount.hostContractHash,
            defaultSurface: surface,
          );
          if (unavailable) {
            return PlacementBatchUseFallbackV1(
              descriptor,
              PlacementBatchRefusalReasonV1.unavailable,
              const [],
            );
          }
          final path = PublicDeliveryDecisionPathV1(
            steps: [
              PublicDeliveryDecisionStepV1(
                scope: DeliveryPolicyScopeV1(
                  root: DeliveryRootIdentityV1.placement(descriptor.placement),
                  family: const DeliveryFamilySelectorV1.none(),
                ),
                source: PublicDeliverySelectionSourceV1.ownerDefault,
              ),
              PublicDeliveryDecisionStepV1(
                scope: DeliveryPolicyScopeV1(
                  root: DeliveryRootIdentityV1.surface(surface.surfaceIdentity),
                  family: surface.family,
                ),
                source: PublicDeliverySelectionSourceV1.ownerDefault,
              ),
            ],
            actualPublication: publication,
          );
          final delivery = PublicPlacementDeliveryV1(
            mount: descriptor,
            path: path,
            selectedSurface: surface,
            actualPublication: publication,
            cacheValidity: DeliveryCacheValidityV1(
              policySelections: const [],
              hostContractHash: mount.hostContractHash,
              installedCapabilityHash:
                  request.buildContract.installedCapabilityHash,
              selectionIdentityDigest: path.selectionIdentityDigest,
            ),
            fitRequirement: SurfaceFitRequirementV1(
              hosting: SurfaceHostingRequirementV1(
                contentKind: SurfaceContentKindV1.single,
                allowedPresentations: {SurfacePresentationV1.inline},
              ),
              requiredContext: definition.hostContract.providedContext,
              emittedEvents: definition.hostContract.handledEvents,
              capabilities: sidecar.manifest,
              requiredVocabulary: WidgetVocabulary(
                widgetNames: {
                  'restage.core:Column',
                  'restage.core:Padding',
                  'restage.core:SizedBox',
                  'restage.core:Text',
                  'restage.material:FilledButton',
                  'restage.material:TextButton',
                },
              ),
            ),
            dependencyClosure: path.steps.map((step) => step.scope).toSet(),
          );
          return PlacementBatchAvailableV1(descriptor, delivery, [reference]);
        }(),
    ],
    artifacts: [
      if (!unavailable)
        PlacementBatchArtifactV1(
          identity: ArtifactIdentityV1(
            payloadFormatVersion: 1,
            contentHash: payload.contentHash,
          ),
          bytes: Uint8List.fromList(payload.canonicalBytes),
        ),
    ],
  );
}
