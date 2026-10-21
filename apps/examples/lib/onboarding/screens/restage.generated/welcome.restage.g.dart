part of '../welcome.dart';

// ignore_for_file: type=lint

const welcomeScreenRef = NeutralFlowScreenRef(
  id: 'welcome',
  artifactPath: 'welcome.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use welcomeScreenRef')
abstract final class WelcomeScreenDescriptor {
  const WelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = welcomeScreenRef;
}
