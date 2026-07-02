part of 'crave_ready.dart';

abstract final class CraveReadyScreenDescriptor {
  const CraveReadyScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'crave_ready',
    artifactPath: 'crave_ready.rfw',
    version: 1,
    minClient: 1,
  );
}
