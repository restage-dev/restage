part of '../tally_recap_savings.dart';

abstract final class TallyRecapSavingsScreenDescriptor {
  const TallyRecapSavingsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'tally_recap_savings',
    artifactPath: 'tally_recap_savings.rfw',
    version: 1,
    minClient: 1,
  );
}
