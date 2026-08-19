part of 'lumen_recap.dart';

abstract final class LumenRecapScreenDescriptor {
  const LumenRecapScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'lumen_recap',
    artifactPath: 'lumen_recap.rfw',
    version: 1,
    minClient: 1,
  );
}
