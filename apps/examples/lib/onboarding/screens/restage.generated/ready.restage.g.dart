part of '../ready.dart';

// ignore_for_file: type=lint

const readyScreenRef = NeutralFlowScreenRef(
  id: 'ready',
  artifactPath: 'ready.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use readyScreenRef')
abstract final class ReadyScreenDescriptor {
  const ReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = readyScreenRef;
}
