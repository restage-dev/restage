part of '../starter_bare_surface.dart';

// ignore_for_file: type=lint

const starterBareSurfaceScreenRef = NeutralFlowScreenRef(
  id: 'starter_bare_surface',
  artifactPath: 'starter_bare_surface.rfw',
  version: 1,
  minClient: 9,
);

@Deprecated('Use starterBareSurfaceScreenRef')
abstract final class StarterBareSurfaceScreenDescriptor {
  const StarterBareSurfaceScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterBareSurfaceScreenRef;
}
