part of '../tally_recap_invest.dart';

const tallyRecapInvestScreenRef = NeutralFlowScreenRef(
  id: 'tally_recap_invest',
  artifactPath: 'tally_recap_invest.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use tallyRecapInvestScreenRef')
abstract final class TallyRecapInvestScreenDescriptor {
  const TallyRecapInvestScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyRecapInvestScreenRef;
}
