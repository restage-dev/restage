part of 'tally_savings.dart';

abstract final class TallySavingsScreenDescriptor {
  const TallySavingsScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'tally_savings',
    artifactPath: 'tally_savings.rfw',
    version: 1,
    minClient: 1,
  );
}
