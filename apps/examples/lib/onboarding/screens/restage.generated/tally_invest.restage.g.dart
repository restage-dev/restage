part of '../tally_invest.dart';

abstract final class TallyInvestScreenDescriptor {
  const TallyInvestScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'tally_invest',
    artifactPath: 'tally_invest.rfw',
    version: 1,
    minClient: 1,
  );
}
