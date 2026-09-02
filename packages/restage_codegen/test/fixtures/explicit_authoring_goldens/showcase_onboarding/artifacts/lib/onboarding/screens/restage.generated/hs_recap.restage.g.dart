part of '../hs_recap.dart';

const hsRecapScreenRef = NeutralFlowScreenRef(
  id: 'hs_recap',
  artifactPath: 'hs_recap.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use hsRecapScreenRef')
abstract final class HsRecapScreenDescriptor {
  const HsRecapScreenDescriptor._();

  static const NeutralFlowScreenRef ref = hsRecapScreenRef;
}
