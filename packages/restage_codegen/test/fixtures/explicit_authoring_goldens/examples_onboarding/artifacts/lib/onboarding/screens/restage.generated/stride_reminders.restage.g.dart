part of '../stride_reminders.dart';

const strideRemindersScreenRef = NeutralFlowScreenRef(
  id: 'stride_reminders',
  artifactPath: 'stride_reminders.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use strideRemindersScreenRef')
abstract final class StrideRemindersScreenDescriptor {
  const StrideRemindersScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideRemindersScreenRef;
}
