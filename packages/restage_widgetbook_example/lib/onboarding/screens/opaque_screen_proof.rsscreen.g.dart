part of 'opaque_screen_proof.dart';

abstract final class OpaqueScreenProofDescriptor {
  const OpaqueScreenProofDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'opaque_screen_proof',
    artifactPath: 'opaque_screen_proof.rfw',
    version: 1,
    minClient: 1,
  );
}
