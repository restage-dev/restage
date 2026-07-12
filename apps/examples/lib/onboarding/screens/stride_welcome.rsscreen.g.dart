part of 'stride_welcome.dart';

abstract final class StrideWelcomeScreenDescriptor {
  const StrideWelcomeScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'stride_welcome',
    artifactPath: 'stride_welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
