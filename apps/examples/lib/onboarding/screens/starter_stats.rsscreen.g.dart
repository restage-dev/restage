part of 'starter_stats.dart';

abstract final class StarterStatsScreenDescriptor {
  const StarterStatsScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'starter_stats',
    artifactPath: 'starter_stats.rfw',
    version: 1,
    minClient: 1,
  );
}
