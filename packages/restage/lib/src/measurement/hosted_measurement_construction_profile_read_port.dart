import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'hosted_measurement_publication_binding_read_port.dart';
import 'measurement_host_construction_owner.dart';
import 'measurement_worker_delivery.dart';

/// Whether a decision's policy revisions admit collection at all.
bool measurementCollectionAdmittedByPolicy({
  required String privacyPolicyRevisionId,
  required String collectionBudgetRevisionId,
  required String classificationRevisionId,
}) =>
    policyRevisionAtOrAbove(
      collectionBudgetRevisionId,
      collectionBudgetFamily,
      collectionBudgetPolicyFloor,
    ) &&
    policyRevisionAtOrAbove(
      privacyPolicyRevisionId,
      manifestPrivacyPolicyFamily,
      collectionPrivacyPolicyFloor,
    ) &&
    classificationRevisionId == privacyClassificationRevisionId;

/// Whether those revisions also admit the presentation metadata.
bool presentationMetadataAdmittedByPolicy({
  required String privacyPolicyRevisionId,
  required String collectionBudgetRevisionId,
}) =>
    policyRevisionAtOrAbove(
      privacyPolicyRevisionId,
      manifestPrivacyPolicyFamily,
      presentationMetadataPrivacyPolicyFloor,
    ) &&
    policyRevisionAtOrAbove(
      collectionBudgetRevisionId,
      collectionBudgetFamily,
      presentationMetadataCollectionBudgetFloor,
    );

/// Whether those revisions also admit the SDK runtime session.
bool sdkRuntimeSessionAdmittedByPolicy({
  required String privacyPolicyRevisionId,
  required String collectionBudgetRevisionId,
}) =>
    policyRevisionAtOrAbove(
      privacyPolicyRevisionId,
      manifestPrivacyPolicyFamily,
      sdkSessionPrivacyPolicyFloor,
    ) &&
    policyRevisionAtOrAbove(
      collectionBudgetRevisionId,
      collectionBudgetFamily,
      sdkSessionCollectionBudgetFloor,
    );

/// Joins an authenticated collection decision to the exact mounted publication.
final class HostedMeasurementConstructionProfileReadPort
    implements MeasurementHostConstructionProfileReadPort {
  HostedMeasurementConstructionProfileReadPort({
    required this.client,
    required this.baseUrl,
    required this.apiKey,
  }) : _fingerprint = sha256
            .convert(utf8.encode(jsonEncode([
              baseUrl.replaceFirst(RegExp(r'/+$'), ''),
              apiKey,
              kMeasurementSchemaVersion,
            ])))
            .toString();

  final RestageRpcClient? Function() client;
  final String baseUrl;
  final String apiKey;
  final String _fingerprint;

  @override
  Future<MeasurementHostConstructionProfileReadResult> readExact(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) async {
    final rpc = client();
    if (rpc == null) return _missing;
    final read = await HostedMeasurementPublicationBindingReadPort(client: rpc)
        .readExact(publicationContext.bindingReference);
    if (read is! MeasurementPublicationBindingReadAccepted) return _missing;
    final binding = read.binding;
    final revision = binding.publishedSurfaceRevision;
    if (revision.surfaceIdentity != publicationContext.surfaceIdentity ||
        revision.revisionId != publicationContext.surfaceRevisionId ||
        binding.exactArtifactGraph.canonicalDigest !=
            publicationContext.artifactGraphHash ||
        binding.completeMeasurementManifest.canonicalDigest !=
            publicationContext.measurementManifestHash) {
      return _stale;
    }
    final decision = await rpc.readMeasurementCollectionDecisionExact(
      publicationContext.bindingReference,
    );
    if (decision == null || client() != rpc) return _missing;
    if (!decision.matchesBinding(binding)) return _stale;
    if (!measurementCollectionAdmittedByPolicy(
      privacyPolicyRevisionId: decision.privacyPolicyRevisionId.value,
      collectionBudgetRevisionId: decision.collectionBudgetRevisionId.value,
      classificationRevisionId: decision.privacyClassificationRevisionId.value,
    )) {
      return const MeasurementHostConstructionProfileReadRejected(
        MeasurementHostConstructionPolicyStatus.unsupported,
      );
    }
    return MeasurementHostConstructionProfileReadAccepted(
      MeasurementHostConstructionProfile(
        publicationContext: publicationContext,
        presentationMetadataAdmitted: presentationMetadataAdmittedByPolicy(
          privacyPolicyRevisionId: decision.privacyPolicyRevisionId.value,
          collectionBudgetRevisionId: decision.collectionBudgetRevisionId.value,
        ),
        sdkRuntimeSessionAdmitted: sdkRuntimeSessionAdmittedByPolicy(
          privacyPolicyRevisionId: decision.privacyPolicyRevisionId.value,
          collectionBudgetRevisionId: decision.collectionBudgetRevisionId.value,
        ),
        endpoint:
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/sdk/v1/measurement',
        analyticsEnabled: true,
        policyStatus: MeasurementHostConstructionPolicyStatus.supported,
        measurementClassAdmitted: decision.admittedCollectionClass ==
            MeasurementCollectionClass.tier2Coalesced,
        remainingSessionBudget: decision.sessionAdmissionLimit,
        deliveryAdapterAvailable: measurementWorkerDeliverySupported,
        configurationFingerprint: _fingerprint,
        headers: [
          MeasurementWorkerOwnedDeliveryHeader(
              name: 'Authorization', value: 'Bearer $apiKey')
        ],
      ),
    );
  }

  static const _missing = MeasurementHostConstructionProfileReadRejected(
    MeasurementHostConstructionPolicyStatus.missing,
  );
  static const _stale = MeasurementHostConstructionProfileReadRejected(
    MeasurementHostConstructionPolicyStatus.stale,
  );
}
