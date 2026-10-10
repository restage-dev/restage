part of '../tally_recap_invest.dart';

// ignore_for_file: type=lint

const tallyRecapInvestScreenRef = NeutralFlowScreenRef(
  id: 'tally_recap_invest',
  artifactPath: 'tally_recap_invest.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use tallyRecapInvestScreenRef')
abstract final class TallyRecapInvestScreenDescriptor {
  const TallyRecapInvestScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyRecapInvestScreenRef;
}
