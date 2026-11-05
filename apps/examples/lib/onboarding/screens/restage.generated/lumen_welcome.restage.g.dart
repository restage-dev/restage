part of '../lumen_welcome.dart';

// ignore_for_file: type=lint, unnecessary_cast

const lumenWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'lumen_welcome',
  artifactPath: 'lumen_welcome.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use lumenWelcomeScreenRef')
abstract final class LumenWelcomeScreenDescriptor {
  const LumenWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = lumenWelcomeScreenRef;
}
