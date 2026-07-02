part of 'crave_location.dart';

abstract final class CraveLocationScreenDescriptor {
  const CraveLocationScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'crave_location',
    artifactPath: 'crave_location.rfw',
    version: 1,
    minClient: 1,
  );
}
