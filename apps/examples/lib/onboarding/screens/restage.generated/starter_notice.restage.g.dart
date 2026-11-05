part of '../starter_notice.dart';

// ignore_for_file: type=lint, unnecessary_cast

const starterNoticeScreenRef = NeutralFlowScreenRef(
  id: 'starter_notice',
  artifactPath: 'starter_notice.rfw',
  version: 1,
  minClient: 17,
);

@Deprecated('Use starterNoticeScreenRef')
abstract final class StarterNoticeScreenDescriptor {
  const StarterNoticeScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterNoticeScreenRef;
}
