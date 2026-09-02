part of '../hs_experience.dart';

const hsExperienceScreenRef = NeutralFlowScreenRef(
  id: 'hs_experience',
  artifactPath: 'hs_experience.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use hsExperienceScreenRef')
abstract final class HsExperienceScreenDescriptor {
  const HsExperienceScreenDescriptor._();

  static const NeutralFlowScreenRef ref = hsExperienceScreenRef;
}
