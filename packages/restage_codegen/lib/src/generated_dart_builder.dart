// Owns each library's `<stem>.restage.g.dart` output once.
// Uses the shared compiler result and the resolved output location.

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';
import 'package:restage_codegen/src/surface_publication/output_location_registry.dart';
import 'package:restage_codegen/src/surface_publication/preserved_outputs.dart';

/// Writes each authored library's one generated Dart part.
final class RestageGeneratedDartBuilder implements Builder {
  /// Creates the builder, resolving and validating output location options once.
  RestageGeneratedDartBuilder(BuilderOptions options)
      : plan = RestageOutputLocationPlan.fromBuilderOptions(options);

  /// The resolved output location authority for this builder invocation.
  final RestageOutputLocationPlan plan;

  @override
  Map<String, List<String>> get buildExtensions =>
      plan.generatedDartBuildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    await registerRestageOutputLocationSignature(
      buildStep,
      plan,
      builderKey: 'restage_codegen:generated_dart',
    );

    final libraryPath = buildStep.inputId.path;
    if (!isAuthoredDartLibraryAsset(buildStep.inputId)) return;

    final bundle = await readRestageCompilerHandoff(buildStep);
    if (bundle == null) {
      await restorePreservedOutput(
        buildStep,
        neutralPartPath(plan, libraryPath),
      );
      return;
    }

    // Both builders must resolve the same output location. Report a mismatch
    // here before it causes an unexplained missing generated part.
    final partPath = neutralPartPath(plan, libraryPath);
    final source = bundle.ownedOutputs[partPath];
    if (source == null) {
      _rejectPlacementDivergence(bundle, libraryPath: libraryPath);
      return;
    }

    await buildStep.writeAsBytes(
      AssetId(buildStep.inputId.package, partPath),
      source,
    );
  }

  /// Fails loudly when the handoff carries this library's generated part at a
  /// path this builder's output location does not resolve to.
  void _rejectPlacementDivergence(
    RestageSurfacePublicationBundle bundle, {
    required String libraryPath,
  }) {
    final stem = p.posix.basenameWithoutExtension(libraryPath);
    final elsewhere = bundle.ownedOutputs.keys
        .where(
          (path) =>
              path.endsWith(kNeutralGeneratedPartSuffix) &&
              p.posix.basename(path) == '$stem$kNeutralGeneratedPartSuffix',
        )
        .toList()
      ..sort();
    if (elsewhere.isEmpty) return;
    throw StateError(
      'Placement options divergence between Restage builder targets: the '
      'generated part for $libraryPath was compiled at ${elsewhere.join(', ')} '
      'but this builder resolved ${neutralPartPath(plan, libraryPath)} from '
      '[${restageOutputLocationSignature(plan)}]. Every placement-affected Restage '
      'builder key must carry identical placement options. In build.yaml, set '
      'the same options on each restage_codegen builder key under targets; a '
      'YAML anchor lets you write the values once. Do not set them under '
      'global_options: root global_options overrides the options every '
      'package in the build sets for itself.',
    );
  }
}
