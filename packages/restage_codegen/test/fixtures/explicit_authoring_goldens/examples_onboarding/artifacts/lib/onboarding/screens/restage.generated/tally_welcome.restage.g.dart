part of '../tally_welcome.dart';

const tallyWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'tally_welcome',
  artifactPath: 'tally_welcome.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use tallyWelcomeScreenRef')
abstract final class TallyWelcomeScreenDescriptor {
  const TallyWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = tallyWelcomeScreenRef;
}
