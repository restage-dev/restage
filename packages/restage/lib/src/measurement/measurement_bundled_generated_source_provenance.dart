import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/bundled_flow_loader.dart';
import '../resolver/resolved_paywall_payload.dart';
import 'bundled_measurement_publication_binding_read_port.dart';

/// Builds one exact resolved flow payload carrier from the loader's actual
/// artifact choices.
///
/// The loader records a selected path for every screen so legacy-path fallback
/// cannot be re-created by convention here. Missing or extra artifacts are a
/// programmer/error-path signal and must never produce an approximate carrier.
@internal
MeasurementBundledGeneratedArtifactClosureCarrier
    bundledMeasurementGeneratedArtifactClosureForFlowArtifacts(
  BundledFlowArtifacts artifacts,
) {
  if (artifacts.flowJsonPath.isEmpty) {
    throw StateError(
      'A bundled flow artifact carrier requires the exact loaded flow path.',
    );
  }
  final artifactIds = artifacts.document.screenArtifacts.keys.toList()..sort();
  final carriers = <MeasurementBundledGeneratedArtifact>[
    MeasurementBundledGeneratedArtifact.fromBytes(
      logicalPath: artifacts.flowJsonPath,
      role: SurfacePublicationArtifactRole.flowDocument,
      id: null,
      bytes: artifacts.documentBytes,
    ),
  ];
  for (final artifactId in artifactIds) {
    final bytes = artifacts.screenBlobs[artifactId];
    final path = artifacts.screenAssetPaths[artifactId];
    if (bytes == null || path == null) {
      throw StateError(
        'A bundled flow artifact carrier requires every exact loaded screen '
        'path and byte payload.',
      );
    }
    carriers.add(
      MeasurementBundledGeneratedArtifact.fromBytes(
        logicalPath: path,
        role: SurfacePublicationArtifactRole.screenBlob,
        id: artifactId,
        bytes: bytes,
      ),
    );
  }
  if (artifacts.screenBlobs.length != artifactIds.length ||
      artifacts.screenAssetPaths.length != artifactIds.length) {
    throw StateError(
      'A bundled flow artifact carrier has an incomplete exact screen '
      'closure.',
    );
  }
  return MeasurementBundledGeneratedArtifactClosureCarrier(
    artifacts: carriers,
  );
}

/// Resolves compiler- or resolver-owned bundled provenance to one exact final
/// Surface publication locator.
///
/// This deliberately has no hosted binding-reference input or fallback path.
/// A value carrying no one exact bundled carrier, both carrier kinds, or an
/// unresolved/ambiguous/stale carrier produces null so business rendering can
/// continue with Measurement disabled.
@internal
Future<MeasurementBundledGeneratedPublicationLocatorV1?>
    resolveBundledExactGeneratedPublicationLocatorFor(
  Object resolvedOrDescriptor, {
  required BundledMeasurementPublicationBindingReadPort bindingReadPort,
}) async {
  final carrierOwner = switch (resolvedOrDescriptor) {
    BlobPaywallPayload(:final variant) => variant,
    FlowPaywallPayload(:final flow) => flow,
    _ => resolvedOrDescriptor,
  };
  final sourceCarrier = measurementBundledGeneratedSourceCarrierFor(
    carrierOwner,
  );
  final artifactClosure = measurementBundledGeneratedArtifactClosureCarrierFor(
    carrierOwner,
  );
  if ((sourceCarrier == null) == (artifactClosure == null)) {
    return null;
  }
  if (sourceCarrier != null) {
    return bindingReadPort.resolveExactGeneratedSourceCarrier(sourceCarrier);
  }
  return bindingReadPort.resolveExactGeneratedArtifactClosureCarrier(
    artifactClosure!,
  );
}
