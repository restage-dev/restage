part of 'lumen_recap.dart';

abstract final class LumenRecapScreenDescriptor {
  const LumenRecapScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'lumen_recap',
    artifactPath: 'lumen_recap.rfw',
    version: 1,
    minClient: 1,
  );
}
