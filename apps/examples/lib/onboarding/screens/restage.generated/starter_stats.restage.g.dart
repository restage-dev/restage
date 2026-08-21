part of '../starter_stats.dart';

const starterStatsScreenRef = NeutralFlowScreenRef(
  id: 'starter_stats',
  artifactPath: 'starter_stats.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use starterStatsScreenRef')
abstract final class StarterStatsScreenDescriptor {
  const StarterStatsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterStatsScreenRef;
}
