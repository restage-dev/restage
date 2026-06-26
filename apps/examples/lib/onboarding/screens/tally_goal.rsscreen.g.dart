part of 'tally_goal.dart';

abstract final class TallyGoalScreenDescriptor {
  const TallyGoalScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'tally_goal',
    artifactPath: 'tally_goal.rfw',
    version: 1,
    minClient: 1,
  );
}
