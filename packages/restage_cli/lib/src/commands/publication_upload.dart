import 'dart:io';

import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_asset_declaration.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_packager.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';

/// The backend publication committed, but its local bundled profile did not.
final class MeasurementBundledProfileFinalizeException implements Exception {
  /// Creates the closed local-finalization failure.
  const MeasurementBundledProfileFinalizeException();
}

/// Submit one assembled publication through the operation selected by its
/// optional Measurement candidate.
///
/// The candidate is target-neutral. Target, revision, binding, policy, and
/// activation authority remain with the publication API and service.
Future<SurfacePublicationUploadResult> publishAssembledSurfacePublication({
  required SurfacePublicationApi api,
  required AssembledSurfacePublication assembled,
  required Directory packageRoot,
  required String project,
  required String app,
  required String environment,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  int? organizationId,
}) async {
  final measurementUpload = assembled.measurementUpload;
  if (measurementUpload == null) {
    return api.publish(
      project: project,
      app: app,
      environment: environment,
      request: assembled.request,
      environmentTargetId: environmentTargetId,
      runtimePlane: runtimePlane,
      organizationId: organizationId,
    );
  }

  final measurementResult = await api.publishMeasurementBound(
    project: project,
    app: app,
    environment: environment,
    upload: measurementUpload,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    organizationId: organizationId,
  );
  if (assembled.hasBundledMeasurementSourceClosure) {
    try {
      await MeasurementBundledTargetProfilePackager().packageFinalizedEntry(
        packageRoot: packageRoot,
        entry: measurementResult.bundledPublicationEntry,
        selectedBundleFiles: assembled.selectedBundleFiles,
      );
      await ensureMeasurementBundledTargetProfileAssetDeclaration(
        packageRoot: packageRoot,
      );
    } on MeasurementBundledTargetProfilePackagingException {
      throw const MeasurementBundledProfileFinalizeException();
    } on MeasurementBundledTargetProfileAssetDeclarationException {
      throw const MeasurementBundledProfileFinalizeException();
    } on ArgumentError {
      throw const MeasurementBundledProfileFinalizeException();
    }
  }
  return measurementResult.publicationResult;
}
