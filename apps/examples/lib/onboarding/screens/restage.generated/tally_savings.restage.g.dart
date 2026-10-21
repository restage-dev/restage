part of '../tally_savings.dart';

// ignore_for_file: type=lint

const tallySavingsScreenRef = NeutralFlowScreenRef(
  id: 'tally_savings',
  artifactPath: 'tally_savings.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use tallySavingsScreenRef')
abstract final class TallySavingsScreenDescriptor {
  const TallySavingsScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallySavingsScreenRef;
}
