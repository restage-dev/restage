part of '../welcome.dart';

abstract final class WelcomeScreenDescriptor {
  const WelcomeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'welcome',
    artifactPath: 'welcome.rfw',
    version: 1,
    minClient: 1,
  );
}
