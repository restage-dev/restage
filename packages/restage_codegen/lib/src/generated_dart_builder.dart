// The single owner of per-library generated Dart.
//
// Exactly one builder declares and writes the `<stem>.restage.g.dart` family,
// so a library holding a screen, a flow, or both never has two builders
// claiming one output. Content comes from the same fixed compiler handoff the
// portable-output builder reads; this builder only decides placement and
// materialization.

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/placement_registry.dart';

/// Writes each authored library's one generated Dart part.
final class RestageGeneratedDartBuilder implements Builder {
  /// Creates the builder, resolving and validating placement options once.
  RestageGeneratedDartBuilder(BuilderOptions options)
      : plan = RestageOutputPlacementPlan.fromBuilderOptions(options);

  /// The resolved placement authority for this builder invocation.
  final RestageOutputPlacementPlan plan;

  @override
  Map<String, List<String>> get buildExtensions =>
      plan.generatedDartBuildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    await registerRestagePlacementSignature(buildStep, plan);

    final libraryPath = buildStep.inputId.path;
    if (!isAuthoredDartLibraryAsset(buildStep.inputId)) return;

    final bundle = await readRestageCompilerHandoff(buildStep);
    if (bundle == null) return;

    // The compiler keys generated parts by the same plan-resolved path this
    // builder declares, so agreement is by construction rather than by a
    // second derivation — provided both builders were configured with the
    // same placement options. When they were not, the part exists in the
    // handoff at a path this builder cannot write, and the developer sees an
    // unexplained missing output. Name the real cause instead.
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
  /// path this builder's placement does not resolve to.
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
      '[${restagePlacementSignature(plan)}]. Every placement-affected Restage '
      'builder key must be configured with the same options — set them once '
      'under global_options, or repeat them identically on each target.',
    );
  }
}
