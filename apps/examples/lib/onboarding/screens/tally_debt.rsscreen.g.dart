part of 'tally_debt.dart';

abstract final class TallyDebtScreenDescriptor {
  const TallyDebtScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'tally_debt',
    artifactPath: 'tally_debt.rfw',
    version: 1,
    minClient: 1,
  );
}
