part of '../tally_debt.dart';

// ignore_for_file: type=lint

const tallyDebtScreenRef = NeutralFlowScreenRef(
  id: 'tally_debt',
  artifactPath: 'tally_debt.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use tallyDebtScreenRef')
abstract final class TallyDebtScreenDescriptor {
  const TallyDebtScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyDebtScreenRef;
}
