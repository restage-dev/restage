part of '../hs_welcome.dart';

const hsWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'hs_welcome',
  artifactPath: 'hs_welcome.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use hsWelcomeScreenRef')
abstract final class HsWelcomeScreenDescriptor {
  const HsWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = hsWelcomeScreenRef;
}
