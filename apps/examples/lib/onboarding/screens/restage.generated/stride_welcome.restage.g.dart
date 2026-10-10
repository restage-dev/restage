part of '../stride_welcome.dart';

// ignore_for_file: type=lint

const strideWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'stride_welcome',
  artifactPath: 'stride_welcome.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use strideWelcomeScreenRef')
abstract final class StrideWelcomeScreenDescriptor {
  const StrideWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideWelcomeScreenRef;
}
