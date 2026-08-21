part of '../welcome.dart';

const welcomeScreenRef = NeutralFlowScreenRef(
  id: 'welcome',
  artifactPath: 'welcome.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use welcomeScreenRef')
abstract final class WelcomeScreenDescriptor {
  const WelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = welcomeScreenRef;
}
