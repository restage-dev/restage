part of '../starter_done_explore.dart';

// ignore_for_file: type=lint

const starterDoneExploreScreenRef = NeutralFlowScreenRef(
  id: 'starter_done_explore',
  artifactPath: 'starter_done_explore.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use starterDoneExploreScreenRef')
abstract final class StarterDoneExploreScreenDescriptor {
  const StarterDoneExploreScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterDoneExploreScreenRef;
}
