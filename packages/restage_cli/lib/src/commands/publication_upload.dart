import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_asset_declaration.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_packager.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_shared/restage_shared.dart'
    show SurfaceEditorState, SurfacePayload;

/// The backend publication committed, but its local bundled profile did not.
final class MeasurementBundledProfileFinalizeException implements Exception {
  /// Creates the local-finalization failure with a safe [reason].
  const MeasurementBundledProfileFinalizeException(this.reason);

  /// Why the profile was not written.
  final String reason;
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
  Future<Uint8List?> Function(SurfacePayload payload)? editorStateOf,
  Uint8List? pushImage,
  Map<String, Object?>? previewContext,
}) async {
  final measurementUpload = assembled.measurementUpload;
  final editorState =
      await (editorStateOf ??
          (payload) => pushedEditorState(
            payload: payload,
            packageRoot: packageRoot,
          ))(assembled.payload);
  if (measurementUpload == null) {
    final result = await api.publish(
      project: project,
      app: app,
      environment: environment,
      request: assembled.request,
      environmentTargetId: environmentTargetId,
      runtimePlane: runtimePlane,
      organizationId: organizationId,
      editorState: editorState,
      pushImage: pushImage,
      previewContext: previewContext,
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
    editorState: editorState,
    pushImage: pushImage,
    previewContext: previewContext,
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
    } on MeasurementBundledTargetProfilePackagingException catch (error) {
      throw MeasurementBundledProfileFinalizeException(error.message);
    } on MeasurementBundledTargetProfileAssetDeclarationException catch (
      error
    ) {
      throw MeasurementBundledProfileFinalizeException(error.message);
    } on ArgumentError catch (error) {
      throw MeasurementBundledProfileFinalizeException('${error.message}');
    }
  }
  return (result: measurementResult.publicationResult, profile: profile);
}

/// The editor state a push stores with a surface that uses the app's own
/// widgets, on any of its screens: the app's generated widget catalog, so the
/// editor can show and edit them. Null for any other surface, or when no
/// catalog was generated.
Future<Uint8List?> pushedEditorState({
  required SurfacePayload payload,
  required Directory packageRoot,
  RenderBundleCatalogProducer widgetCatalog = readGeneratedWidgetCatalog,
}) async {
  if (payload.requiredLibraries.isEmpty) return null;
  final GeneratedWidgetCatalog catalog;
  try {
    catalog = await widgetCatalog(projectRoot: packageRoot, generate: false);
  } on GeneratedCatalogException {
    return null;
  }
  if (!catalog.registersWidgets) return null;
  return SurfaceEditorState(
    catalog: jsonDecode(catalog.json) as Map<String, Object?>,
  ).encode();
}
