part of '../lumen_experience.dart';

const lumenExperienceScreenRef = NeutralFlowScreenRef(
  id: 'lumen_experience',
  artifactPath: 'lumen_experience.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use lumenExperienceScreenRef')
abstract final class LumenExperienceScreenDescriptor {
  const LumenExperienceScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenExperienceScreenRef;
}
