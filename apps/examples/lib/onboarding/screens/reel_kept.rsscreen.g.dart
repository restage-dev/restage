part of 'reel_kept.dart';

abstract final class ReelKeptScreenDescriptor {
  const ReelKeptScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'reel_kept',
    artifactPath: 'reel_kept.rfw',
    version: 1,
    minClient: 1,
  );
}
