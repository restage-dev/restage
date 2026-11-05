import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_cli/src/api/component_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_asset_declaration.dart';
import 'package:restage_cli/src/measurement/bundled_measurement_target_profile_packager.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart'
    show readProjectPackageName;
import 'package:restage_shared/restage_shared.dart'
    show
        BlobSurfacePayload,
        FlowSurfacePayload,
        SurfaceEditorState,
        SurfacePayload;
import 'package:restage_shared/rfw_formats.dart' show decodeLibraryBlob;

/// Where a push publishes the shared components its designs deliver.
typedef ComponentTarget = ({ComponentApi api, int organizationId});

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
  required ComponentTarget components,
  bool declareAssets = false,
  Future<Uint8List?> Function(SurfacePayload payload)? editorStateOf,
  Uint8List? pushImage,
  Map<String, Object?>? previewContext,
}) async {
  final measurementUpload = assembled.measurementUpload;
  final publication = assembled.entry.publication;
  final pins = await publishDeliveredComponents(
    components: components,
    project: project,
    packageRoot: packageRoot,
    surface: '${publication.surface.wireName}/${publication.slug}',
  );
  final editorState =
      await (editorStateOf ??
          (payload) => pushedEditorState(
            payload: payload,
            packageRoot: packageRoot,
            pins: pins,
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

/// The editor state a push stores with a surface: the app's generated widget
/// catalog when it uses the app's own widgets, so the editor can show and
/// edit them, and the pins of the shared components it delivers. Null when it
/// has neither.
///
/// [pins] are the component pins [publishDeliveredComponents] returned, by
/// declaration; each lands on the screen that declares it.
Future<Uint8List?> pushedEditorState({
  required SurfacePayload payload,
  required Directory packageRoot,
  Map<String, Map<String, Object?>> pins = const {},
  RenderBundleCatalogProducer widgetCatalog = readGeneratedWidgetCatalog,
}) async {
  Map<String, Object?>? catalog;
  if (payload.requiredLibraries.isNotEmpty) {
    try {
      final generated = await widgetCatalog(
        projectRoot: packageRoot,
        generate: false,
      );
      if (generated.registersWidgets) {
        catalog = jsonDecode(generated.json) as Map<String, Object?>;
      }
    } on GeneratedCatalogException {
      // No catalog: the state carries only pins.
    }
  }
  Map<String, Object?> pinsIn(Uint8List blob) {
    final declared = {
      for (final widget in decodeLibraryBlob(blob).widgets) widget.name,
    };
    return {
      for (final entry in pins.entries)
        if (declared.contains(entry.key)) entry.key: entry.value,
    };
  }

  Map<String, Object?> meta = const {};
  Map<String, Map<String, Object?>>? screens;
  switch (payload) {
    case BlobSurfacePayload(:final blob):
      if (pinsIn(blob) case final found when found.isNotEmpty) {
        meta = {'components': found};
      }
    case FlowSurfacePayload(:final screenBlobs):
      screens = {
        for (final entry in screenBlobs.entries)
          if (pinsIn(entry.value) case final found when found.isNotEmpty)
            entry.key: {'components': found},
      };
      if (screens.isEmpty) screens = null;
  }
  if (catalog == null && meta.isEmpty && screens == null) return null;
  return SurfaceEditorState(
    meta: meta,
    catalog: catalog,
    screens: screens,
  ).encode();
}

/// Publishes the shared components the build hands off for [surface]
/// (`<surface>/<slug>`) and returns their pins by declaration.
///
/// A new component gets version 1; an unchanged definition keeps the newest
/// version; a changed one appends a version, as a code push does for a
/// surface. Pinned surfaces are untouched.
Future<Map<String, Map<String, Object?>>> publishDeliveredComponents({
  required ComponentTarget components,
  required String project,
  required Directory packageRoot,
  required String surface,
}) async {
  final delivered = _deliveredComponents(packageRoot, surface);
  if (delivered.isEmpty) return const {};
  final api = components.api;
  final organizationId = components.organizationId;
  Future<Map<String, ComponentSummary>> existing() async => {
    for (final component in await api.list(
      organizationId: organizationId,
      project: project,
    ))
      component.name: component,
  };
  final byName = await existing();
  final pins = <String, Map<String, Object?>>{};
  for (final component in delivered) {
    final published = switch (byName[component.name]) {
      null => await api.create(
        organizationId: organizationId,
        project: project,
        name: component.name,
        payload: component.payload,
      ),
      final current => await _appended(
        api,
        organizationId,
        current,
        component,
        reload: () async => (await existing())[component.name] ?? current,
      ),
    };
    pins[component.declaration] = {
      'id': published.id,
      'version': published.latestVersion,
      'fingerprint': component.fingerprint,
      if (component.parts.isNotEmpty) 'parts': component.parts,
    };
  }
  return pins;
}

// [current] when its newest version already holds [component]'s payload,
// otherwise the component after appending it; a race re-reads once.
Future<ComponentSummary> _appended(
  ComponentApi api,
  int organizationId,
  ComponentSummary current,
  _DeliveredComponent component, {
  required Future<ComponentSummary> Function() reload,
}) async {
  var latest = current;
  for (var attempt = 0; ; attempt += 1) {
    final row = await api.loadVersion(
      organizationId: organizationId,
      componentId: latest.id,
      version: latest.latestVersion,
    );
    if (_sameBytes(row.payload, component.payload)) return latest;
    try {
      return await api.pushVersion(
        organizationId: organizationId,
        componentId: latest.id,
        expectedLatestVersion: latest.latestVersion,
        payload: component.payload,
      );
    } on ComponentVersionConflict {
      if (attempt > 0) rethrow;
      latest = await reload();
    }
  }
}

typedef _DeliveredComponent = ({
  String name,
  String declaration,
  Uint8List payload,
  String fingerprint,
  List<String> parts,
});

List<_DeliveredComponent> _deliveredComponents(
  Directory packageRoot,
  String surface,
) {
  final file = File(
    generatedCompilerHandoffPath(
      packageRoot,
      readProjectPackageName(packageRoot),
    ),
  );
  if (!file.existsSync()) return const [];
  final handoff = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final bySurface = handoff['surfaceComponents'] as Map<String, Object?>?;
  return [
    for (final raw in (bySurface?[surface] as List<Object?>?) ?? const [])
      if (raw case final Map<String, Object?> json)
        (
          name: json['name']! as String,
          declaration: json['declaration']! as String,
          payload: base64Decode(json['payload']! as String),
          fingerprint: json['fingerprint']! as String,
          parts: [...(json['parts']! as List<Object?>).cast<String>()],
        ),
  ];
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
