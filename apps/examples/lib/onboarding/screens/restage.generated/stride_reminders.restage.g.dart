part of '../stride_reminders.dart';

// ignore_for_file: type=lint

const strideRemindersScreenRef = NeutralFlowScreenRef(
  id: 'stride_reminders',
  artifactPath: 'stride_reminders.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use strideRemindersScreenRef')
abstract final class StrideRemindersScreenDescriptor {
  const StrideRemindersScreenDescriptor._();

  static const NeutralFlowScreenRef ref = strideRemindersScreenRef;
}
