import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        InstalledCapability,
        SurfaceFitEvaluator,
        SurfaceFitRequirementV1,
        SurfaceFitVerdictV1,
        SurfaceHostContractV1;

final _verdicts =
    Expando<Map<(String, String), SurfaceFitVerdictV1>>('placement fit');

/// Whether [requirement] fits [host] on [installed], judged once per host and
/// installed runtime.
@internal
SurfaceFitVerdictV1 placementFitVerdict({
  required SurfaceHostContractV1 host,
  required SurfaceFitRequirementV1 requirement,
  required InstalledCapability installed,
}) =>
    (_verdicts[requirement] ??=
            {})[(host.contentHash, installed.contentHash)] ??=
        SurfaceFitEvaluator.evaluate(
            host: host, requirement: requirement, installed: installed);

/// Records a verdict judged elsewhere for the host and runtime with these
/// hashes.
@internal
void notePlacementFitVerdict(SurfaceFitRequirementV1 requirement,
        String hostHash, String installedHash, SurfaceFitVerdictV1 verdict) =>
    (_verdicts[requirement] ??= {})[(hostHash, installedHash)] = verdict;
