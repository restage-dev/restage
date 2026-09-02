part of '../stride_ready.dart';

const strideReadyScreenRef = NeutralFlowScreenRef(
  id: 'stride_ready',
  artifactPath: 'stride_ready.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use strideReadyScreenRef')
abstract final class StrideReadyScreenDescriptor {
  const StrideReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideReadyScreenRef;
}
