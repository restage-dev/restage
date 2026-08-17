// The one cross-builder record of a package's resolved output placement.
//
// Build Runner has no cross-builder options channel, so every
// placement-affected Restage builder key accepts the same options with the
// same defaults, and the honest configuration is the same target options
// repeated on each key (a YAML anchor writes the values once). Root
// global_options is not a remedy: it is itself keyed per builder, and it
// overrides the options every package in the build sets for itself. Two keys
// resolving different placement for one package is therefore possible, and it
// would otherwise surface as a silently missing or misplaced output.
//
// Every placement-affected builder registers here — including the ones that
// only read a placement plan and never compile surfaces, and so have no other
// reason to meet.

import 'package:build/build.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';

/// Records [plan] as the resolved placement for this build step's package,
/// claimed by [builderKey] (the `build.yaml` key, for diagnostics only).
///
/// Throws [StateError] naming both builder keys and both signatures when
/// another Restage builder already registered a different placement for the
/// same package.
Future<void> registerRestagePlacementSignature(
  BuildStep buildStep,
  RestageOutputPlacementPlan plan, {
  required String builderKey,
}) async {
  final registry = await buildStep.fetchResource(_placementRegistryResource);
  registry.record(buildStep.inputId.package, plan, builderKey);
}

final Resource<_PlacementRegistry> _placementRegistryResource =
    Resource<_PlacementRegistry>(_PlacementRegistry.new);

final class _PlacementRegistry {
  final Map<String, ({String signature, String builderKey})> _byPackage = {};

  void record(
    String package,
    RestageOutputPlacementPlan plan,
    String builderKey,
  ) {
    final signature = restagePlacementSignature(plan);
    final previous = _byPackage[package];
    if (previous == null) {
      _byPackage[package] = (signature: signature, builderKey: builderKey);
      return;
    }
    if (previous.signature != signature) {
      throw StateError(
        'Placement options divergence between Restage builder targets for '
        'package $package: ${previous.builderKey} resolved '
        '[${previous.signature}] while $builderKey resolved [$signature]. '
        'Every placement-affected Restage builder key must carry identical '
        'placement options. In build.yaml, set the same options on each '
        'restage_codegen builder key under targets; a YAML anchor lets you '
        'write the values once. Do not set them under global_options: root '
        'global_options overrides the options every package in the build '
        'sets for itself.',
      );
    }
  }
}
