part of '../stride_ready.dart';

// ignore_for_file: type=lint, unnecessary_cast

const strideReadyScreenRef = NeutralFlowScreenRef(
  id: 'stride_ready',
  artifactPath: 'stride_ready.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use strideReadyScreenRef')
abstract final class StrideReadyScreenDescriptor {
  const StrideReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideReadyScreenRef;
}
