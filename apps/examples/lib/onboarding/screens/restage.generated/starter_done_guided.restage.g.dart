part of '../starter_done_guided.dart';

// ignore_for_file: type=lint

const starterDoneGuidedScreenRef = NeutralFlowScreenRef(
  id: 'starter_done_guided',
  artifactPath: 'starter_done_guided.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use starterDoneGuidedScreenRef')
abstract final class StarterDoneGuidedScreenDescriptor {
  const StarterDoneGuidedScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterDoneGuidedScreenRef;
}
