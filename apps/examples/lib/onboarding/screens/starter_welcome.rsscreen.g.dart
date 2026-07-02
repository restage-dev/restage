part of 'starter_welcome.dart';

abstract final class StarterWelcomeScreenDescriptor {
  const StarterWelcomeScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'starter_welcome',
    artifactPath: 'starter_welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
