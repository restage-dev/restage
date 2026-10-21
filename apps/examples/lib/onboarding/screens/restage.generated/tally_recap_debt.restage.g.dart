part of '../tally_recap_debt.dart';

// ignore_for_file: type=lint

const tallyRecapDebtScreenRef = NeutralFlowScreenRef(
  id: 'tally_recap_debt',
  artifactPath: 'tally_recap_debt.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use tallyRecapDebtScreenRef')
abstract final class TallyRecapDebtScreenDescriptor {
  const TallyRecapDebtScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyRecapDebtScreenRef;
}
