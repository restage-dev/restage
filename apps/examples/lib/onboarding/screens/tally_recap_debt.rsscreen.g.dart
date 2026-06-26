part of 'tally_recap_debt.dart';

abstract final class TallyRecapDebtScreenDescriptor {
  const TallyRecapDebtScreenDescriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: 'tally_recap_debt',
    artifactPath: 'tally_recap_debt.rfw',
    version: 1,
    minClient: 1,
  );
}
