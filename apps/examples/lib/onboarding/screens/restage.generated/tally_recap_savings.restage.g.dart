part of '../tally_recap_savings.dart';

const tallyRecapSavingsScreenRef = NeutralFlowScreenRef(
  id: 'tally_recap_savings',
  artifactPath: 'tally_recap_savings.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use tallyRecapSavingsScreenRef')
abstract final class TallyRecapSavingsScreenDescriptor {
  const TallyRecapSavingsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyRecapSavingsScreenRef;
}
