part of '../stride_ready.dart';

abstract final class StrideReadyScreenDescriptor {
  const StrideReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'stride_ready',
    artifactPath: 'stride_ready.rfw',
    version: 1,
    minClient: 1,
  );
}
