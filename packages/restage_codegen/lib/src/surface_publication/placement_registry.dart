// The one cross-builder record of a package's resolved output placement.
//
// Build Runner has no cross-builder options channel, so every
// placement-affected Restage builder key accepts the same options with the
// same defaults, and "configure it once" is honest only through root global
// options or through repeating the same target options on each key. Two keys
// resolving different placement for one package is therefore possible, and it
// would otherwise surface as a silently missing or misplaced output.
//
// Every placement-affected builder registers here — including the ones that
// only read a placement plan and never compile surfaces, and so have no other
// reason to meet.

import 'package:build/build.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';

/// Records [plan] as the resolved placement for this build step's package.
///
/// Throws [StateError] naming both signatures when another Restage builder
/// already registered a different placement for the same package.
Future<void> registerRestagePlacementSignature(
  BuildStep buildStep,
  RestageOutputPlacementPlan plan,
) async {
  final registry = await buildStep.fetchResource(_placementRegistryResource);
  registry.record(buildStep.inputId.package, plan);
}

final Resource<_PlacementRegistry> _placementRegistryResource =
    Resource<_PlacementRegistry>(_PlacementRegistry.new);

final class _PlacementRegistry {
  final Map<String, String> _byPackage = {};

  void record(String package, RestageOutputPlacementPlan plan) {
    final signature = restagePlacementSignature(plan);
    final previous = _byPackage[package];
    if (previous != null && previous != signature) {
      throw StateError(
        'Placement options divergence between Restage builder targets for '
        'package $package: one builder resolved [$previous] while another '
        'resolved [$signature]. Every placement-affected Restage builder key '
        'must be configured with the same options — set them once under '
        'global_options, or repeat them identically on each target.',
      );
    }
    _byPackage[package] = signature;
  }
}
