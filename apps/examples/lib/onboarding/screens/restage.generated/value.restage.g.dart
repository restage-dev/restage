part of '../value.dart';

// ignore_for_file: type=lint

const valueScreenRef = NeutralFlowScreenRef(
  id: 'value',
  artifactPath: 'value.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use valueScreenRef')
abstract final class ValueScreenDescriptor {
  const ValueScreenDescriptor._();

  static const NeutralFlowScreenRef ref = valueScreenRef;
}
