part of '../ready.dart';

const readyScreenRef = NeutralFlowScreenRef(
  id: 'ready',
  artifactPath: 'ready.rfw',
  version: 1,
  minClient: 6,
);

@Deprecated('Use readyScreenRef')
abstract final class ReadyScreenDescriptor {
  const ReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = readyScreenRef;
}
