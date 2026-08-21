part of '../starter_bare_surface.dart';

const starterBareSurfaceScreenRef = NeutralFlowScreenRef(
  id: 'starter_bare_surface',
  artifactPath: 'starter_bare_surface.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use starterBareSurfaceScreenRef')
abstract final class StarterBareSurfaceScreenDescriptor {
  const StarterBareSurfaceScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterBareSurfaceScreenRef;
}
