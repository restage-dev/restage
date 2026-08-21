part of '../starter_notice.dart';

const starterNoticeScreenRef = NeutralFlowScreenRef(
  id: 'starter_notice',
  artifactPath: 'starter_notice.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use starterNoticeScreenRef')
abstract final class StarterNoticeScreenDescriptor {
  const StarterNoticeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterNoticeScreenRef;
}
