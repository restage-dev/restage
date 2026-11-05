part of '../lumen_experience.dart';

// ignore_for_file: type=lint, unnecessary_cast

const lumenExperienceScreenRef = NeutralFlowScreenRef(
  id: 'lumen_experience',
  artifactPath: 'lumen_experience.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use lumenExperienceScreenRef')
abstract final class LumenExperienceScreenDescriptor {
  const LumenExperienceScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenExperienceScreenRef;
}
