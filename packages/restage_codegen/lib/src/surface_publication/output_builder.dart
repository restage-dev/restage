// The single static materialization boundary for portable Restage output:
// one deterministic `.rsbundle` per authored Dart library, its optional
// `.restage.md` inspection report, and the package-wide physical output
// index plus publication manifest. A normal builder with buildExtensions
// resolved once from RestageOutputPlacementPlan at construction — no
// post-process builder, no warm-graph reliance, no second generation
// command.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/placement_registry.dart';
import 'package:restage_shared/restage_shared.dart';

/// Materializes deterministic per-library bundles, optional inspection
/// reports, and the package-wide output index/publication manifest from the
/// fixed compiler handoff, per the resolved [RestageOutputPlacementPlan].
final class RestageOutputsBuilder implements Builder {
  /// Creates the builder, resolving and validating placement options once.
  RestageOutputsBuilder(BuilderOptions options)
      : plan = RestageOutputPlacementPlan.fromBuilderOptions(options);

  /// The resolved placement authority for this builder invocation.
  final RestageOutputPlacementPlan plan;

  @override
  Map<String, List<String>> get buildExtensions => plan.portableBuildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    await registerRestagePlacementSignature(
      buildStep,
      plan,
      builderKey: 'restage_codegen:outputs',
    );

    final bundle = await readRestageCompilerHandoff(buildStep);
    if (bundle == null) return;

    if (buildStep.inputId.path == r'$package$') {
      await _buildPackageWide(buildStep, bundle);
    } else {
      await _buildForLibrary(buildStep, bundle);
    }
  }

  Future<void> _buildForLibrary(
    BuildStep buildStep,
    RestageSurfacePublicationBundle bundle,
  ) async {
    final libraryPath = buildStep.inputId.path;
    final entries = _entriesFor(bundle, onlyLibrary: libraryPath);
    if (entries.isEmpty) return;

    final placement = plan.forLibrary(libraryPath);
    final restageBundle = RestageBundle(
      packageName: buildStep.inputId.package,
      authoredLibraryPath: libraryPath,
      entries: entries,
    );
    await buildStep.writeAsBytes(
      AssetId(buildStep.inputId.package, placement.bundlePath),
      RestageBundleCodec.encode(restageBundle),
    );

    final reportPath = placement.inspectionReportPath;
    if (reportPath != null) {
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, reportPath),
        _renderInspectionReport(restageBundle),
      );
    }
  }

  Future<void> _buildPackageWide(
    BuildStep buildStep,
    RestageSurfacePublicationBundle bundle,
  ) async {
    final manifest = bundle.manifest;
    if (manifest == null) return;
    final measurementAsset = AssetId(
      buildStep.inputId.package,
      kRestageMeasurementCompilerOutputPath,
    );
    RestageMeasurementCompilerOutputV1? measurementOutput;
    if (await buildStep.canRead(measurementAsset)) {
      try {
        measurementOutput =
            RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
          await buildStep.readAsBytes(measurementAsset),
        );
      } on Object catch (error) {
        log.severe(
          'The package Measurement compiler output is invalid; package-wide '
          'Restage outputs were not materialized: $error',
        );
        return;
      }
      if (!measurementOutput.valid) {
        log.severe(
          'Measurement compilation failed: '
          '${measurementOutput.errors.join('; ')}',
        );
        return;
      }
    }
    final manifestJson = SurfacePublicationManifestV1Codec.encodeCanonicalJson(
      manifest,
    );
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, plan.publicationManifestPath),
      manifestJson,
    );

    // The index is the publication resolver's physical locator and must be
    // an exact bijection with the manifest's artifact set. Text-role entries
    // stay in the bundle (they still pass through _entriesFor below, which
    // still fails loud on one this build cannot attribute at all) but are
    // never manifest artifacts, so they never appear here — their physical
    // location is discoverable through the bundle's own META-INF records,
    // via the manifest artifact the index does locate for that library.
    final entries = _entriesFor(bundle)
        .where((entry) => entry.role != RestageBundleEntryRole.rfwText);
    final indexEntries = <Map<String, Object?>>[];
    for (final entry in entries) {
      final libraryPath = bundle.artifactLibraryPaths[entry.logicalPath];
      if (libraryPath == null) {
        throw StateError(
          'Bundle entry ${entry.logicalPath} has no authored-library '
          'attribution.',
        );
      }
      indexEntries.add(<String, Object?>{
        'path': entry.logicalPath,
        'bundle': plan.forLibrary(libraryPath).bundlePath,
        'entry': entry.logicalPath,
        'sha256': entry.sha256,
      });
    }
    indexEntries.sort(
      (left, right) => compareGeneratedOutputPaths(
        left['path']! as String,
        right['path']! as String,
      ),
    );

    final index = <String, Object?>{
      'schemaVersion': 1,
      'package': buildStep.inputId.package,
      'physicalRoot': plan.physicalRoot,
      'publicationManifestPath': plan.publicationManifestPath,
      'generationFingerprint': _sha256Hex(utf8.encode(manifestJson)),
      'entries': indexEntries,
    };
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, plan.outputIndexPath),
      const JsonEncoder.withIndent('  ').convert(index),
    );
    if (measurementOutput != null) {
      await buildStep.writeAsBytes(
        AssetId(buildStep.inputId.package, plan.measurementOutputIndexPath),
        measurementOutput.outputIndexBytes(buildStep.inputId.package),
      );
    }
  }

  /// Every manifest-closure entry plus the library's canonical `.rfwtxt`
  /// inspection texts, optionally filtered to one authored library, sorted
  /// by logical path.
  ///
  /// A bundle's entry set is not limited to the strict delivery-manifest
  /// closure: `.rfwtxt` is never a manifest artifact (it is never part of
  /// the OTA wire), but the frozen packaging contract's own worked example
  /// and its `.restage.md` report contract both include it, so it belongs
  /// in the bundle alongside the artifacts that are. The package-wide index
  /// is a stricter view than this: it excludes text-role entries entirely
  /// (see [_buildPackageWide]), since it must stay an exact bijection with
  /// the manifest's own artifact set.
  List<RestageBundleEntry> _entriesFor(
    RestageSurfacePublicationBundle bundle, {
    String? onlyLibrary,
  }) {
    final rolesByPath = <String, SurfacePublicationArtifactRole>{};
    final publications = bundle.manifest?.publications ??
        const <SurfacePublicationManifestEntry>[];
    for (final publication in publications) {
      for (final artifact in publication.artifacts) {
        rolesByPath[artifact.path] = artifact.role;
      }
    }

    final merged = <String, List<int>>{
      ...bundle.artifacts,
      ...bundle.borrowedArtifacts,
    };
    final rfwTextPaths =
        bundle.ownedOutputs.keys.where((path) => path.endsWith('.rfwtxt'));

    // A bundle's owned outputs never overlap its manifest artifacts, so every
    // logical path collected below is distinct and the one sort at the end is
    // a total order over them — collection order cannot survive into the
    // result, and neither group needs pre-sorting.
    final entries = <RestageBundleEntry>[];
    for (final path in merged.keys) {
      if (onlyLibrary != null &&
          bundle.artifactLibraryPaths[path] != onlyLibrary) {
        continue;
      }
      final role = rolesByPath[path];
      if (role == null) {
        throw StateError('Manifest artifact $path has no declared role.');
      }
      entries.add(
        RestageBundleEntry(
          logicalPath: path,
          role: RestageBundleEntryRole.fromManifestRole(role),
          bytes: merged[path]!,
        ),
      );
    }
    for (final path in rfwTextPaths) {
      final libraryPath = bundle.artifactLibraryPaths[path];
      if (onlyLibrary != null) {
        // An entry this library step cannot attribute to itself is never
        // this library's to include — never a reason to fail a build step
        // for a library the entry may not even belong to. Only the
        // package-wide step below, which needs every entry accounted for,
        // fails loud on a genuinely unattributed entry.
        if (libraryPath != onlyLibrary) continue;
      } else if (libraryPath == null) {
        throw StateError(
          'Generated text $path has no authored-library attribution.',
        );
      }
      entries.add(
        RestageBundleEntry(
          logicalPath: path,
          role: RestageBundleEntryRole.rfwText,
          bytes: bundle.ownedOutputs[path]!,
        ),
      );
    }
    entries.sort(
      (left, right) =>
          compareGeneratedOutputPaths(left.logicalPath, right.logicalPath),
    );
    return entries;
  }

  String _renderInspectionReport(RestageBundle bundle) {
    final buffer = StringBuffer()
      ..writeln('# ${bundle.authoredLibraryPath}')
      ..writeln()
      ..writeln('Package: `${bundle.packageName}`')
      ..writeln();
    for (final entry in bundle.entries) {
      buffer
        ..writeln('## ${entry.logicalPath}')
        ..writeln()
        ..writeln('- role: `${entry.role.wireName}`')
        ..writeln('- length: ${entry.byteLength}')
        ..writeln('- sha256: `${entry.sha256}`')
        ..writeln();
      if (entry.logicalPath.endsWith('.json')) {
        buffer
          ..writeln('```json')
          ..writeln(utf8.decode(entry.bytes))
          ..writeln('```')
          ..writeln();
      } else if (entry.logicalPath.endsWith('.rfwtxt')) {
        buffer
          ..writeln('```text')
          ..writeln(utf8.decode(entry.bytes))
          ..writeln('```')
          ..writeln();
      } else {
        buffer
          ..writeln('Binary artifact; content omitted.')
          ..writeln();
      }
    }
    return buffer.toString();
  }
}

String _sha256Hex(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';
