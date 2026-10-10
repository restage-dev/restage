part of '../starter_welcome.dart';

// ignore_for_file: type=lint

const starterWelcomeScreenRef = NeutralFlowScreenRef(
  id: 'starter_welcome',
  artifactPath: 'starter_welcome.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use starterWelcomeScreenRef')
abstract final class StarterWelcomeScreenDescriptor {
  const StarterWelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterWelcomeScreenRef;
}
