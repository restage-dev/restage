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

/// What a publication wrote into the app for its bundled Measurement profile.
final class MeasurementProfileWrite {
  const MeasurementProfileWrite({
    required this.declared,
    required this.pubspecUpdated,
  });

  /// Whether pubspec.yaml ships the profile after this publication.
  final bool declared;

  /// Whether this publication added the profile to pubspec.yaml.
  final bool pubspecUpdated;
}

/// Submit one assembled publication through the operation selected by its
/// optional Measurement candidate. With [declareAssets] the profile it writes
/// is added to pubspec.yaml; otherwise pubspec.yaml is left as it is.
///
/// The candidate is target-neutral. Target, revision, binding, policy, and
/// active-pointer authority remain with the publication API and service.
Future<
  ({SurfacePublicationUploadResult result, MeasurementProfileWrite? profile})
>
publishAssembledSurfacePublication({
  required SurfacePublicationApi api,
  required AssembledSurfacePublication assembled,
  required Directory packageRoot,
  required String project,
  required String app,
  required String environment,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  int? organizationId,
  bool declareAssets = false,
}) async {
  final measurementUpload = assembled.measurementUpload;
  if (measurementUpload == null) {
    final result = await api.publish(
      project: project,
      app: app,
      environment: environment,
      request: assembled.request,
      environmentTargetId: environmentTargetId,
      runtimePlane: runtimePlane,
      organizationId: organizationId,
    );
    return (result: result, profile: null);
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
  MeasurementProfileWrite? profile;
  if (assembled.hasBundledMeasurementSourceClosure) {
    try {
      await MeasurementBundledTargetProfilePackager().packageFinalizedEntry(
        packageRoot: packageRoot,
        entry: measurementResult.bundledPublicationEntry,
        selectedBundleFiles: assembled.selectedBundleFiles,
      );
      final updated =
          declareAssets &&
          await ensureMeasurementBundledTargetProfileAssetDeclaration(
            packageRoot: packageRoot,
          );
      profile = MeasurementProfileWrite(
        declared:
            updated ||
            await isMeasurementBundledTargetProfileAssetDeclared(
              packageRoot: packageRoot,
            ),
        pubspecUpdated: updated,
      );
    } on MeasurementBundledTargetProfilePackagingException {
      throw const MeasurementBundledProfileFinalizeException();
    } on MeasurementBundledTargetProfileAssetDeclarationException {
      throw const MeasurementBundledProfileFinalizeException();
    } on ArgumentError {
      throw const MeasurementBundledProfileFinalizeException();
    }
  }
  return (result: measurementResult.publicationResult, profile: profile);
}
