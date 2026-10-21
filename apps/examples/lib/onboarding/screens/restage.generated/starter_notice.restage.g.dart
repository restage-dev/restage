part of '../starter_notice.dart';

// ignore_for_file: type=lint

const starterNoticeScreenRef = NeutralFlowScreenRef(
  id: 'starter_notice',
  artifactPath: 'starter_notice.rfw',
  version: 1,
  minClient: 12,
);

@Deprecated('Use starterNoticeScreenRef')
abstract final class StarterNoticeScreenDescriptor {
  const StarterNoticeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterNoticeScreenRef;
}
