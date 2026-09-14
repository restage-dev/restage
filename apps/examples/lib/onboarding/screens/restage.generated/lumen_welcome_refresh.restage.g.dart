part of '../lumen_welcome_refresh.dart';

const lumenWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'lumen_welcome_refresh',
  artifactPath: 'lumen_welcome_refresh.rfw',
  version: 1,
  minClient: 6,
);

@Deprecated('Use lumenWelcomeScreenRef')
abstract final class LumenWelcomeScreenDescriptor {
  const LumenWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenWelcomeScreenRef;
}
