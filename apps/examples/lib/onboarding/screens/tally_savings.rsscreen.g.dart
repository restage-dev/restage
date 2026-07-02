part of 'tally_savings.dart';

abstract final class TallySavingsScreenDescriptor {
  const TallySavingsScreenDescriptor._();

  static const SurfaceScreenRef ref = SurfaceScreenRef(
    id: 'tally_savings',
    artifactPath: 'tally_savings.rfw',
    version: 1,
    minClient: 1,
  );
}
