part of '../tally_savings.dart';

const tallySavingsScreenRef = NeutralFlowScreenRef(
  id: 'tally_savings',
  artifactPath: 'tally_savings.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use tallySavingsScreenRef')
abstract final class TallySavingsScreenDescriptor {
  const TallySavingsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallySavingsScreenRef;
}
