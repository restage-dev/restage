// Writes each library's deterministic `.rsbundle` and optional `.restage.md`
// report, plus the package output index and publication manifest.
// Resolves `buildExtensions` once from `RestageOutputLocationPlan`.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/generated_check_builder.dart';
import 'package:restage_codegen/src/surface_publication/legacy_output_cleanup.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';
import 'package:restage_codegen/src/surface_publication/output_location_registry.dart';
import 'package:restage_codegen/src/surface_publication/preserved_outputs.dart';
import 'package:restage_codegen/src/surface_publication/surface_capture_plan.dart';
import 'package:restage_codegen/src/surface_publication/surface_mount_diagnostics.dart';
import 'package:restage_shared/restage_shared.dart';

/// Materializes deterministic per-library bundles, optional inspection
/// reports, and the package-wide output index/publication manifest from the
/// compiler outputs, per the resolved [RestageOutputLocationPlan].
final class RestageOutputsBuilder implements Builder {
  /// Creates the builder, resolving and validating output location options once.
  RestageOutputsBuilder(
    BuilderOptions options, {
    this.priorOutputReader = noPriorGeneratedOutputs,
  }) : plan = RestageOutputLocationPlan.fromBuilderOptions(options);

  /// The resolved output location authority for this builder invocation.
  final RestageOutputLocationPlan plan;

  /// Reads the outputs a failed build writes back.
  final PriorGeneratedOutputReader priorOutputReader;

  @override
  Map<String, List<String>> get buildExtensions => plan.portableBuildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    await registerRestageOutputLocationSignature(
      buildStep,
      plan,
      builderKey: 'restage_codegen:outputs',
    );
    // Generated parts and other non-authored files own no outputs.
    if (buildStep.inputId.path != r'$package$' &&
        !isAuthoredDartLibraryAsset(buildStep.inputId)) {
      return;
    }

    final packageWide = buildStep.inputId.path == r'$package$';
    if (packageWide) {
      await warnAboutUnbundledSurfaceMounts(
        buildStep,
        bundled: plan.bundledRuntime,
      );
    }

    final bundle = await readRestageCompilerHandoff(buildStep);
    // Decided before this step writes anything. A failed build then writes
    // each prior output back exactly once.
    final failure = await _failure(buildStep, bundle);
    if (failure != null) {
      await _restorePriorOutputs(buildStep);
      if (packageWide) await _failBuild(buildStep, failure);
      return;
    }

    if (packageWide) {
      await _buildPackageWide(buildStep, bundle!);
    } else {
      await _buildForLibrary(buildStep, bundle!);
    }
  }

  /// Why this build failed, or `null` when every step it depends on succeeded.
  Future<_Failure?> _failure(
    BuildStep buildStep,
    RestageSurfacePublicationBundle? bundle,
  ) async {
    if (bundle == null) {
      final package = buildStep.inputId.package;
      final preserved = await buildStep.fetchResource(
        restagePreservedOutputsResource,
      );
      final refusal = preserved.refusalOf(package);
      // A compiler that refused in this build logged its own errors.
      if (refusal != null && refusal.isNotEmpty) {
        return (errors: refusal, logged: true);
      }
      // Only a compiler that didn't run leaves the last build's errors current.
      final prior = preserved.compiledIn(package)
          ? null
          : await _priorFailure(buildStep);
      return (
        errors: await _compilerErrors(buildStep) ?? prior ?? _kNoCompilation,
        logged: false,
      );
    }
    final uncompiled = await _generatedCheckErrors(buildStep);
    if (uncompiled.isNotEmpty) return (errors: uncompiled, logged: false);
    try {
      final measurementOutput = await _measurementOutput(buildStep);
      if (measurementOutput != null && !measurementOutput.valid) {
        return (
          errors: [
            'Measurement compilation failed: '
                '${measurementOutput.errors.join('; ')}',
          ],
          logged: false,
        );
      }
    } on Object catch (error) {
      return (
        errors: [
          'The package Measurement compiler output is invalid; package-wide '
              'Restage outputs were not materialized: $error',
        ],
        logged: false,
      );
    }
    return null;
  }

  /// Fails the build with [failure] and records why.
  Future<void> _failBuild(BuildStep buildStep, _Failure failure) async {
    if (!failure.logged) failure.errors.forEach(log.severe);
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, plan.buildResultPath),
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'result': 'failed',
        'errors': failure.errors,
      }),
    );
  }

  /// The errors the last build recorded, when it failed.
  Future<List<String>?> _priorFailure(BuildStep buildStep) async {
    final bytes = await priorOutputBytes(
      buildStep,
      plan,
      priorOutputReader,
      plan.buildResultPath,
    );
    if (bytes == null) return null;
    try {
      if (jsonDecode(utf8.decode(bytes)) case {
        'result': 'failed',
        'errors': final List<Object?> errors,
      } when errors.isNotEmpty) {
        return [for (final error in errors) '$error'];
      }
    } on FormatException {
      // An unreadable record says nothing about why.
    }
    return null;
  }

  /// This build's measurement compiler output, decoded once per package.
  Future<RestageMeasurementCompilerOutputV1?> _measurementOutput(
    BuildStep buildStep,
  ) async {
    final asset = AssetId(
      buildStep.inputId.package,
      kRestageMeasurementCompilerOutputPath,
    );
    if (!await buildStep.canRead(asset)) return null;
    final decoded = await buildStep.fetchResource(_measurementOutputs);
    return decoded.putIfAbsent(
      asset.package,
      () async => RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
        await buildStep.readAsBytes(asset),
      ),
    );
  }

  /// The compile errors the generated-part check found in this build.
  Future<List<String>> _generatedCheckErrors(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final asset = AssetId(package, kRestageGeneratedCheckPath);
    if (!await buildStep.canRead(asset)) {
      // Generated code nothing checked can't be trusted to compile.
      final noParts = await buildStep
          .findAssets(Glob('lib/**.restage.g.dart'))
          .isEmpty;
      return noParts
          ? const []
          : const [
              "Restage couldn't check that the code it generated compiles, "
                  'because `restage_codegen:generated_check` didn\'t run. '
                  'Try enabling that builder in build.yaml.',
            ];
    }
    final json = jsonDecode(await buildStep.readAsString(asset));
    if (json case {'errors': final List<Object?> errors}) {
      return [for (final error in errors) '$error'];
    }
    return const [];
  }

  /// The errors a readable compiler bundle records, if it records any.
  Future<List<String>?> _compilerErrors(BuildStep buildStep) async {
    final asset = AssetId(
      buildStep.inputId.package,
      kRestageSurfacePublicationCompilerBundlePath,
    );
    if (await buildStep.canRead(asset)) {
      try {
        final json = jsonDecode(await buildStep.readAsString(asset));
        if (json case {
          'errors': final List<Object?> errors,
        } when errors.isNotEmpty) {
          return [for (final error in errors) '$error'];
        }
      } on FormatException {
        // An unreadable result is reported as no result below.
      }
    }
    return null;
  }

  static const _kNoCompilation = [
    "Restage has no result from compiling the package's surfaces. Try "
        'running `dart run build_runner clean`, then '
        '`dart run build_runner build`.',
  ];

  /// Writes back what this step wrote last time, when the build failed.
  Future<void> _restorePriorOutputs(BuildStep buildStep) async {
    final List<String> paths;
    if (buildStep.inputId.path == r'$package$') {
      paths = <String>[
        plan.publicationManifestPath,
        plan.outputIndexPath,
        plan.measurementOutputIndexPath,
        plan.analyticsIdMetadataPath,
        plan.capturePlanPath,
        plan.customCatalogPath,
      ];
    } else {
      final placement = plan.forLibrary(buildStep.inputId.path);
      final reportPath = placement.inspectionReportPath;
      paths = <String>[
        placement.bundlePath,
        if (reportPath != null) reportPath,
      ];
    }
    for (final path in paths) {
      await restorePreservedOutput(buildStep, plan, priorOutputReader, path);
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
    final customCatalog = AssetId(
      buildStep.inputId.package,
      'lib/src/widget_catalog/catalog.json',
    );
    if (await buildStep.canRead(customCatalog)) {
      final bytes = await buildStep.readAsBytes(customCatalog);
      final catalog = decodeCatalog(utf8.decode(bytes));
      if (!catalog.libraries.keys.any(
        (library) =>
            WidgetLibrary.builtInByNamespace(library.namespace) != null,
      )) {
        await buildStep.writeAsBytes(
          AssetId(buildStep.inputId.package, plan.customCatalogPath),
          bytes,
        );
        await removeIdenticalLegacyOutput(
          buildStep,
          customCatalog.path,
          bytes,
        );
      }
    }
    final manifest = bundle.manifest;
    if (manifest == null) return;
    final AnalyticsIdControlOutputV1? analyticsIdControl;
    try {
      analyticsIdControl = await readAnalyticsIdControlOutput(buildStep);
    } on Object catch (error) {
      throw StateError('Analytics label control output is invalid: $error');
    }
    if (analyticsIdControl != null &&
        analyticsIdControl.packageName != buildStep.inputId.package) {
      throw StateError(
        'Analytics label control output names '
        '${analyticsIdControl.packageName} instead of '
        '${buildStep.inputId.package}.',
      );
    }
    final measurementOutput = await _measurementOutput(buildStep);
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
    final entries = _entriesFor(
      bundle,
    ).where((entry) => entry.role != RestageBundleEntryRole.rfwText);
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
    final capturePlanAsset = AssetId(
      buildStep.inputId.package,
      kRestageSurfaceCapturePlanCompilerPath,
    );
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, plan.capturePlanPath),
      jsonEncode({
        'version': kRestageSurfaceCapturePlanVersion,
        'generationFingerprint': index['generationFingerprint'],
        'surfaces': await buildStep.canRead(capturePlanAsset)
            ? jsonDecode(await buildStep.readAsString(capturePlanAsset))
            : const <String, Object?>{},
      }),
    );
    if (measurementOutput != null) {
      await buildStep.writeAsBytes(
        AssetId(buildStep.inputId.package, plan.measurementOutputIndexPath),
        measurementOutput.outputIndexBytes(buildStep.inputId.package),
      );
    }
    if (analyticsIdControl != null) {
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, plan.analyticsIdMetadataPath),
        analyticsIdControl.encodeJson(),
      );
    } else {
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, plan.analyticsIdMetadataPath),
        AnalyticsIdControlOutputV1(
          packageName: buildStep.inputId.package,
          publications: const <AnalyticsIdControlPublication>[],
        ).encodeJson(),
      );
    }
    await cleanLegacyRestageOutputs(buildStep.inputId.package, plan);
    // Written last: a build that stops before here records no success.
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, plan.buildResultPath),
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'result': 'succeeded',
        'generationFingerprint': index['generationFingerprint'],
        if (bundle.unfitPublications.isNotEmpty)
          'unfit': {
            for (final key in bundle.unfitPublications.keys.toList()..sort())
              key: bundle.unfitPublications[key],
          },
      }),
    );
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
    final publications =
        bundle.manifest?.publications ??
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
    final rfwTextPaths = bundle.ownedOutputs.keys.where(
      (path) => path.endsWith('.rfwtxt'),
    );

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

/// Why a build failed, and whether the step that refused already logged it.
typedef _Failure = ({List<String> errors, bool logged});

final Resource<Map<String, Future<RestageMeasurementCompilerOutputV1>>>
_measurementOutputs = Resource(
  () => <String, Future<RestageMeasurementCompilerOutputV1>>{},
);

String _sha256Hex(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';
