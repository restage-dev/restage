part of '../starter_done_explore.dart';

const starterDoneExploreScreenRef = NeutralFlowScreenRef(
  id: 'starter_done_explore',
  artifactPath: 'starter_done_explore.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use starterDoneExploreScreenRef')
abstract final class StarterDoneExploreScreenDescriptor {
  const StarterDoneExploreScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterDoneExploreScreenRef;
}
