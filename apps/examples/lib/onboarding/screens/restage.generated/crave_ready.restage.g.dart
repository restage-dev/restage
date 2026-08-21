part of '../crave_ready.dart';

const craveReadyScreenRef = NeutralFlowScreenRef(
  id: 'crave_ready',
  artifactPath: 'crave_ready.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use craveReadyScreenRef')
abstract final class CraveReadyScreenDescriptor {
  const CraveReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = craveReadyScreenRef;
}
