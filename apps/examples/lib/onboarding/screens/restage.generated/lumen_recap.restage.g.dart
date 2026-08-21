part of '../lumen_recap.dart';

const lumenRecapScreenRef = NeutralFlowScreenRef(
  id: 'lumen_recap',
  artifactPath: 'lumen_recap.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use lumenRecapScreenRef')
abstract final class LumenRecapScreenDescriptor {
  const LumenRecapScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenRecapScreenRef;
}
