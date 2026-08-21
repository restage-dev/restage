part of '../tally_invest.dart';

const tallyInvestScreenRef = NeutralFlowScreenRef(
  id: 'tally_invest',
  artifactPath: 'tally_invest.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use tallyInvestScreenRef')
abstract final class TallyInvestScreenDescriptor {
  const TallyInvestScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyInvestScreenRef;
}
