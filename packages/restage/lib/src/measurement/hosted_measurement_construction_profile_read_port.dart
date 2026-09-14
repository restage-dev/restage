import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'hosted_measurement_publication_binding_read_port.dart';
import 'measurement_host_construction_owner.dart';
import 'measurement_worker_delivery.dart';

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
    if (!const {'restage.collection-budget.v2', 'restage.collection-budget.v3'}
            .contains(decision.collectionBudgetRevisionId.value) ||
        !const {'restage.manifest-privacy.v1', 'restage.manifest-privacy.v2'}
            .contains(decision.privacyPolicyRevisionId.value) ||
        decision.privacyClassificationRevisionId.value !=
            'restage.privacy-classification.v1') {
      return const MeasurementHostConstructionProfileReadRejected(
        MeasurementHostConstructionPolicyStatus.unsupported,
      );
    }
    return MeasurementHostConstructionProfileReadAccepted(
      MeasurementHostConstructionProfile(
        publicationContext: publicationContext,
        sdkRuntimeSessionAdmitted: decision.privacyPolicyRevisionId.value ==
                'restage.manifest-privacy.v2' &&
            decision.collectionBudgetRevisionId.value ==
                'restage.collection-budget.v3',
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
