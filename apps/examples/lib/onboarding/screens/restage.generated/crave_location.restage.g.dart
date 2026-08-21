part of '../crave_location.dart';

const craveLocationScreenRef = NeutralFlowScreenRef(
  id: 'crave_location',
  artifactPath: 'crave_location.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use craveLocationScreenRef')
abstract final class CraveLocationScreenDescriptor {
  const CraveLocationScreenDescriptor._();

  static const NeutralFlowScreenRef ref = craveLocationScreenRef;
}
