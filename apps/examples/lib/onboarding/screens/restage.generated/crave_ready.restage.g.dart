part of '../crave_ready.dart';

// ignore_for_file: type=lint, unnecessary_cast

const craveReadyScreenRef = NeutralFlowScreenRef(
  id: 'crave_ready',
  artifactPath: 'crave_ready.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use craveReadyScreenRef')
abstract final class CraveReadyScreenDescriptor {
  const CraveReadyScreenDescriptor._();

  static const NeutralFlowScreenRef ref = craveReadyScreenRef;
}
