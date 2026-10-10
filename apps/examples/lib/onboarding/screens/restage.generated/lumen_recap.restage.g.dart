part of '../lumen_recap.dart';

// ignore_for_file: type=lint

const lumenRecapScreenRef = NeutralFlowScreenRef(
  id: 'lumen_recap',
  artifactPath: 'lumen_recap.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use lumenRecapScreenRef')
abstract final class LumenRecapScreenDescriptor {
  const LumenRecapScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenRecapScreenRef;
}
