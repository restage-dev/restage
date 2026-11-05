part of '../tally_invest.dart';

// ignore_for_file: type=lint, unnecessary_cast

const tallyInvestScreenRef = NeutralFlowScreenRef(
  id: 'tally_invest',
  artifactPath: 'tally_invest.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use tallyInvestScreenRef')
abstract final class TallyInvestScreenDescriptor {
  const TallyInvestScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyInvestScreenRef;
}
