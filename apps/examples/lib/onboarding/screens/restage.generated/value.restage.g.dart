part of '../value.dart';

const valueScreenRef = NeutralFlowScreenRef(
  id: 'value',
  artifactPath: 'value.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use valueScreenRef')
abstract final class ValueScreenDescriptor {
  const ValueScreenDescriptor._();

  static const NeutralFlowScreenRef ref = valueScreenRef;
}
