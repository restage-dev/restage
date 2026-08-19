part of '../tally_welcome.dart';

abstract final class TallyWelcomeScreenDescriptor {
  const TallyWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'tally_welcome',
    artifactPath: 'tally_welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
