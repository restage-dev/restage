part of '../lumen_welcome.dart';

const lumenWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'lumen_welcome',
  artifactPath: 'lumen_welcome.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use lumenWelcomeScreenRef')
abstract final class LumenWelcomeScreenDescriptor {
  const LumenWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenWelcomeScreenRef;
}
